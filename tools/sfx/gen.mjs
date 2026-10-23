// 程式合成音效 → hanzo/audio/*.wav（16-bit mono 44.1kHz）
// 不靠任何素材網站、不需登入、可重現（固定亂數種子）。
// 用法：node tools/sfx/gen.mjs
import { writeFileSync, mkdirSync } from 'node:fs';

const SR = 44100;
const out = new URL('../../hanzo/audio/', import.meta.url);
mkdirSync(out, { recursive: true });

let seed = 20261023;
const rng = () => {
  seed = (seed * 1664525 + 1013904223) >>> 0;
  return seed / 4294967296 * 2 - 1; // -1..1
};
const rand01 = () => (rng() + 1) / 2;

function wav(samples) {
  const n = samples.length;
  const buf = Buffer.alloc(44 + n * 2);
  buf.write('RIFF', 0); buf.writeUInt32LE(36 + n * 2, 4); buf.write('WAVE', 8);
  buf.write('fmt ', 12); buf.writeUInt32LE(16, 16); buf.writeUInt16LE(1, 20); buf.writeUInt16LE(1, 22);
  buf.writeUInt32LE(SR, 24); buf.writeUInt32LE(SR * 2, 28); buf.writeUInt16LE(2, 32); buf.writeUInt16LE(16, 34);
  buf.write('data', 36); buf.writeUInt32LE(n * 2, 40);
  for (let i = 0; i < n; i++) {
    const v = Math.max(-1, Math.min(1, samples[i]));
    buf.writeInt16LE(Math.round(v * 32767), 44 + i * 2);
  }
  return buf;
}

function render(dur, fn) {
  const n = Math.floor(SR * dur);
  const o = new Float32Array(n);
  const st = { lp: 0, crack: 0 };
  for (let i = 0; i < n; i++) o[i] = fn(i / SR, st);
  return o;
}
// 包絡：attack 秒線性起、之後以 decay 時間常數指數衰減
const env = (t, a, d) => (t < a ? t / a : Math.exp(-(t - a) / d));
// 一階低通
function lp(st, x, cutoff) {
  const a = 1 - Math.exp(-2 * Math.PI * cutoff / SR);
  st.lp += a * (x - st.lp);
  return st.lp;
}
const softclip = (x) => Math.tanh(x * 1.4);
function normalize(o, peak = 0.9) {
  let m = 0;
  for (const v of o) m = Math.max(m, Math.abs(v));
  if (m > 0) for (let i = 0; i < o.length; i++) o[i] = o[i] / m * peak;
  return o;
}

// 揮刀：噴氣噪音，濾波由低掃高
const swing = render(0.2, (t, st) => {
  const n = rng();
  const cut = 500 + 5000 * Math.pow(t / 0.2, 0.6);
  const f = lp(st, n, cut);
  return (n - f * 0.7) * env(t, 0.012, 0.05);
});
// 命中（輕）：低頻降音錘擊 + 極短喀嚦 + 高頻殘響
const hit = render(0.18, (t, st) => {
  const f0 = 140 * Math.exp(-t * 18) + 45;
  const thump = Math.sin(2 * Math.PI * f0 * t) * env(t, 0.002, 0.06);
  const click = rng() * env(t, 0.0005, 0.008) * 0.9;
  const ring = Math.sin(2 * Math.PI * 1900 * t) * env(t, 0.001, 0.02) * 0.35;
  return softclip(thump * 1.2 + click + ring);
});
// 命中（重）：更低更長的錘擊 + 碎裂噪音 + 次低音
const heavy = render(0.34, (t, st) => {
  const f0 = 95 * Math.exp(-t * 9) + 32;
  const thump = Math.sin(2 * Math.PI * f0 * t) * env(t, 0.003, 0.12);
  const crunch = lp(st, rng(), 1800) * env(t, 0.001, 0.045) * 1.4;
  const sub = Math.sin(2 * Math.PI * 48 * t) * env(t, 0.01, 0.15) * 0.6;
  return softclip(thump * 1.3 + crunch + sub);
});
// 閃步：空氣聲由高往低
const dash = render(0.24, (t, st) => {
  const n = rng();
  const cut = 4500 * Math.exp(-t * 9) + 300;
  return lp(st, n, cut) * 1.6 * env(t, 0.02, 0.08);
});
// 受傷：粗糙方波降音 + 噪音
const hurt = render(0.28, (t, st) => {
  const f0 = 260 * Math.exp(-t * 6) + 60;
  const sq = Math.sign(Math.sin(2 * Math.PI * f0 * t)) * 0.5;
  const n = lp(st, rng(), 2500) * 0.5;
  return softclip((sq + n) * env(t, 0.004, 0.09));
});
// 擊破：木頭裂響（隨機脈衝）+ 低頻倒地 + 碎屑
const brk = render(0.5, (t, st) => {
  if (rand01() < 0.015 * Math.exp(-t * 4)) st.crack = (rng() > 0 ? 1 : -1) * 0.9;
  st.crack *= 0.93;
  const thump = Math.sin(2 * Math.PI * (70 * Math.exp(-t * 7) + 35) * t) * env(t, 0.003, 0.14);
  const debris = lp(st, rng(), 1200) * env(t, 0.01, 0.2) * 0.5;
  return softclip(thump + st.crack + debris);
});

for (const [name, s] of Object.entries({ swing, hit, heavy, dash, hurt, break: brk })) {
  writeFileSync(new URL(`${name}.wav`, out), wav(normalize(s)));
  console.log('wrote', `${name}.wav`, `${(s.length / SR * 1000).toFixed(0)}ms`);
}
