// Same-origin API proxy + automatic Flutter web hot reload for docker compose.
import {spawn} from 'node:child_process';
import {watch} from 'node:fs';
import http from 'node:http';
import https from 'node:https';
import net from 'node:net';
import readline from 'node:readline';

async function run(command, args) {
  await new Promise((resolve, reject) => {
    const child = spawn(command, args, {stdio: 'inherit'});
    child.on('error', reject);
    child.on('exit', code => code === 0 ? resolve() : reject(new Error(`${command}: ${code}`)));
  });
}
await run('npm', ['ci', '--prefix', 'tool/web_runtime']);
await run('flutter', ['pub', 'get']);
const flutter = spawn('flutter', ['run', '-d', 'web-server', '--machine',
  '--no-pub', '--web-experimental-hot-reload', '--web-hostname=0.0.0.0', '--web-port=8080'],
  {stdio: ['pipe', 'pipe', 'inherit']});
let appId;
let requestId = 0;
let timer;
let restarting = false;
let changed = false;
function reload() {
  changed = true;
  if (!appId || restarting) return;
  restarting = true;
  changed = false;
  flutter.stdin.write(JSON.stringify([{id: ++requestId, method: 'app.restart',
    params: {appId, fullRestart: false, pause: false}}]) + '\n');
}
readline.createInterface({input: flutter.stdout}).on('line', line => {
  console.log(line);
  try {
    for (const event of JSON.parse(line)) {
      if (event.event === 'app.started') { appId = event.params.appId; if (changed) reload(); }
      if (event.id === requestId && restarting) { restarting = false; if (changed) reload(); }
    }
  } catch { /* Flutter also emits human-readable startup messages. */ }
});
for (const dir of ['lib', 'web']) {
  watch(dir, {recursive: true}, () => {
    clearTimeout(timer);
    timer = setTimeout(reload, 350);
  });
}
const api = new URL(process.env.WEB_API_URL || 'http://api:8000');
const server = http.createServer((req, res) => {
  const isApi = /^\/(api\/|static\/|health(?:\?|$))/.test(req.url);
  const target = isApi ? api : new URL('http://127.0.0.1:8080');
  const transport = target.protocol === 'https:' ? https : http;
  const upstream = transport.request({hostname: target.hostname, port: target.port,
    path: req.url, method: req.method, headers: {...req.headers, host: target.host}}, response => {
    res.writeHead(response.statusCode, response.headers);
    response.pipe(res);
  });
  upstream.on('error', () => {
    if (!res.headersSent) res.writeHead(503, {'Content-Type': 'text/plain; charset=utf-8', 'Retry-After': '5'});
    res.end('TsumoAIを起動中です。少し待って再読み込みしてください。');
  });
  req.pipe(upstream);
});
server.on('upgrade', (req, socket, head) => {
  const upstream = net.connect(8080, '127.0.0.1', () => {
    upstream.write(`${req.method} ${req.url} HTTP/${req.httpVersion}\r\n` +
      Object.entries(req.headers).map(([key, value]) => `${key}: ${value}\r\n`).join('') + '\r\n');
    if (head.length) upstream.write(head);
    socket.pipe(upstream).pipe(socket);
  });
  upstream.on('error', () => socket.destroy());
  socket.on('error', () => upstream.destroy());
  socket.on('close', () => upstream.destroy());
});
server.listen(8088, '0.0.0.0');
for (const signal of ['SIGINT', 'SIGTERM']) process.on(signal, () => {
  flutter.kill(signal);
  server.close();
});
flutter.on('exit', code => process.exit(code ?? 1));
