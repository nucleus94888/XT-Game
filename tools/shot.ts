// 開發用截圖：npx tsx tools/shot.ts [baseUrl]
// 以手機視口（直式 390x844、橫式 844x390）與桌機視口截圖，並印出主要區塊的尺寸
import puppeteer from 'puppeteer-core';
import { existsSync } from 'node:fs';

const base = process.argv[2] ?? 'http://localhost:5180';
const candidates = [
  'C:/Program Files/Google/Chrome/Application/chrome.exe',
  'C:/Program Files (x86)/Microsoft/Edge/Application/msedge.exe',
];
const executablePath = candidates.find(p => existsSync(p));
if (!executablePath) throw new Error('找不到 Chrome / Edge');

/** 步驟：'click:文字' 點擊第一個文字相符的按鈕/卡片；'wait:毫秒' */
const shots: { name: string; url: string; w: number; h: number; mobile: boolean; wait?: number; steps?: string[] }[] = [
  { name: 'title', url: '/', w: 390, h: 844, mobile: true },
  { name: 'guide-start', url: '/?faction=oda&seed=1&guide=0&intro=1', w: 390, h: 844, mobile: true, steps: ['wait:300'] },
  { name: 'guide-go', url: '/?faction=oda&seed=1&guide=0', w: 390, h: 844, mobile: true, steps: ['click:帶我去', 'wait:700', 'scroll:#panel,420', 'wait:200'] },
  { name: 'guide-step3', url: '/?faction=oda&seed=1&guide=3', w: 390, h: 844, mobile: true, steps: ['wait:300'] },
  { name: 'drill', url: '/', w: 390, h: 844, mobile: true, steps: ['click:合戰演習', 'wait:2500'] },
  { name: 'desktop-guide', url: '/?faction=oda&seed=1&guide=0', w: 1280, h: 720, mobile: false },
  { name: 'portrait', url: '/?faction=oda&seed=1', w: 390, h: 844, mobile: true },
  { name: 'landscape', url: '/?faction=oda&seed=1', w: 844, h: 390, mobile: true },
  { name: 'desktop', url: '/?faction=oda&seed=1', w: 1280, h: 720, mobile: false },
  { name: 'battle', url: '/?faction=oda&seed=1&battle=1', w: 390, h: 844, mobile: true, wait: 2500 },
  { name: 'flow-cmd', url: '/?faction=oda&seed=1', w: 390, h: 844, mobile: true, steps: ['click:.officer', 'wait:300', 'click:振興商業', 'wait:500'] },
  { name: 'flow-turn', url: '/?faction=oda&seed=1', w: 390, h: 844, mobile: true, steps: ['click:結束回合', 'wait:400', 'click:確定', 'wait:2500'] },
  { name: 'tab-diplomacy', url: '/?faction=oda&seed=1', w: 390, h: 844, mobile: true, steps: ['click:#tabs>外交', 'wait:300'] },
  { name: 'tab-tech', url: '/?faction=oda&seed=1', w: 390, h: 844, mobile: true, steps: ['click:#tabs>技術', 'wait:300'] },
  { name: 'faction-select', url: '/', w: 390, h: 844, mobile: true, steps: ['click:新遊戲', 'wait:500'] },
  { name: 'battle-mid', url: '/?faction=oda&seed=1&battle=1', w: 390, h: 844, mobile: true, wait: 2500,
    steps: ['click:開戰', 'wait:6000', 'click:.stance:not(.active):not(:disabled)', 'wait:3000'] },
  { name: 'battle-done', url: '/?faction=oda&seed=1&battle=1', w: 390, h: 844, mobile: true, wait: 2500,
    steps: ['click:開戰', 'wait:45000'] },
  { name: 'battle-landscape', url: '/?faction=oda&seed=1&battle=1', w: 844, h: 390, mobile: true, wait: 2500,
    steps: ['click:開戰', 'wait:5000'] },
  // 連過 6 個月（1 月→7 月）：今川 5 月出陣、6 月到達 → 應出現桶狹間奇襲選項
  { name: 'okehazama', url: '/?faction=oda&seed=1', w: 390, h: 844, mobile: true,
    steps: Array.from({ length: 6 }, () => ['click:結束回合', 'wait:300', 'click:確定', 'wait:1800', 'click:謝絕', 'wait:200']).flat() },
];
const only = process.argv[3];

async function runStep(page: import('puppeteer-core').Page, step: string) {
  const [kind, arg] = [step.slice(0, step.indexOf(':')), step.slice(step.indexOf(':') + 1)];
  if (kind === 'wait') { await new Promise(r => setTimeout(r, Number(arg))); return; }
  if (kind === 'scroll') { const [sel, px] = arg.split(','); await page.evaluate((s: string, p: number) => { const el = document.querySelector(s); if (el) el.scrollTop = p; }, sel, Number(px)); return; }
  if (kind === 'click') {
    const ok = await page.evaluate((sel: string) => {
      let scope: ParentNode = document;
      let text = sel;
      if (sel.includes('>')) { const [s, t] = sel.split('>'); scope = document.querySelector(s) ?? document; text = t; }
      if (text.startsWith('.') || text.startsWith('#')) { const el = scope.querySelector(text) as HTMLElement | null; el?.click(); return !!el; }
      const els = [...scope.querySelectorAll('button, .cmd, .list-item, .officer, .tactic, .stance')] as HTMLElement[];
      const el = els.find(e => e.textContent?.includes(text));
      el?.click();
      return !!el;
    }, arg);
    if (!ok) console.log(`  step failed: ${step}`);
  }
}

const browser = await puppeteer.launch({ executablePath, headless: true, args: ['--disable-gpu', '--use-gl=swiftshader', '--enable-unsafe-swiftshader'] });
try {
  for (const s of shots) {
    if (only && s.name !== only) continue;
    const page = await browser.newPage();
    const errors: string[] = [];
    page.on('pageerror', e => errors.push(String(e)));
    page.on('console', m => { if (m.type() === 'error') errors.push(m.text()); });
    await page.setViewport({ width: s.w, height: s.h, deviceScaleFactor: 2, isMobile: s.mobile, hasTouch: s.mobile });
    await page.goto(base + s.url, { waitUntil: 'load' });
    await new Promise(r => setTimeout(r, s.wait ?? 2500));
    for (const step of s.steps ?? []) await runStep(page, step);
    const rects = await page.evaluate(() => {
      const out: Record<string, string> = {};
      for (const id of ['app', 'hud', 'map', 'side', 'tabs', 'panel', 'battle']) {
        const el = document.getElementById(id);
        if (!el) continue;
        const r = el.getBoundingClientRect();
        out[id] = `${Math.round(r.x)},${Math.round(r.y)} ${Math.round(r.width)}x${Math.round(r.height)} display=${getComputedStyle(el).display}`;
      }
      out.doc = `${document.documentElement.scrollWidth}x${document.documentElement.scrollHeight} inner=${innerWidth}x${innerHeight}`;
      return out;
    });
    console.log(`[${s.name}]`, JSON.stringify(rects, null, 1));
    if (errors.length) console.log(`  errors:`, errors.slice(0, 5));
    await page.screenshot({ path: `tools/shot-${s.name}.png` });
    await page.close();
  }
} finally {
  await browser.close();
}
