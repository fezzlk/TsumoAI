// Run with: node --test tests/web_auth.test.cjs
// Firebase and fetch are stubbed: these tests never log in or contact a server.
const assert = require('node:assert/strict');
const { readFileSync } = require('node:fs');
const path = require('node:path');
const test = require('node:test');
const vm = require('node:vm');

const staticDir = path.join(__dirname, '../app/static');
const readStatic = (name) => readFileSync(path.join(staticDir, name), 'utf8');

function createHarness({ sdkAvailable = true } = {}) {
  const elements = new Map();
  const calls = [];
  const downloads = [];
  let onTokenChanged;
  let response = { status: 200, body: { files: [], storage: { bucket: 'test', object_name: 'data.json' } } };
  const element = (id) => {
    if (!elements.has(id)) {
      elements.set(id, {
        textContent: '', innerHTML: '', hidden: false, disabled: false,
        style: {}, listeners: {}, children: [],
        addEventListener(event, handler) { this.listeners[event] = handler; },
        appendChild(child) { this.children.push(child); },
        click() { downloads.push(this); },
      });
    }
    return elements.get(id);
  };
  const auth = {
    currentUser: null,
    onIdTokenChanged(callback) { onTokenChanged = callback; },
    async signInWithPopup() { auth.loginCalled = true; },
    async signOut() { auth.currentUser = null; await onTokenChanged(null); },
  };
  const firebaseAuth = () => auth;
  firebaseAuth.GoogleAuthProvider = class {};
  const context = vm.createContext({
    window: {}, Headers, Blob,
    URL: { createObjectURL: () => 'blob:test', revokeObjectURL: () => {} },
    document: {
      getElementById: element,
      createElement: (type) => element(`${type}-${elements.size}`),
    },
    fetch: async (url, options) => {
      calls.push({ url, options });
      return new Response(JSON.stringify(response.body), {
        status: response.status,
        headers: { 'Content-Type': 'application/json' },
      });
    },
    ...(sdkAvailable ? { firebase: { initializeApp() {}, auth: firebaseAuth } } : {}),
  });
  vm.runInContext(readStatic('firebase_config.js'), context);
  vm.runInContext(readStatic('web_auth.js'), context);
  context.TsumoAuth = context.window.TsumoAuth;
  return {
    context, auth, calls, downloads, element,
    setResponse(status, body = {}) { response = { status, body }; },
    async signIn({ admin = false, token = 'id-token' } = {}) {
      auth.currentUser = {
        email: 'tester@example.test',
        getIdTokenResult: async () => ({ token, claims: { admin } }),
      };
      await onTokenChanged(auth.currentUser);
    },
    signOut: () => auth.signOut(),
    notifyTokenChanged: () => onTokenChanged(auth.currentUser),
  };
}

function loadFunction(harness, page, name) {
  const source = readStatic(page);
  const start = source.indexOf(`      async function ${name}(`);
  assert.notEqual(start, -1, `${name} exists`);
  const rest = source.slice(start);
  const next = rest.slice(1).search(/\n      (?:(?:async )?function |\/\* ── Event listeners)/);
  assert.notEqual(next, -1, `${name} has a following declaration boundary`);
  vm.runInContext(rest.slice(0, next + 1), harness.context);
}

test('embedded page scripts remain valid JavaScript', () => {
  for (const page of ['score_ui.html', 'score_dataset.html', 'training_data.html']) {
    for (const match of readStatic(page).matchAll(/<script>([\s\S]*?)<\/script>/g)) {
      assert.doesNotThrow(() => new vm.Script(match[1], { filename: page }));
    }
  }
});

test('anonymous submissions show a login prompt without sending a request', async () => {
  const h = createHarness();
  await h.signOut();
  await assert.rejects(h.context.TsumoAuth.fetch('/api/v1/dataset/upload'), /ログイン/);
  assert.equal(h.calls.length, 0);
  assert.equal(h.element('webLoginBtn').hidden, false);
  assert.equal(h.element('webLogoutBtn').hidden, true);
});

