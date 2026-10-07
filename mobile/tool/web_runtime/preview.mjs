// Serve the release build and API together for local phone/browser checks.
import http from 'node:http';
import https from 'node:https';
import {createReadStream} from 'node:fs';
import {stat} from 'node:fs/promises';
import path from 'node:path';

const root = path.resolve('build/web');
const api = new URL(process.env.WEB_API_URL || 'http://127.0.0.1:8000');
const mime = {'.html': 'text/html; charset=utf-8', '.js': 'text/javascript',
  '.json': 'application/json', '.wasm': 'application/wasm', '.png': 'image/png',
  '.jpg': 'image/jpeg', '.svg': 'image/svg+xml', '.woff2': 'font/woff2'};
const server = http.createServer(async (req, res) => {
  if (/^\/(api\/|static\/|health(?:\?|$))/.test(req.url)) {
    const upstream = (api.protocol === 'https:' ? https : http).request({
      hostname: api.hostname, port: api.port, path: req.url, method: req.method,
      headers: {...req.headers, host: api.host},
    }, response => { res.writeHead(response.statusCode, response.headers); response.pipe(res); });
    upstream.on('error', () => { res.writeHead(502); res.end('API server unavailable'); });
    req.pipe(upstream);
    return;
  }
  if (!['GET', 'HEAD'].includes(req.method)) { res.writeHead(405); res.end(); return; }
  try {
    const pathname = decodeURIComponent(new URL(req.url, 'http://localhost').pathname);
    const file = path.resolve(root, '.' + (pathname.endsWith('/') ? pathname + 'index.html' : pathname));
    if (!file.startsWith(root + path.sep)) { res.writeHead(403); res.end(); return; }
    const info = await stat(file);
    if (!info.isFile()) throw new Error('Not a file');
    res.writeHead(200, {'Content-Type': mime[path.extname(file)] || 'application/octet-stream',
      'Content-Length': info.size, 'Cache-Control': 'no-cache'});
    if (req.method === 'HEAD') res.end(); else createReadStream(file).pipe(res);
  } catch { res.writeHead(404); res.end('Not found'); }
});
const port = Number(process.env.PORT || 8089);
server.listen(port, '0.0.0.0', () => console.log(`TsumoAI preview: http://localhost:${port}`));
