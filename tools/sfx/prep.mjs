// 把挑好的音效整理成遊戲用格式：單聲道 16-bit 44.1kHz、去掉前段靜音、限制長度、淡出、正規化。
// 用法：node tools/sfx/prep.mjs <來源目錄> <輸出目錄> name=srcfile[:maxMs[:gainDb]] ...
//   例：node tools/sfx/prep.mjs C:/tmp/mixkit hanzo/audio/mixkit swing_1=2792.wav:220 hit_1=2166.wav:260:-2
import { readFileSync, writeFileSync, mkdirSync } from 'node:fs';
import { join } from 'node:path';

const SR = 44100;
function readWav(p) {
  const b = readFileSync(p); const ch = b.readUInt16LE(22), sr = b.readUInt32LE(24), bits = b.readUInt16LE(34);
  let off = 12, data;
  while (off < b.length) { const id = b.toString('ascii', off, off + 4), len = b.readUInt32LE(off + 4); if (id === 'data') { data = b.subarray(off + 8, off + 8 + len); break; } off += 8 + len; }
  const bps = bits / 8, n = Math.floor(data.length / bps / ch), s = new Float32Array(n);
  for (let i = 0; i < n; i++) { let v = 0; for (let c = 0; c < ch; c++) { const o = (i * ch + c) * bps; v += bits === 16 ? data.readInt16LE(o) / 32768 : bits === 24 ? ((data[o] | (data[o + 1] << 8) | (data[o + 2] << 16)) << 8 >> 8) / 8388608 : data.readInt32LE(o) / 2147483648; } s[i] = v / ch; }
  return { sr, s };
}
function resample(s, from, to) {
  if (from === to) return s;
  const n = Math.floor(s.length * to / from), o = new Float32Array(n);
  for (let i = 0; i < n; i++) { const x = i * from / to, i0 = Math.floor(x), f = x - i0; o[i] = s[i0] * (1 - f) + (s[Math.min(i0 + 1, s.length - 1)] || 0) * f; }
  return o;
}
function wav(samples) {
  const n = samples.length, buf = Buffer.alloc(44 + n * 2);
  buf.write('RIFF', 0); buf.writeUInt32LE(36 + n * 2, 4); buf.write('WAVE', 8);
  buf.write('fmt ', 12); buf.writeUInt32LE(16, 16); buf.writeUInt16LE(1, 20); buf.writeUInt16LE(1, 22);
  buf.writeUInt32LE(SR, 24); buf.writeUInt32LE(SR * 2, 28); buf.writeUInt16LE(2, 32); buf.writeUInt16LE(16, 34);
  buf.write('data', 36); buf.writeUInt32LE(n * 2, 40);
  for (let i = 0; i < n; i++) buf.writeInt16LE(Math.round(Math.max(-1, Math.min(1, samples[i])) * 32767), 44 + i * 2);
  return buf;
}

const [srcDir, outDir, ...specs] = process.argv.slice(2);
mkdirSync(outDir, { recursive: true });
for (const spec of specs) {
  const [name, rest] = spec.split('=');
  const [file, maxMs = '400', gainDb = '0'] = rest.split(':');
  let { sr, s } = readWav(join(srcDir, file));
  s = resample(s, sr, SR);
  let peak = 0; for (const v of s) peak = Math.max(peak, Math.abs(v));
  // 去前段靜音：第一個超過峰值 3% 的取樣往前留 2ms
  let first = 0; for (let i = 0; i < s.length; i++) if (Math.abs(s[i]) > peak * 0.03) { first = Math.max(0, i - Math.floor(SR * 0.002)); break; }
  const maxN = Math.floor(SR * Number(maxMs) / 1000);
  let o = s.subarray(first, Math.min(s.length, first + maxN));
  o = Float32Array.from(o);
  // 淡入 1ms、淡出最後 15%（至少 20ms）
  const fi = Math.floor(SR * 0.001), fo = Math.max(Math.floor(o.length * 0.15), Math.floor(SR * 0.02));
  for (let i = 0; i < fi && i < o.length; i++) o[i] *= i / fi;
  for (let i = 0; i < fo && i < o.length; i++) o[o.length - 1 - i] *= i / fo;
  const g = Math.pow(10, Number(gainDb) / 20) * 0.9 / (peak || 1);
  for (let i = 0; i < o.length; i++) o[i] *= g;
  writeFileSync(join(outDir, `${name}.wav`), wav(o));
  console.log(`${name}.wav ← ${file}  ${(o.length / SR * 1000).toFixed(0)}ms`);
}