test('waits for restored login and preserves body and headers when attaching the ID token', async () => {
  const h = createHarness();
  const pending = h.context.TsumoAuth.fetch('/api/v1/score/feedback', {
    method: 'POST', body: '{"comment":"example"}',
    headers: new Headers({ 'Content-Type': 'application/json' }),
  });
  await Promise.resolve();
  assert.equal(h.calls.length, 0);
  await h.signIn();
  await pending;
  assert.equal(h.calls[0].options.headers.get('Authorization'), 'Bearer id-token');
  assert.equal(h.calls[0].options.headers.get('Content-Type'), 'application/json');
  assert.equal(h.calls[0].options.body, '{"comment":"example"}');
  assert.equal(h.element('webLoginBtn').hidden, true);
  assert.equal(h.element('webLogoutBtn').hidden, false);
});

test('normal users can submit but administrator reads require a true admin claim', async () => {
  const h = createHarness();
  await h.signIn();
  await h.context.TsumoAuth.fetch('/api/v1/dataset/upload', { method: 'POST' });
  for (const admin of [false, 'true']) {
    await h.signIn({ admin });
    await assert.rejects(
      h.context.TsumoAuth.fetch('/api/v1/dataset/list', {}, { admin: true }), /管理者権限/,
    );
  }
  assert.equal(h.calls.length, 1);
  await h.signIn({ admin: true, token: 'admin-token' });
  await h.context.TsumoAuth.fetch('/api/v1/dataset/list', {}, { admin: true });
  assert.equal(h.calls[1].options.headers.get('Authorization'), 'Bearer admin-token');
});

test('token changes are reflected in new requests and logout state is published', async () => {
  const h = createHarness();
  const states = [];
  h.context.TsumoAuth.subscribe((state) => states.push(state));
  await h.signIn({ token: 'first' });
  await h.context.TsumoAuth.fetch('/api/v1/score/feedback');
  await h.signIn({ token: 'refreshed' });
  await h.context.TsumoAuth.fetch('/api/v1/recognition/feedback');
  await h.element('webLogoutBtn').listeners.click();
  assert.equal(h.calls[1].options.headers.get('Authorization'), 'Bearer refreshed');
  assert.equal(states.at(-1).user, null);
  await assert.rejects(h.context.TsumoAuth.fetch('/api/v1/dataset/upload'), /ログイン/);
});

for (const change of ['logout', 'switch-user', 'same-user-new-session']) {
  test(`a ${change} while acquiring a token cancels the pending write`, async () => {
    const h = createHarness();
    await h.signIn({ token: 'old-token' });
    const oldUser = h.auth.currentUser;
    let resolveToken;
    const tokenResult = new Promise((resolve) => { resolveToken = resolve; });
    oldUser.getIdTokenResult = () => tokenResult;
    const request = h.context.TsumoAuth.fetch('/api/v1/score/feedback', { method: 'POST' });
    await Promise.resolve();
    assert.ok(resolveToken);
    await h.signOut();
    if (change === 'switch-user') await h.signIn({ token: 'new-token' });
    let restored;
    if (change === 'same-user-new-session') {
      h.auth.currentUser = oldUser;
      restored = h.notifyTokenChanged();
    }
    resolveToken({ token: 'old-token', claims: {} });
    await assert.rejects(request, /ログイン状態が変わりました/);
    await restored;
    assert.equal(h.calls.length, 0);
  });
}

test('a token refresh for the same signed-in user can still submit', async () => {
  const h = createHarness();
  await h.signIn();
  let resolveToken;
  const token = new Promise((resolve) => { resolveToken = resolve; });
  h.auth.currentUser.getIdTokenResult = () => token;
  const request = h.context.TsumoAuth.fetch('/api/v1/score/feedback', { method: 'POST' });
  await Promise.resolve();
  const notification = h.notifyTokenChanged();
  resolveToken({ token: 'refreshed-token', claims: {} });
  await notification;
  await request;
  assert.equal(h.calls[0].options.headers.get('Authorization'), 'Bearer refreshed-token');
});

