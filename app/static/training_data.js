const API = '';
const TILES = [
  ...Array.from({length:9},(_,i)=>`${i+1}m`), '5mr',
  ...Array.from({length:9},(_,i)=>`${i+1}p`), '5pr',
  ...Array.from({length:9},(_,i)=>`${i+1}s`), '5sr',
  'E','S','W','N','P','F','C'
];
const TILE_NAMES = {
  '1m':'一萬', '2m':'二萬', '3m':'三萬', '4m':'四萬', '5m':'五萬',
  '6m':'六萬', '7m':'七萬', '8m':'八萬', '9m':'九萬', '5mr':'赤五萬',
  '1p':'一筒', '2p':'二筒', '3p':'三筒', '4p':'四筒', '5p':'五筒',
  '6p':'六筒', '7p':'七筒', '8p':'八筒', '9p':'九筒', '5pr':'赤五筒',
  '1s':'一索', '2s':'二索', '3s':'三索', '4s':'四索', '5s':'五索',
  '6s':'六索', '7s':'七索', '8s':'八索', '9s':'九索', '5sr':'赤五索',
  'E':'東', 'S':'南', 'W':'西', 'N':'北', 'P':'白', 'F':'發', 'C':'中'
};
const tileName = code => TILE_NAMES[code] || code;
let historyRefreshTimer = null;

function showPageAlert(message = '') {
  const alert = document.getElementById('pageAlert');
  alert.textContent = message;
  alert.hidden = !message;
}

function markUpdated() {
  document.getElementById('lastUpdated').textContent = new Date().toLocaleString('ja-JP');
}

function escapeHtml(value) {
  return String(value ?? '').replace(/[&<>'"]/g, char => ({
    '&':'&amp;', '<':'&lt;', '>':'&gt;', "'":'&#39;', '"':'&quot;'
  })[char]);
}

function formatBuildDate(value) {
  return value ? new Date(value).toLocaleString('ja-JP') : '—';
}

function formatDuration(seconds) {
  if (seconds == null) return '—';
  const minutes = Math.floor(seconds / 60);
  return minutes ? `${minutes}分 ${seconds % 60}秒` : `${seconds}秒`;
}

function buildStatus(status) {
  const statuses = {
    SUCCESS:['成功','success'], QUEUED:['待機中','active'], WORKING:['実行中','active'],
    FAILURE:['失敗','failure'], INTERNAL_ERROR:['内部エラー','failure'],
    TIMEOUT:['タイムアウト','failure'], CANCELLED:['キャンセル','failure'],
    EXPIRED:['期限切れ','failure']
  };
  const [label, kind] = statuses[status] || [status || '不明', 'other'];
  return {label, kind};
}

async function loadRetrainingHistory() {
  const button = document.getElementById('historyRefreshBtn');
  button.disabled = true;
  try {
    const res = await authFetch(`${API}/api/v1/model/retraining-history?limit=20`);
    const data = await res.json();
    if (!res.ok) throw new Error(data.detail || `HTTP ${res.status}`);
    const builds = data.builds || [];
    const el = document.getElementById('trainingHistory');
    if (!builds.length) {
      el.innerHTML = '<div class="history-empty">再学習の実行履歴はありません</div>';
    } else {
      el.innerHTML = `<table class="history-table">
        <thead><tr><th>結果</th><th>開始日時</th><th>終了日時</th><th>所要時間</th><th>詳細</th></tr></thead>
        <tbody>${builds.map(build => {
          const status = buildStatus(build.status);
          const safeLogUrl = typeof build.log_url === 'string' && build.log_url.startsWith('https://') ? build.log_url : null;
          const detail = build.failure_detail ? `<br><small>${escapeHtml(build.failure_detail)}</small>` : '';
          return `<tr>
            <td><span class="build-status build-${status.kind}">${escapeHtml(status.label)}</span>${detail}</td>
            <td>${escapeHtml(formatBuildDate(build.start_time || build.create_time))}</td>
            <td>${escapeHtml(formatBuildDate(build.finish_time))}</td>
            <td>${escapeHtml(formatDuration(build.duration_seconds))}</td>
            <td>${safeLogUrl ? `<a href="${escapeHtml(safeLogUrl)}" target="_blank" rel="noopener noreferrer">ログ</a>` : escapeHtml(build.build_id)}</td>
          </tr>`;
        }).join('')}</tbody>
      </table>`;
    }
    clearTimeout(historyRefreshTimer);
    if (builds.some(build => ['QUEUED','WORKING'].includes(build.status))) {
      historyRefreshTimer = setTimeout(loadRetrainingHistory, 15000);
    }
  } catch (e) {
    document.getElementById('trainingHistory').innerHTML = `<div class="history-empty">履歴の読み込みに失敗: ${escapeHtml(e.message)}</div>`;
  } finally {
    button.disabled = false;
  }
}

