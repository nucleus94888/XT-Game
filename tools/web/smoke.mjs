// Web 匯出煙霧測試：起本機 HTTP 伺服器 → 無頭 Chrome 載入 build/web → 收集 console 錯誤 → 截圖。
// 用法：node tools/web/smoke.mjs   （需先 godot --headless --path hanzo --export-release Web ../build/web/index.html）
// 需要 node_modules/puppeteer-core 與本機 Chrome。
import { createServer } from 'node:http';
import { readFileSync, statSync, existsSync, mkdirSync } from 'node:fs';
import { join, extname } from 'node:path';
import puppeteer from 'puppeteer-core';

const ROOT = new URL('../../build/web/', import.meta.url).pathname.replace(/^\/([A-Za-z]:)/, '$1');
const OUT = new URL('../../build/shots/', import.meta.url).pathname.replace(/^\/([A-Za-z]:)/, '$1');
mkdirSync(OUT, { recursive: true });
const MIME = { '.html': 'text/html', '.js': 'text/javascript', '.wasm': 'application/wasm', '.pck': 'application/octet-stream', '.png': 'image/png', '.json': 'application/json' };

const server = createServer((req, res) => {
  const p = join(ROOT, decodeURIComponent(req.url.split('?')[0]) === '/' ? 'index.html' : decodeURIComponent(req.url.split('?')[0]));
  if (!existsSync(p) || statSync(p).isDirectory()) { res.writeHead(404); return res.end(); }
  res.writeHead(200, { 'Content-Type': MIME[extname(p)] || 'application/octet-stream' });
  res.end(readFileSync(p));
}).listen(0);
const port = server.address().port;

const chrome = ['C:/Program Files/Google/Chrome/Application/chrome.exe', 'C:/Program Files (x86)/Microsoft/Edge/Application/msedge.exe'].find(existsSync);
const browser = await puppeteer.launch({ executablePath: chrome, headless: true, args: ['--use-gl=angle', '--use-angle=swiftshader', '--enable-unsafe-swiftshader', '--autoplay-policy=no-user-gesture-required'] });
const page = await browser.newPage();
await page.setViewport({ width: 1280, height: 720 });
const errors = [];
page.on('console', (m) => { if (['error', 'warning'].includes(m.type())) errors.push(`[${m.type()}] ${m.text()}`); });
page.on('pageerror', (e) => errors.push(`[pageerror] ${e.message}`));
await page.goto(`http://127.0.0.1:${port}/index.html`, { waitUntil: 'load' });
await new Promise((r) => setTimeout(r, 9000));
await page.screenshot({ path: join(OUT, 'web.png') });
console.log('screenshot:', join(OUT, 'web.png'));
console.log(errors.length ? `console 問題 ${errors.length} 筆：\n` + errors.slice(0, 20).join('\n') : 'console 無錯誤');
await browser.close();
server.close();
process.exit(errors.some((e) => e.startsWith('[pageerror]') || /Error|Uncaught|failed/i.test(e)) ? 1 : 0);