for (const [status, expected] of [[401, /再度ログイン/], [403, /管理者権限/]]) {
  test(`API ${status} produces an actionable message without retrying the write`, async () => {
    const h = createHarness();
    await h.signIn();
    h.setResponse(status);
    await assert.rejects(h.context.TsumoAuth.fetch('/api/v1/score/feedback'), expected);
    assert.equal(h.calls.length, 1);
  });
}

test('unavailable Firebase SDK leaves the page usable and reports a login loading error', async () => {
  const h = createHarness({ sdkAvailable: false });
  await h.context.TsumoAuth.ready;
  assert.equal(h.element('webLoginBtn').disabled, true);
  assert.match(h.element('webAuthStatus').textContent, /再読み込み/);
  loadFunction(h, 'score_dataset.html', 'generateEntry');
  Object.assign(h.context, {
    buildPayload: () => ({ hand: {} }),
    convertToDatasetFormat: () => ({ input: {}, output: { yaku: [], han: 1, fu: 30 } }),
    openEditForm: () => {},
  });
  await h.context.generateEntry();
  assert.equal(h.calls[0].url, '/api/v1/score');
  assert.equal(h.calls[0].options.headers.Authorization, undefined);
});

for (const [fn, endpoint, statusId] of [
  ['sendFeedback', '/api/v1/score/feedback', 'feedbackStatus'],
  ['sendRecognitionFeedback', '/api/v1/recognition/feedback', 'recognitionFeedbackStatus'],
]) {
  test(`${fn} displays auth errors and posts its request with the token`, async () => {
    const h = createHarness();
    loadFunction(h, 'score_ui.html', fn);
    Object.assign(h.context, {
      value: (id) => id === 'recognitionCorrectedTiles' ? Array(14).fill('1m').join(',') : 'example',
      lastScoreRequest: {}, lastScoreResponse: {}, lastRecognitionResponse: {},
    });
    await h.signOut();
    await h.context[fn]();
    assert.match(h.element(statusId).textContent, /ログイン/);
    assert.equal(h.calls.length, 0);
    await h.signIn();
    await h.context[fn]();
    assert.equal(h.calls[0].url, endpoint);
    assert.equal(h.calls[0].options.headers.get('Authorization'), 'Bearer id-token');
  });
}

test('dataset upload works for normal users without attempting an admin list request', async () => {
  const h = createHarness();
  loadFunction(h, 'score_dataset.html', 'uploadToGcs');
  Object.assign(h.context, {
    datasetEntries: [{ input: {}, output: {} }], getContributor: () => 'tester',
    refreshGcsList: () => assert.fail('normal users must not request the admin list'),
  });
  await h.signIn();
  await h.context.uploadToGcs();
  assert.equal(h.calls[0].url, '/api/v1/dataset/upload');
  assert.equal(h.calls[0].options.headers.get('Authorization'), 'Bearer id-token');
  assert.match(h.element('uploadStatus').textContent, /アップロード完了/);
});

test('anonymous confirmation produces local JSON and keeps the editor for upload after login', async () => {
  const h = createHarness();
  loadFunction(h, 'score_dataset.html', 'confirmEntry');
  let uploaded = 0;
  let closed = 0;
  Object.assign(h.context, {
    editState: { input: { win: { jikaze: 'south', win_type: 'ron' } }, yakuList: [{ name: 'riichi', han: 1 }] },
    datasetEntries: [],
    calcPayments: () => ({ oya_payment: 0, ko_payment: 1000 }),
    renderDatasetList: () => {
      h.element('datasetJson').textContent = JSON.stringify({ entries: h.context.datasetEntries });
    },
    closeEditForm: () => { closed += 1; h.context.editState = null; },
    uploadToGcs: () => { uploaded += 1; },
  });
  h.element('editHan').value = '1';
  h.element('editFu').value = '30';
  await h.signOut();
  await h.context.confirmEntry();
  assert.equal(h.context.datasetEntries.length, 1);
  assert.equal(JSON.parse(h.element('datasetJson').textContent).entries[0].output.han, 1);
  assert.equal(closed, 0);
  assert.equal(uploaded, 0);
  assert.ok(h.context.editState);
  assert.match(h.element('uploadStatus').textContent, /JSON/);
  assert.match(h.element('uploadStatus').textContent, /ログイン/);
  await h.context.confirmEntry();
  assert.equal(h.context.datasetEntries.length, 1, 'retrying local confirmation must update the same entry');
  await h.signIn();
  await h.context.confirmEntry();
  assert.equal(h.context.datasetEntries.length, 1, 'uploading after login must not duplicate the saved entry');
  assert.equal(uploaded, 1);
});

