// 武將水墨剪影：依 id 雜湊決定頭盔/體型變化，純 SVG
import { OFFICER_MAP } from '../core/state';

function hash(s: string): number { let h = 2166136261; for (let i = 0; i < s.length; i++) { h ^= s.charCodeAt(i); h = Math.imul(h, 16777619); } return h >>> 0; }

const cache = new Map<string, string>();

export function silhouetteSvg(id: string, color = '#1f1a17'): string {
  const key = id + color;
  const hit = cache.get(key); if (hit) return hit;
  const d = OFFICER_MAP[id];
  const h = hash(id);
  const helmet = h % 5;              // 0 無 1 鍬形 2 角 3 日輪 4 烏帽子（文官）
  const broad = d ? 6 + d.valor / 12 : 10;   // 肩寬
  const hair = (h >> 3) % 3;
  const parts: string[] = [];
  // 肩
  parts.push(`<path d="M${50 - broad - 14} 100 Q${50 - broad} 62 50 60 Q${50 + broad} 62 ${50 + broad + 14} 100 Z" fill="${color}"/>`);
  // 頸
  parts.push(`<rect x="44" y="48" width="12" height="14" fill="${color}"/>`);
  // 頭
  parts.push(`<ellipse cx="50" cy="38" rx="14" ry="16" fill="${color}"/>`);
  // 髮/盔
  if (helmet === 4) {
    parts.push(`<path d="M38 30 Q50 -4 62 30 Z" fill="${color}"/>`); // 烏帽子
  } else {
    parts.push(`<path d="M34 34 Q50 ${12 + hair * 3} 66 34 L66 40 Q50 ${24 + hair * 2} 34 40 Z" fill="${color}"/>`); // 兜
    parts.push(`<path d="M30 40 Q50 48 70 40 L70 44 Q50 54 30 44 Z" fill="${color}"/>`); // 錣
    if (helmet === 1) parts.push(`<path d="M44 22 L30 2 L46 18 Z M56 22 L70 2 L54 18 Z" fill="${color}"/>`); // 鍬形
    if (helmet === 2) parts.push(`<path d="M42 20 Q30 10 36 0 Q40 12 46 18 Z M58 20 Q70 10 64 0 Q60 12 54 18 Z" fill="${color}"/>`); // 角
    if (helmet === 3) parts.push(`<circle cx="50" cy="14" r="7" fill="${color}"/>`); // 日輪前立
  }
  // 墨暈
  parts.push(`<ellipse cx="50" cy="100" rx="${broad + 18}" ry="4" fill="${color}" opacity="0.25"/>`);
  const svg = `<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 100 104">${parts.join('')}</svg>`;
  cache.set(key, svg);
  return svg;
}

export function silhouetteDataUrl(id: string, color?: string): string {
  return 'data:image/svg+xml;charset=utf-8,' + encodeURIComponent(silhouetteSvg(id, color));
}
