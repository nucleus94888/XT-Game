// 專門為「刀砍稻草人」合成的音效 → hanzo/audio/synth/*.wav（16-bit mono 44.1kHz）
// 用法：node tools/sfx/gen.mjs
// 設計：
//   swing_*        揮空：帶通噪音由低掃高（破風）+ 兩個極短高頻正弦（刀鳴），無金屬迴響
//   straw_light_*  砍進乾草：密集隨機脈衝（草稈斷裂）經帶通 + 短噪音「唰」+ 極輕低頻
//   straw_heavy_*  同上但更密、更長、低頻更沉
//   straw_break    整束稻草爆開：長脈衝雲 + 下墜噪音
import { writeFileSync, mkdirSync } from 'node:fs';

const SR = 44100;
const out = new URL('../../hanzo/audio/synth/', import.meta.url);
mkdirSync(out, { recursive: true });

let seed = 1;
const rng = () => { seed = (seed * 1664525 + 1013904223) >>> 0; return seed / 4294967296 * 2 - 1; };
const r01 = () => (rng() + 1) / 2;

function wav(samples) {
  const n = samples.length, buf = Buffer.alloc(44 + n * 2);
  buf.write('RIFF', 0); buf.writeUInt32LE(36 + n * 2, 4); buf.write('WAVE', 8);
  buf.write('fmt ', 12); buf.writeUInt32LE(16, 16); buf.writeUInt16LE(1, 20); buf.writeUInt16LE(1, 22);
  buf.writeUInt32LE(SR, 24); buf.writeUInt32LE(SR * 2, 28); buf.writeUInt16LE(2, 32); buf.writeUInt16LE(16, 34);
  buf.write('data', 36); buf.writeUInt32LE(n * 2, 40);
  for (let i = 0; i < n; i++) buf.writeInt16LE(Math.round(Math.max(-1, Math.min(1, samples[i])) * 32767), 44 + i * 2);
  return buf;
}
const env = (t, a, d) => (t < a ? t / a : Math.exp(-(t - a) / d));
// RBJ 帶通（每個取樣重算係數，支援掃頻）
function makeBP() {
  const s = { x1: 0, x2: 0, y1: 0, y2: 0 };
  return (x, f0, Q) => {
    const w0 = 2 * Math.PI * f0 / SR, al = Math.sin(w0) / (2 * Q), c = Math.cos(w0);
    const b0 = al, b2 = -al, a0 = 1 + al, a1 = -2 * c, a2 = 1 - al;
    const y = (b0 * x + b2 * s.x2 - a1 * s.y1 - a2 * s.y2) / a0;
    s.x2 = s.x1; s.x1 = x; s.y2 = s.y1; s.y1 = y;
    return y;
  };
}
function render(dur, fn) {
  const n = Math.floor(SR * dur), o = new Float32Array(n);
  const st = { bp1: makeBP(), bp2: makeBP(), bp3: makeBP(), crack: 0 };
  for (let i = 0; i < n; i++) o[i] = fn(i / SR, st);
  return o;
}
const soft = (x) => Math.tanh(x * 1.3);
function normalize(o, peak = 0.9) {
  let m = 0; for (const v of o) m = Math.max(m, Math.abs(v));
  if (m > 0) for (let i = 0; i < o.length; i++) o[i] = o[i] / m * peak;
  return o;
}

// 揮空：破風 + 刀鳴（兩個高頻正弦 40ms 內衰減，不留迴響）
function swing(variant) {
  seed = 100 + variant;
  const dur = 0.17;
  return render(dur, (t, st) => {
    const k = t / dur;
    const f = 700 + 4200 * Math.pow(k, 0.7);
    const whoosh = st.bp1(rng(), f, 1.2) * 2.2 * env(t, 0.02, 0.045);
    const air = st.bp2(rng(), 2500, 0.6) * 0.5 * env(t, 0.01, 0.06);
    const ring = (Math.sin(2 * Math.PI * 4300 * t) + 0.6 * Math.sin(2 * Math.PI * 6800 * t)) * 0.12 * (t > 0.025 ? env(t - 0.025, 0.002, 0.018) : 0);
    return soft(whoosh + air + ring);
  });
}

// 砍進乾草：脈衝雲（草稈斷裂）+ 唰 + 極輕低頻
function straw(variant, heavy) {
  seed = 200 + variant + (heavy ? 50 : 0);
  const dur = heavy ? 0.24 : 0.14;
  const rate0 = heavy ? 0.45 : 0.3;    // 初始每取樣脈衝機率
  return render(dur, (t, st) => {
    const k = t / dur;
    const p = rate0 * Math.exp(-k * 5.5);
    if (r01() < p) st.crack = rng() * (0.6 + 0.4 * r01());
    st.crack *= 0.72;
    const cr = st.bp1(st.crack, heavy ? 2400 : 3200, 0.9) * 3.0;
    const swish = st.bp2(rng(), 1800 + 1500 * (1 - k), 0.7) * 1.2 * env(t, 0.004, heavy ? 0.05 : 0.035);
    const body = Math.sin(2 * Math.PI * (heavy ? 70 : 95) * t) * (heavy ? 0.5 : 0.25) * env(t, 0.003, heavy ? 0.07 : 0.04);
    return soft(cr * env(t, 0.002, heavy ? 0.12 : 0.07) + swish + body);
  });
}

// 整束稻草爆開：長脈衝雲 + 由高往低的噪音 + 沉低頻
function strawBreak() {
  seed = 300;
  const dur = 0.42;
  return render(dur, (t, st) => {
    const k = t / dur;
    const p = 0.5 * Math.exp(-k * 3.0);
    if (r01() < p) st.crack = rng();
    st.crack *= 0.75;
    const cr = st.bp1(st.crack, 2600, 0.8) * 3.0 * env(t, 0.003, 0.2);
    const fall = st.bp2(rng(), 3500 * Math.exp(-k * 2.5) + 400, 0.8) * 1.0 * env(t, 0.01, 0.12);
    const body = Math.sin(2 * Math.PI * (60 * Math.exp(-t * 6) + 40) * t) * 0.6 * env(t, 0.004, 0.1);
    return soft(cr + fall + body);
  });
}

const files = {
  swing_1: swing(1), swing_2: swing(2), swing_3: swing(3),
  straw_light_1: straw(1, false), straw_light_2: straw(2, false), straw_light_3: straw(3, false),
  straw_heavy_1: straw(1, true), straw_heavy_2: straw(2, true), straw_heavy_3: straw(3, true),
  straw_break: strawBreak(),
};
for (const [name, s] of Object.entries(files)) {
  writeFileSync(new URL(`${name}.wav`, out), wav(normalize(s)));
  console.log('wrote', `${name}.wav`, `${(s.length / SR * 1000).toFixed(0)}ms`);
}
