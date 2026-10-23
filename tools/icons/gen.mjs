// 程式繪製 App 圖示 → hanzo/icons/icon_{1024,512,180,144}.png（不透明，符合 iOS 要求）
// 純 Node，無任何依賴（自寫 PNG 編碼器）。用法：node tools/icons/gen.mjs
import { deflateSync } from 'node:zlib';
import { writeFileSync, mkdirSync } from 'node:fs';

const out = new URL('../../hanzo/icons/', import.meta.url);
mkdirSync(out, { recursive: true });

const CRC = new Uint32Array(256);
for (let n = 0; n < 256; n++) {
  let c = n;
  for (let k = 0; k < 8; k++) c = c & 1 ? 0xedb88320 ^ (c >>> 1) : c >>> 1;
  CRC[n] = c >>> 0;
}
function crc32(buf) {
  let c = 0xffffffff;
  for (let i = 0; i < buf.length; i++) c = CRC[(c ^ buf[i]) & 0xff] ^ (c >>> 8);
  return (c ^ 0xffffffff) >>> 0;
}
function chunk(type, data) {
  const len = Buffer.alloc(4); len.writeUInt32BE(data.length);
  const td = Buffer.concat([Buffer.from(type, 'ascii'), data]);
  const crc = Buffer.alloc(4); crc.writeUInt32BE(crc32(td));
  return Buffer.concat([len, td, crc]);
}
function png(w, h, rgb) {
  const raw = Buffer.alloc((w * 3 + 1) * h);
  for (let y = 0; y < h; y++) {
    raw[y * (w * 3 + 1)] = 0;
    rgb.copy(raw, y * (w * 3 + 1) + 1, y * w * 3, (y + 1) * w * 3);
  }
  const ihdr = Buffer.alloc(13);
  ihdr.writeUInt32BE(w, 0); ihdr.writeUInt32BE(h, 4);
  ihdr[8] = 8; ihdr[9] = 2; ihdr[10] = 0; ihdr[11] = 0; ihdr[12] = 0;
  return Buffer.concat([
    Buffer.from([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]),
    chunk('IHDR', ihdr), chunk('IDAT', deflateSync(raw, { level: 9 })), chunk('IEND', Buffer.alloc(0)),
  ]);
}

// 設計：墨黑底、朱紅日輪、一道白刃斜切而過
const BG = [0x14, 0x15, 0x1a];
const RED = [0xb8, 0x35, 0x2a];
const INK = [0xf4, 0xf1, 0xea];
const mix = (a, b, t) => a.map((v, i) => v + (b[i] - v) * t);
const clamp01 = (x) => Math.max(0, Math.min(1, x));

function shade(u, v) {
  // u,v ∈ [0,1]
  let col = BG;
  const dx = u - 0.52, dy = v - 0.47;
  const r = Math.hypot(dx, dy);
  col = mix(col, RED, clamp01((0.31 - r) * 400));
  // 刀光：從左下到右上的曲線帶，中段最寬、兩端收尖
  const t = clamp01((u + (1 - v)) / 2);            // 沿對角線位置
  const cx = 0.16 + 0.70 * t, cy = 0.84 - 0.64 * t; // 中心線
  const bend = Math.sin(t * Math.PI) * 0.06;        // 微彎
  const d = Math.abs((v - (cy - bend)) * 0.7 + (u - cx) * 0.7) / Math.SQRT2 * 2;
  const width = 0.012 + 0.045 * Math.pow(Math.sin(t * Math.PI), 0.8);
  col = mix(col, INK, clamp01((width - d) * 500));
  return col;
}

function draw(S) {
  const rgb = Buffer.alloc(S * S * 3);
  const ss = 3; // 超取樣抗鋸齒
  for (let y = 0; y < S; y++) for (let x = 0; x < S; x++) {
    let acc = [0, 0, 0];
    for (let sy = 0; sy < ss; sy++) for (let sx = 0; sx < ss; sx++) {
      const c = shade((x + (sx + 0.5) / ss) / S, (y + (sy + 0.5) / ss) / S);
      acc = acc.map((v, i) => v + c[i]);
    }
    const o = (y * S + x) * 3;
    for (let i = 0; i < 3; i++) rgb[o + i] = Math.round(acc[i] / (ss * ss));
  }
  return png(S, S, rgb);
}

for (const S of [1024, 512, 180, 144]) {
  writeFileSync(new URL(`icon_${S}.png`, out), draw(S));
  console.log('wrote', `icon_${S}.png`);
}