test('dataset list, download and import enforce admin access and send tokens', async () => {
  const h = createHarness();
  for (const name of ['refreshGcsList', 'downloadGcsFile', 'loadGcsFile']) {
    loadFunction(h, 'score_dataset.html', name);
  }
  Object.assign(h.context, { gcsListGeneration: 0, datasetEntries: [], renderDatasetList() {} });
  await h.signIn();
  await h.context.refreshGcsList();
  await h.context.downloadGcsFile('dataset/test.json');
  await h.context.loadGcsFile('dataset/test.json');
  assert.equal(h.calls.length, 0);
  assert.match(h.element('gcsListStatus').textContent, /管理者権限/);
  await h.signIn({ admin: true });
  await h.context.refreshGcsList();
  await h.context.downloadGcsFile('dataset/test.json');
  await h.context.loadGcsFile('dataset/test.json');
  assert.equal(h.calls.length, 3);
  assert.ok(h.calls.every(({ options }) => options.headers.get('Authorization') === 'Bearer id-token'));
  assert.equal(h.downloads.length, 1);
  assert.equal(h.downloads[0].download, 'test.json');
});

test('a failed dataset download displays an error instead of saving error JSON', async () => {
  const h = createHarness();
  loadFunction(h, 'score_dataset.html', 'downloadGcsFile');
  await h.signIn({ admin: true });
  for (const status of [401, 403, 500]) {
    h.setResponse(status, { detail: 'failed' });
    await h.context.downloadGcsFile('dataset/test.json');
    assert.equal(h.downloads.length, 0);
    assert.match(h.element('gcsListStatus').textContent, /ダウンロード失敗/);
  }
});

for (const action of ['refreshGcsList', 'loadGcsFile', 'downloadGcsFile']) {
  for (const change of ['logout', 'switch-user', 'remove-admin']) {
  test(`${action} ignores an old administrator response after ${change}`, async () => {
    const h = createHarness();
    loadFunction(h, 'score_dataset.html', action);
    Object.assign(h.context, { gcsListGeneration: 0, datasetEntries: [], renderDatasetList() {} });
    await h.signIn({ admin: true });
    let resolveBody;
    h.context.fetch = async () => ({
      ok: true, status: 200,
      json: () => new Promise((resolve) => { resolveBody = resolve; }),
    });
    const request = h.context[action]('dataset/old-admin.json');
    for (let attempt = 0; attempt < 20 && !resolveBody; attempt += 1) await Promise.resolve();
    assert.ok(resolveBody);
    if (change === 'remove-admin') {
      h.auth.currentUser.getIdTokenResult = async () => ({ token: 'no-admin', claims: {} });
      await h.notifyTokenChanged();
    } else {
      await h.signOut();
      if (change === 'switch-user') await h.signIn({ admin: true, token: 'new-admin' });
    }
    h.context.datasetEntries.push({ currentDraft: true });
    h.element('gcsListStatus').textContent = 'logged out';
    resolveBody({ entries: [{ oldAdminData: true }], files: [{ name: 'private.json' }] });
    await request;
    assert.equal(h.element('gcsListStatus').textContent, 'logged out');
    assert.deepEqual(h.context.datasetEntries, [{ currentDraft: true }]);
    assert.equal(h.downloads.length, 0);
    assert.equal(h.element('gcsFileList').children.length, 0);
  });
  }
}
