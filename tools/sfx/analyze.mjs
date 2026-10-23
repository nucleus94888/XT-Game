// 粗略分析 WAV：長度、起音時間（到 50% 峰值）、尾音長度（峰值後降到 -30dB）、亮度（零交越率）
import { readFileSync, readdirSync } from 'node:fs';
import { join } from 'node:path';
function readWav(p) {
  const b = readFileSync(p); const ch = b.readUInt16LE(22), sr = b.readUInt32LE(24), bits = b.readUInt16LE(34);
  let off = 12; let data;
  while (off < b.length) { const id = b.toString('ascii', off, off + 4), len = b.readUInt32LE(off + 4); if (id === 'data') { data = b.subarray(off + 8, off + 8 + len); break; } off += 8 + len; }
  const n = Math.floor(data.length / (bits / 8) / ch); const s = new Float32Array(n);
  const bps = bits / 8; for (let i = 0; i < n; i++) { let v = 0; for (let c = 0; c < ch; c++) { const o = (i * ch + c) * bps; v += bits === 16 ? data.readInt16LE(o) / 32768 : bits === 24 ? ((data[o] | (data[o + 1] << 8) | (data[o + 2] << 16)) << 8 >> 8) / 8388608 : data.readInt32LE(o) / 2147483648; } s[i] = v / ch; }
  return { sr, s };
}
const dir = process.argv[2];
for (const f of readdirSync(dir).filter((x) => x.endsWith('.wav')).sort()) {
  const { sr, s } = readWav(join(dir, f)); const n = s.length; const bits = readFileSync(join(dir, f)).readUInt16LE(34);
  let peak = 0, pi = 0; for (let i = 0; i < n; i++) { const a = Math.abs(s[i]); if (a > peak) { peak = a; pi = i; } }
  let onset = 0; for (let i = 0; i < n; i++) if (Math.abs(s[i]) > peak * 0.5) { onset = i; break; }
  let first = 0; for (let i = 0; i < n; i++) if (Math.abs(s[i]) > peak * 0.05) { first = i; break; }
  const win = Math.floor(sr * 0.01); let tail = n; for (let i = pi; i + win < n; i += win) { let r = 0; for (let j = 0; j < win; j++) r += s[i + j] * s[i + j]; r = Math.sqrt(r / win); if (r < peak * 0.03) { tail = i; break; } }
  let zc = 0; for (let i = 1; i < n; i++) if ((s[i] >= 0) !== (s[i - 1] >= 0)) zc++;
  console.log(`${f.padEnd(10)} ${bits}bit len ${(n / sr).toFixed(2)}s  起音 ${((onset - first) / sr * 1000).toFixed(0)}ms(前靜音 ${(first / sr * 1000).toFixed(0)}ms)  峰值@${(pi / sr * 1000).toFixed(0)}ms  尾音 ${((tail - pi) / sr * 1000).toFixed(0)}ms  亮度 ${(zc / (n / sr) / 1000).toFixed(1)}kHz`);
}
