import {after, before, test} from 'node:test';
import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';
import {createHash} from 'node:crypto';
import http from 'node:http';
import path from 'node:path';
import {fileURLToPath} from 'node:url';
import {chromium, webkit} from 'playwright';

const root = fileURLToPath(new URL('../../', import.meta.url));
const fixture = JSON.parse(await readFile(path.join(root, 'test/fixtures/web_recognition_eval_v1.json')));
let server, browser, origin;
before(async () => {
  const model = await readFile(path.join(root, 'assets/ml/tile_classifier.tflite'));
  assert.equal(createHash('sha256').update(model).digest('hex'), fixture.model_sha256);
  server = http.createServer(async (req, res) => {
    if (req.url === '/') {
      res.setHeader('Content-Type', 'text/html');
      res.end('<!doctype html><base href="/web/"><script src="classifier.js"></script>');
      return;
    }
    const file = path.resolve(root, '.' + new URL(req.url, 'http://localhost').pathname);
    if (!file.startsWith(root)) { res.writeHead(403); res.end(); return; }
    try {
      const data = await readFile(file);
      res.setHeader('Content-Type', file.endsWith('.wasm') ? 'application/wasm' : file.endsWith('.js') ? 'text/javascript' : 'application/octet-stream');
      res.end(data);
    } catch { res.writeHead(404); res.end(); }
  });
  await new Promise(resolve => server.listen(0, '127.0.0.1', resolve));
  origin = `http://127.0.0.1:${server.address().port}`;
  browser = process.env.BROWSER === 'webkit'
    ? await webkit.launch({headless: true})
    : await chromium.launch({channel: process.env.CHROME_CHANNEL || 'chrome', headless: true});
});
after(async () => {
  await browser?.close();
  await new Promise(resolve => server ? server.close(resolve) : resolve());
});

test('bundled browser model matches native TFLite v1 evaluation tensors', {timeout: 120000}, async () => {
  const page = await browser.newPage();
  const requests = [];
  page.on('request', request => requests.push(request.url()));
  await page.goto(origin);
  const outputs = await page.evaluate(async cases => {
    const classifier = createTsumoClassifier();
    try {
      await classifier.load('../assets/ml/tile_classifier.tflite');
      const results = [];
      for (const c of cases) {
        const values = await classifier.predict(new Float32Array(224 * 224 * 3).fill(c.input_fill));
        results.push(Array.from(values));
      }
      return results;
    } finally { classifier.dispose(); }
  }, fixture.cases);
  for (let i = 0; i < outputs.length; i++) {
    const expected = fixture.cases[i];
    assert.equal(outputs[i].length, expected.scores.length);
    const maxError = Math.max(...outputs[i].map((score, j) => Math.abs(score - expected.scores[j])));
    assert.ok(maxError <= fixture.absolute_tolerance, `${expected.id}: max error ${maxError}`);
  }
  assert.ok(requests.every(url => url.startsWith(origin)), 'Inference must not call external services');
  await page.close();
});

test('missing model and disposed worker fail promptly without an API fallback', {timeout: 120000}, async () => {
  const page = await browser.newPage();
  await page.goto(origin);
  const result = await page.evaluate(async () => {
    const classifier = createTsumoClassifier();
    let loadFailed = false, disposedFailed = false;
    try { await classifier.load('../missing-model.tflite'); } catch { loadFailed = true; }
    classifier.dispose();
    try { await classifier.predict(new Float32Array(224 * 224 * 3)); } catch { disposedFailed = true; }
    return {loadFailed, disposedFailed};
  });
  assert.deepEqual(result, {loadFailed: true, disposedFailed: true});
  await page.close();
});