// ── Auth (Firebase Google sign-in; the admin APIs below require the
// resulting ID token, verified server-side via app/auth.py) ──

firebase.initializeApp(window.TsumoFirebaseConfig);
const auth = firebase.auth();

function signIn() {
  document.getElementById('authError').textContent = '';
  auth.signInWithPopup(new firebase.auth.GoogleAuthProvider())
    .catch(e => { document.getElementById('authError').textContent = 'ログイン失敗: ' + e.message; });
}

function signOutUser() {
  auth.signOut();
}

async function authFetch(url, options = {}) {
  const headers = { ...(options.headers || {}) };
  if (auth.currentUser) {
    headers['Authorization'] = `Bearer ${await auth.currentUser.getIdToken()}`;
  }
  return fetch(url, { ...options, headers });
}

auth.onAuthStateChanged(async user => {
  const gate = document.getElementById('authGate');
  const content = document.getElementById('appContent');
  gate.hidden = false;
  content.hidden = true;
  if (!user) return;
  try {
    const token = await user.getIdTokenResult(true);
    if (token.claims.admin !== true) {
      document.getElementById('authError').textContent = 'このアカウントには管理者権限がありません。';
      return;
    }
  } catch (e) {
    document.getElementById('authError').textContent = '管理者権限を確認できませんでした。再度ログインしてください。';
    return;
  }
  gate.hidden = true;
  content.hidden = false;
  document.getElementById('userInfo').textContent = user.email;
  refreshDashboard();
});

async function refreshDashboard() {
  showPageAlert();
  const results = await Promise.allSettled([
    loadData(true),
    loadModelInfo(),
    loadAccuracyHistory(),
    loadRetrainingHistory(),
  ]);
  if (results.every(result => result.status === 'rejected')) {
    showPageAlert('管理データを取得できませんでした。通信状態を確認して再試行してください。');
  }
}

async function loadData(refresh = false) {
  const tile = document.getElementById('filterTile').value;
  const source = document.getElementById('filterSource').value;
  let url = `${API}/api/v1/training-data/list?limit=500`;
  if (tile) url += `&tile_code=${tile}`;
  if (source) url += `&source=${source}`;
  if (refresh) url += `&refresh=true`;

  try {
    const res = await authFetch(url);
    const data = await res.json();
    if (!res.ok) throw new Error(data.detail || `HTTP ${res.status}`);
    renderStats(data.stats);
    renderAccuracy(data.stats);
    renderRanking(data.stats);
    renderGrid(data.entries);
    renderTileStats(data.stats);
    populateFilter(data.stats);
    renderTimelineChart(data.timeline);
    renderDistributionChart(data.stats.by_tile_code);
    markUpdated();
  } catch(e) {
    document.getElementById('grid').innerHTML = `<div class="empty">データの読み込みに失敗: ${escapeHtml(e.message)}</div>`;
    showPageAlert(`学習データの読み込みに失敗しました: ${e.message}`);
    throw e;
  }
}

function percent(correct, total) {
  return total ? `${(correct / total * 100).toFixed(1)}%` : '—';
}

function renderAccuracy(stats) {
  const accuracy = stats.recognition_accuracy || {};
  const total = Number(accuracy.total || 0);
  const el = document.getElementById('accuracyContent');
  if (!total) {
    el.innerHTML = '<div class="accuracy-empty">訂正前ラベルを含む新しい学習データがまだありません</div>';
    return;
  }
  const tileRows = TILES.map(tile => {
    const item = (accuracy.by_actual_tile || {})[tile];
    if (!item) return '';
    const rate = item.correct / item.total * 100;
    return `<div class="accuracy-row"><span>${tileName(tile)}</span><div class="accuracy-bar"><span style="width:${rate}%"></span></div><span>${rate.toFixed(1)}% (${item.correct}/${item.total})</span></div>`;
  }).join('');
  const dayRows = Object.entries(accuracy.by_day || {}).slice(-14).map(([day, item]) => {
    const rate = item.correct / item.total * 100;
    return `<div class="accuracy-row"><span>${day.slice(5)}</span><div class="accuracy-bar"><span style="width:${rate}%"></span></div><span>${rate.toFixed(1)}% (${item.total}枚)</span></div>`;
  }).join('');
  const confusionRows = (accuracy.top_confusions || []).map(item =>
    `<div class="accuracy-row"><span>${tileName(item.predicted)}→${tileName(item.actual)}</span><div></div><span>${item.count}枚</span></div>`
  ).join('');
  el.innerHTML = `
    <div class="accuracy-summary">
      <div class="accuracy-card"><div class="label">集計対象</div><div class="value">${total}枚</div></div>
      <div class="accuracy-card"><div class="label">正解（訂正なし）</div><div class="value">${accuracy.correct || 0}枚</div></div>
      <div class="accuracy-card"><div class="label">不正解（訂正あり）</div><div class="value">${accuracy.corrected || 0}枚</div></div>
      <div class="accuracy-card"><div class="label">実利用正解率</div><div class="value">${percent(accuracy.correct, total)}</div></div>
    </div>
    <div class="accuracy-details">
      <div class="accuracy-group"><h3>牌別正解率</h3><div class="accuracy-rows">${tileRows}</div></div>
      <div class="accuracy-group"><h3>日別正解率（直近14日）</h3><div class="accuracy-rows">${dayRows || '<div class="accuracy-empty">日付データなし</div>'}</div></div>
      <div class="accuracy-group"><h3>主な訂正（識別→正解）</h3><div class="accuracy-rows">${confusionRows || '<div class="accuracy-empty">訂正なし</div>'}</div></div>
    </div>`;
}

