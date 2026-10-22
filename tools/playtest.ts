// 自動試玩：織田引導劇本跑到桶狹間之後，檢查引導推進、功能解鎖、即時戰鬥能走完、沒有 console 錯誤
// 用法：npx tsx tools/playtest.ts [baseUrl]
import puppeteer from 'puppeteer-core';
import { existsSync } from 'node:fs';

const base = process.argv[2] ?? 'http://localhost:5180';
const candidates = ['C:/Program Files/Google/Chrome/Application/chrome.exe', 'C:/Program Files (x86)/Microsoft/Edge/Application/msedge.exe'];
const executablePath = candidates.find(p => existsSync(p));
if (!executablePath) throw new Error('找不到 Chrome / Edge');

const browser = await puppeteer.launch({ executablePath, headless: true, args: ['--disable-gpu', '--use-gl=swiftshader', '--enable-unsafe-swiftshader'] });
const page = await browser.newPage();
const errors: string[] = [];
page.on('pageerror', e => errors.push(String(e)));
page.on('console', m => { if (m.type() === 'error' && !m.text().includes('404')) errors.push(m.text()); });
await page.setViewport({ width: 390, height: 844, deviceScaleFactor: 1, isMobile: true, hasTouch: true });
await page.goto(`${base}/?faction=oda&seed=1&guide=0`, { waitUntil: 'load' });
await sleep(1500);

type Snapshot = { turn: number; month: number; step: number; tabs: string[]; cmds: string[]; advice: string; gold: number; troops: number; battle: boolean };
const snap = (): Promise<Snapshot> => page.evaluate(() => {
  const app = (window as unknown as { __app: { state: { turn: number; month: number; flags: Record<string, unknown>; factions: Record<string, { gold: number }>; regions: Record<string, { troops: { ashigaru: number; cavalry: number; gun: number } }> } } }).__app;
  const s = app.state;
  const t = s.regions.owari.troops;
  return {
    turn: s.turn, month: s.month, step: Number(s.flags.guideStep ?? -1),
    tabs: [...document.querySelectorAll('#tabs button')].map(b => b.textContent ?? ''),
    cmds: [...document.querySelectorAll('.cmd')].map(b => (b.querySelector('.cmd-name')?.textContent ?? '')),
    advice: document.querySelector('.advisor .say')?.textContent ?? '',
    gold: s.factions.oda.gold, troops: t.ashigaru + t.cavalry + t.gun,
    battle: !!document.getElementById('battle'),
  };
});
const click = (text: string, scope = 'body'): Promise<boolean> => page.evaluate((sel: string, txt: string) => {
  const root = document.querySelector(sel) ?? document;
  if (txt.startsWith('.') || txt.startsWith('#')) { const el = root.querySelector(txt) as HTMLElement | null; el?.click(); return !!el; }
  const els = [...root.querySelectorAll('button, .cmd, .list-item, .officer, .stance')] as HTMLElement[];
  const el = els.find(e => e.textContent?.includes(txt) && !(e as HTMLButtonElement).disabled);
  el?.click(); return !!el;
}, scope, text);
function sleep(ms: number) { return new Promise(r => setTimeout(r, ms)); }

const log = (s: string) => console.log(s);
let st = await snap();
log(`開局：step=${st.step} tabs=${st.tabs.join('/')} advice=「${st.advice}」`);

// 步驟 0：帶我去 → 點高亮指令
log(`帶我去: ${await click('帶我去')}`); await sleep(400);
let cmds = (await snap()).cmds;
log(`指令列（引導中）：${cmds.join(' ')}`);
log(`點高亮指令: ${await click('.cmd.hinted')}`); await sleep(400);
st = await snap(); log(`→ step=${st.step} gold=${st.gold} advice=「${st.advice}」`);
// 步驟 1
log(`帶我去: ${await click('帶我去')}`); await sleep(400);
log(`點高亮指令: ${await click('.cmd.hinted')}`); await sleep(400);
st = await snap(); log(`→ step=${st.step} troops=${st.troops} advice=「${st.advice}」`);

// 連跑回合直到戰鬥出現或 8 回合
for (let i = 0; i < 8; i++) {
  await click('結束回合'); await sleep(300);
  await click('確定'); await sleep(1500);
  // 事件（商人）
  if (await click('謝絕')) await sleep(300);
  st = await snap();
  if (st.battle) {
    log(`第 ${st.turn} 回合（${st.month} 月）出現戰鬥`);
    // 桶狹間奇襲選項
    if (await click('奇襲')) { log('  桶狹間：選擇奇襲'); await sleep(800); }
    log(`  開戰: ${await click('開戰')}`);
    // 改陣幾次（反應敵方預告）
    for (let k = 0; k < 12; k++) {
      await sleep(2500);
      const tg = await page.evaluate(() => document.querySelector('.telegraph')?.textContent ?? '');
      if (tg) {
        // 敵軍準備改為 X → 選剋制：突擊→方陣、方陣→迂迴、迂迴→突擊、鐵砲→突擊
        const counter = tg.includes('突擊') ? '方陣' : tg.includes('方陣') ? '迂迴' : '突擊';
        const ok = await click(counter, '.stance-grid');
        if (ok) log(`  ${tg} → 改為${counter}`);
      }
      const done = await page.evaluate(() => !!document.querySelector('#battle .modal-title'));
      if (done) break;
    }
    // 等結束
    for (let k = 0; k < 30; k++) { if (await click('結束戰鬥')) break; await sleep(1000); }
    await sleep(800);
    st = await snap();
    log(`  戰鬥結束 → step=${st.step} tabs=${st.tabs.join('/')} advice=「${st.advice}」`);
    break;
  }
  log(`第 ${st.turn} 回合（${st.month} 月）step=${st.step} tabs=${st.tabs.join('/')} gold=${st.gold} advice=「${st.advice}」`);
}
await page.screenshot({ path: 'tools/shot-playtest.png' });
log(`console errors: ${errors.length}`);
for (const e of errors.slice(0, 5)) log('  ' + e);
await browser.close();
