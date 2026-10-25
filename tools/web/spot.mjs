// 網頁版定點截圖：node tools/web/spot.mjs <level> <x,y,z> [portrait|landscape] [輸出檔名]
// 用真網頁版（build/web）在指定關卡、指定位置截圖，排查「本機正常、手機不正常」的問題
import { createServer } from 'node:http';
import { readFileSync, statSync, existsSync, mkdirSync } from 'node:fs';
import { join, extname } from 'node:path';
import puppeteer, { KnownDevices } from 'puppeteer-core';
const ROOT = new URL('../../build/web/', import.meta.url).pathname.replace(/^\/([A-Za-z]:)/, '$1');
const OUT = new URL('../../build/play/', import.meta.url).pathname.replace(/^\/([A-Za-z]:)/, '$1');
mkdirSync(OUT, { recursive: true });
const MIME = { '.html': 'text/html', '.js': 'text/javascript', '.wasm': 'application/wasm', '.pck': 'application/octet-stream', '.png': 'image/png' };
const server = createServer((req, res) => {
  const u = decodeURIComponent(req.url.split('?')[0]);
  const p = join(ROOT, u === '/' ? 'index.html' : u);
  if (!existsSync(p) || statSync(p).isDirectory()) { res.writeHead(404); return res.end(); }
  res.writeHead(200, { 'Content-Type': MIME[extname(p)] || 'application/octet-stream' });
  res.end(readFileSync(p));
}).listen(0);
const [level = '1', pos = '0,0.1,0', orient = 'portrait', name = 'spot'] = process.argv.slice(2);
const chrome = ['C:/Program Files/Google/Chrome/Application/chrome.exe'].find(existsSync);
const browser = await puppeteer.launch({ executablePath: chrome, headless: true, args: ['--use-gl=angle', '--use-angle=swiftshader', '--enable-unsafe-swiftshader'] });
const page = await browser.newPage();
await page.emulate(KnownDevices[orient === 'portrait' ? 'iPhone 13 Pro' : 'iPhone 13 Pro landscape']);
const log = [];
page.on('console', (m) => { if (/ERROR|error/.test(m.text())) log.push(m.text()); });
await page.goto(`http://127.0.0.1:${server.address().port}/index.html?level=${level}&tour=${pos};${pos};${pos}`, { waitUntil: 'load' });
await new Promise((r) => setTimeout(r, 14000));
const f = join(OUT, `${name}.png`);
await page.screenshot({ path: f });
console.log('shot:', f);
console.log(log.slice(0, 10).join('\n'));
await browser.close(); server.close();