function renderRanking(stats) {
  const byTile = stats.by_tile_code || {};
  const ranking = TILES
    .map((tile, tileOrder) => ({tile, count: Number(byTile[tile] || 0), tileOrder}))
    .sort((a, b) => a.count - b.count || a.tileOrder - b.tileOrder);
  document.getElementById('rankingList').innerHTML = ranking.map((item, index) => `
    <div class="ranking-item">
      <span class="ranking-position">${index + 1}位</span>
      <span class="ranking-tile">${tileName(item.tile)}</span>
      <span class="ranking-count ${item.count === 0 ? 'zero' : ''}">${item.count}枚</span>
    </div>
  `).join('');
}

// ── Charts (plain SVG, no external library) ──

function lineChartSVG(labels, seriesArr, opts = {}) {
  const w = 300, h = 110, padL = 28, padR = 8, padT = 8, padB = 20;
  const innerW = w - padL - padR, innerH = h - padT - padB;
  const allVals = seriesArr.flatMap(s => s.values).filter(v => v != null);
  const yMax = opts.yMax != null ? opts.yMax : Math.max(...allVals, 1);
  const yMin = opts.yMin != null ? opts.yMin : Math.min(...allVals, 0);
  const range = (yMax - yMin) || 1;
  const n = labels.length;
  const xStep = n > 1 ? innerW / (n - 1) : 0;
  const xAt = i => padL + xStep * i;
  const yAt = v => padT + innerH - ((v - yMin) / range) * innerH;
  const fmt = opts.yFormat || (v => Math.round(v));

  let svg = `<svg viewBox="0 0 ${w} ${h}">`;
  svg += `<line class="axis" x1="${padL}" y1="${padT}" x2="${padL}" y2="${padT + innerH}"/>`;
  svg += `<line class="axis" x1="${padL}" y1="${padT + innerH}" x2="${padL + innerW}" y2="${padT + innerH}"/>`;
  svg += `<text x="2" y="${padT + 6}">${fmt(yMax)}</text>`;
  svg += `<text x="2" y="${padT + innerH + 2}">${fmt(yMin)}</text>`;

  seriesArr.forEach(s => {
    const pts = s.values.map((v, i) => (v == null ? null : `${xAt(i)},${yAt(v)}`)).filter(Boolean).join(' ');
    svg += `<polyline class="line${s.className ? ' ' + s.className : ''}" points="${pts}"/>`;
    s.values.forEach((v, i) => {
      if (v != null) svg += `<circle class="dot${s.className ? ' ' + s.className : ''}" cx="${xAt(i)}" cy="${yAt(v)}" r="2"/>`;
    });
  });

  if (n > 0) {
    svg += `<text x="${xAt(0)}" y="${h - 2}" text-anchor="start">${labels[0]}</text>`;
    if (n > 1) svg += `<text x="${xAt(n - 1)}" y="${h - 2}" text-anchor="end">${labels[n - 1]}</text>`;
  }
  svg += `</svg>`;
  return svg;
}

