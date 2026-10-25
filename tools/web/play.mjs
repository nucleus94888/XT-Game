// 網頁版實機操作測試：無頭 Chrome 模擬 iPhone（觸控、iOS UA）載入 build/web，
// 照玩家的手指做一遍：點「開始」→ 點「換」→ 按住「鉤」→ 放開 → 按住「攻擊」（手裡劍瞄準）→ 放開，
// 每一步截圖，並收集 console 的 SCRIPT ERROR。
// 用法：node tools/web/play.mjs [landscape|portrait]
//   需先：godot --headless --path hanzo --export-release Web ../build/web/index.html
import { createServer } from 'node:http';
import { readFileSync, statSync, existsSync, mkdirSync } from 'node:fs';
import { join, extname } from 'node:path';
import puppeteer, { KnownDevices } from 'puppeteer-core';

const ROOT = new URL('../../build/web/', import.meta.url).pathname.replace(/^\/([A-Za-z]:)/, '$1');
const OUT = new URL('../../build/play/', import.meta.url).pathname.replace(/^\/([A-Za-z]:)/, '$1');
mkdirSync(OUT, { recursive: true });
const MIME = { '.html': 'text/html', '.js': 'text/javascript', '.wasm': 'application/wasm', '.pck': 'application/octet-stream', '.png': 'image/png', '.json': 'application/json' };
const server = createServer((req, res) => {
  const u = decodeURIComponent(req.url.split('?')[0]);
  const p = join(ROOT, u === '/' ? 'index.html' : u);
  if (!existsSync(p) || statSync(p).isDirectory()) { res.writeHead(404); return res.end(); }
  res.writeHead(200, { 'Content-Type': MIME[extname(p)] || 'application/octet-stream', 'Cross-Origin-Opener-Policy': 'same-origin', 'Cross-Origin-Embedder-Policy': 'require-corp' });
  res.end(readFileSync(p));
}).listen(0);
const port = server.address().port;

const portrait = process.argv[2] === 'portrait';
const chrome = ['C:/Program Files/Google/Chrome/Application/chrome.exe', 'C:/Program Files (x86)/Microsoft/Edge/Application/msedge.exe'].find(existsSync);
const browser = await puppeteer.launch({ executablePath: chrome, headless: true, args: ['--use-gl=angle', '--use-angle=swiftshader', '--enable-unsafe-swiftshader', '--autoplay-policy=no-user-gesture-required'] });
const page = await browser.newPage();
const dev = KnownDevices[portrait ? 'iPhone 13 Pro' : 'iPhone 13 Pro landscape'];
await page.emulate(dev);
const W = dev.viewport.width, H = dev.viewport.height;
const log = [];
page.on('console', (m) => { const t = m.text(); if (['error', 'warning'].includes(m.type()) || /SCRIPT ERROR|ERROR/.test(t)) log.push(`[${m.type()}] ${t}`); });
page.on('pageerror', (e) => log.push(`[pageerror] ${e.message}`));
await page.goto(`http://127.0.0.1:${port}/index.html`, { waitUntil: 'load' });
await sleep(9000);
await shot('0-title');

// 位置用畫面比例（UI 倍率是相對短邊，所以比例在同比例螢幕上穩定）
const P = portrait
  ? { start: [0.5, 0.54], swap: [1 - 78 / 553 + 54 * 0.72 / 553, 1 - (115 + 54 * 0.72) / 1203], atk: [1 - 78 / 553, 1 - 115 / 1203], hook: [1 - 195 / 553, 1 - 205 / 1203] }
  : { start: [0.5, 0.56], swap: [0.944, 0.74], atk: [0.913, 0.808], hook: [0.794, 0.643] };
const px = ([x, y]) => [Math.round(x * W), Math.round(y * H)];

await tap(...px(P.start)); await sleep(3000); await shot('1-level');
await tap(...px(P.swap)); await sleep(600); await shot('2-after-swap');
await down(...px(P.hook)); await sleep(700); await shot('3-hook-hold');
await up(); await sleep(800); await shot('4-hook-release');
await down(...px(P.atk)); await sleep(700); await shot('5-attack-hold');
await up(); await sleep(800); await shot('6-attack-release');
await tap(...px(P.swap)); await sleep(600); await shot('7-swap-smoke');
await tap(...px(P.atk)); await sleep(900); await shot('8-smoke-thrown');
await tap(...px(P.swap)); await sleep(600); await shot('9-swap-back');

console.log(log.length ? `console 問題 ${log.length} 筆：\n` + [...new Set(log)].slice(0, 30).join('\n') : 'console 無錯誤');
await browser.close();
server.close();

async function tap(x, y) { await page.touchscreen.touchStart(x, y); await sleep(60); await page.touchscreen.touchEnd(); }
async function down(x, y) { await page.touchscreen.touchStart(x, y); }
async function up() { await page.touchscreen.touchEnd(); }
async function shot(name) { const f = join(OUT, `${name}.png`); await page.screenshot({ path: f }); console.log('shot:', f); }
function sleep(ms) { return new Promise((r) => setTimeout(r, ms)); }