function barChartSVG(labels, values) {
  const w = 320, h = 140, padL = 4, padR = 4, padT = 8, padB = 26;
  const innerW = w - padL - padR, innerH = h - padT - padB;
  const n = labels.length;
  const maxV = Math.max(...values, 1);
  const barW = innerW / n;

  let svg = `<svg viewBox="0 0 ${w} ${h}">`;
  svg += `<line class="axis" x1="${padL}" y1="${padT + innerH}" x2="${padL + innerW}" y2="${padT + innerH}"/>`;
  values.forEach((v, i) => {
    const bh = (v / maxV) * innerH;
    const x = padL + i * barW + barW * 0.15;
    const bw = barW * 0.7;
    const y = padT + innerH - bh;
    svg += `<rect class="bar" x="${x.toFixed(1)}" y="${y.toFixed(1)}" width="${bw.toFixed(1)}" height="${Math.max(bh, 0).toFixed(1)}"><title>${labels[i]}: ${v}</title></rect>`;
  });
  labels.forEach((l, i) => {
    if (i % 3 === 0) {
      const x = padL + i * barW + barW / 2;
      svg += `<text x="${x.toFixed(1)}" y="${h - 4}" text-anchor="middle">${l}</text>`;
    }
  });
  svg += `</svg>`;
  return svg;
}

function renderTimelineChart(timeline) {
  const el = document.getElementById('timelineChart');
  if (!timeline || timeline.length === 0) {
    el.innerHTML = '<div class="chart-empty">まだデータがありません</div>';
    return;
  }
  const labels = timeline.map(t => t.date.slice(5));
  const values = timeline.map(t => t.cumulative_count);
  el.innerHTML = lineChartSVG(labels, [{ values }], { yMin: 0 });
}

function renderDistributionChart(byTile) {
  const el = document.getElementById('distributionChart');
  if (!byTile || Object.keys(byTile).length === 0) {
    el.innerHTML = '<div class="chart-empty">まだデータがありません</div>';
    return;
  }
  const values = TILES.map(t => byTile[t] || 0);
  el.innerHTML = barChartSVG(TILES.map(tileName), values);
}

async function loadAccuracyHistory() {
  const el = document.getElementById('accuracyChart');
  try {
    const res = await authFetch(`${API}/api/v1/metrics/accuracy-history`);
    const data = await res.json();
    const history = data.history || [];
    if (!res.ok || history.length === 0) {
      el.innerHTML = '<div class="chart-empty">まだ測定データがありません</div>';
      return;
    }
    const labels = history.map(h => (h.evaluated_at || '').slice(5, 10));
    const tileAcc = history.map(h => (h.tile_accuracy != null ? h.tile_accuracy * 100 : null));
    const exactAcc = history.map(h => (h.exact_match_rate != null ? h.exact_match_rate * 100 : null));
    el.innerHTML = lineChartSVG(labels, [
      { values: tileAcc },
      { values: exactAcc, className: 'secondary' },
    ], { yMin: 0, yMax: 100, yFormat: v => `${Math.round(v)}%` });
  } catch (e) {
    el.innerHTML = '<div class="chart-empty">読み込みに失敗しました</div>';
  }
}

function renderStats(stats) {
  const el = document.getElementById('stats');
  const accuracy = stats.recognition_accuracy || {};
  const sourceNames = {user: 'ユーザー撮影', camerash: 'Camerash', kaggle: 'Kaggle'};
  el.innerHTML = `
    <div class="stat-card"><div class="label">総画像数</div><div class="value">${stats.total || 0}</div></div>
    <div class="stat-card"><div class="label">収集済み牌種</div><div class="value">${Object.keys(stats.by_tile_code || {}).length} / ${TILES.length}</div></div>
    <div class="stat-card"><div class="label">訂正実績</div><div class="value">${accuracy.corrected || 0}</div></div>
    <div class="stat-card"><div class="label">実利用正解率</div><div class="value">${percent(accuracy.correct, accuracy.total)}</div></div>
    ${Object.entries(stats.by_source || {}).map(([k,v]) =>
      `<div class="stat-card"><div class="label">${escapeHtml(sourceNames[k] || k)}</div><div class="value">${v}</div></div>`
    ).join('')}
  `;
}

function renderGrid(entries) {
  const el = document.getElementById('grid');
  if (!entries || entries.length === 0) {
    el.innerHTML = '<div class="empty">学習データがありません</div>';
    return;
  }
  el.innerHTML = entries.map(e => `
    <div class="tile-card">
      <img data-id="${e.id}" alt="${tileName(e.tile_code)}">
      <select class="label-select" aria-label="正解牌" data-previous-value="${e.tile_code}" onchange="updateTileCode('${e.id}', this)">
        ${TILES.map(t => `<option value="${t}" ${t === e.tile_code ? 'selected' : ''}>${tileName(t)}</option>`).join('')}
      </select>
      <div class="source">${e.source}</div>
      <div class="save-status" aria-live="polite"></div>
      <button class="delete-btn" onclick="deleteEntry('${e.id}')" title="削除">×</button>
    </div>
  `).join('');
  // <img src> can't carry an Authorization header, so each thumbnail is
  // fetched via authFetch and swapped in as a blob: URL instead.
  el.querySelectorAll('img[data-id]').forEach(async img => {
    try {
      const res = await authFetch(`${API}/api/v1/training-data/image/${img.dataset.id}`);
      if (!res.ok) return;
      img.src = URL.createObjectURL(await res.blob());
    } catch (e) {}
  });
}

function renderTileStats(stats) {
  const el = document.getElementById('tileStats');
  const byTile = stats.by_tile_code || {};
  el.innerHTML = '<div class="tile-stats-grid">' +
    Object.entries(byTile).map(([k,v]) =>
      `<div class="tile-stat">${tileName(k)}: <span class="count">${v}</span></div>`
    ).join('') + '</div>';
}

function populateFilter(stats) {
  const sel = document.getElementById('filterTile');
  const current = sel.value;
  sel.innerHTML = '<option value="">全ての牌</option>';
  TILES.forEach(t => {
    sel.innerHTML += `<option value="${t}" ${t===current?'selected':''}>${tileName(t)}</option>`;
  });
}

async function deleteEntry(id) {
  if (!confirm('この学習データを削除しますか？')) return;
  try {
    const res = await authFetch(`${API}/api/v1/training-data/${id}`, {method:'DELETE'});
    const data = await res.json();
    if (!res.ok) throw new Error(data.detail || '削除に失敗しました');
    await loadData();
  } catch (e) {
    showPageAlert(`学習データを削除できませんでした: ${e.message}`);
  }
}

async function updateTileCode(id, select) {
  const tileCode = select.value;
  const previousTileCode = select.dataset.previousValue;
  if (tileCode === previousTileCode) return;
  const status = select.closest('.tile-card').querySelector('.save-status');
  select.disabled = true;
  status.textContent = '保存中…';
  status.className = 'save-status saving';
  try {
    const res = await authFetch(`${API}/api/v1/training-data/${id}?tile_code=${encodeURIComponent(tileCode)}`, {method:'PATCH'});
    const data = await res.json();
    if (!res.ok) throw new Error(data.detail || '更新に失敗しました');
    // Deliberately not calling loadData() here: with a tile-code filter
    // active, refetching would immediately drop this card out of view
    // under the old filter value, so a mis-click can't be corrected without
    // hunting it down under the wrong filter first. The select already
    // reflects the committed value (tracked via data-previous-value so a
    // second correction in a row still rolls back correctly on failure);
    // stats/charts just go stale until the next manual refresh or filter
    // change.
    select.dataset.previousValue = tileCode;
    select.disabled = false;
    status.textContent = '保存済み';
    status.className = 'save-status saved';
  } catch (e) {
    select.value = previousTileCode;
    select.disabled = false;
    status.textContent = '保存できませんでした';
    status.className = 'save-status failed';
  }
}

async function loadModelInfo() {
  try {
    const res = await authFetch(`${API}/api/v1/model/latest`);
    const data = await res.json();
    const el = document.getElementById('modelInfo');
    if (data.status === 'ok') {
      const date = new Date(data.created_at).toLocaleString('ja-JP');
      el.textContent = `配信モデル v${data.version}・精度 ${(data.val_accuracy * 100).toFixed(1)}%・${date}`;
    } else if (data.status === 'no_model') {
      el.textContent = '配信モデルなし・アプリ同梱モデルを使用中';
      showPageAlert('公開中の学習済みモデルがありません。');
    }
  } catch(e) {
    document.getElementById('modelInfo').textContent = 'モデル情報を取得できません';
    throw e;
  }
}

async function triggerRetrain() {
  const btn = document.getElementById('retrainBtn');
  if (!confirm('モデルの再学習を開始しますか？\n\nCloud Buildを30〜60分実行します。費用目安は無料枠内〜1回100円程度で、実行時間と無料枠残量により変動します。')) return;
  btn.disabled = true;
  btn.textContent = '開始中...';
  try {
    const res = await authFetch(`${API}/api/v1/model/retrain`, {method: 'POST'});
    const data = await res.json();
    if (res.ok) {
      btn.textContent = '再学習中...';
      btn.style.background = '#888';
      alert(data.message);
      await loadRetrainingHistory();
    } else {
      alert('エラー: ' + (data.detail || '不明なエラー'));
      btn.disabled = false;
      btn.textContent = 'モデル再学習';
    }
  } catch(e) {
    alert('エラー: ' + e.message);
    btn.disabled = false;
    btn.textContent = 'モデル再学習';
  }
}
