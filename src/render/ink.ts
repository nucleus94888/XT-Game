// ===== 水墨風共用工具 =====
// 和紙質感、toon 漸層、墨線描邊、家紋 sprite、墨漬島形等共用輔助。

import * as THREE from 'three';
import { kamonDataUrl, type KamonId } from '../data/kamon';

/** 和紙的米色底 */
export const PAPER_CREAM = 0xf1e7d0;
/** 墨色 */
export const INK = 0x1c1915;

// ---------------------------------------------------------------------------
// 亂數 / 顏色
// ---------------------------------------------------------------------------

/** 極小型的 mulberry32 PRNG（決定性）。 */
export function mulberry32(seed: number): () => number {
  let a = seed >>> 0;
  return () => {
    a = (a + 0x6d2b79f5) >>> 0;
    let t = a;
    t = Math.imul(t ^ (t >>> 15), t | 1);
    t ^= t + Math.imul(t ^ (t >>> 7), t | 61);
    return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
  };
}

/** 線性混合兩個十六進位顏色，t = 0 回傳 a，t = 1 回傳 b。 */
export function mixColor(a: number, b: number, t: number): number {
  const ca = new THREE.Color(a);
  const cb = new THREE.Color(b);
  return ca.lerp(cb, t).getHex();
}

/** 把勢力色「洗淡」成水墨地圖用的淡彩。 */
export function mutedColor(color: number, amount = 0.5): number {
  return mixColor(color, PAPER_CREAM, amount);
}

// ---------------------------------------------------------------------------
// 和紙材質
// ---------------------------------------------------------------------------

let paperCache: THREE.Texture | null = null;

/** 程序式和紙：米色底 + 斑點 + 纖維條紋。重複包裹。 */
export function makePaperTexture(size = 512): THREE.Texture {
  if (paperCache) return paperCache;
  const canvas = document.createElement('canvas');
  canvas.width = size;
  canvas.height = size;
  const ctx = canvas.getContext('2d')!;
  const rnd = mulberry32(1560);

  ctx.fillStyle = '#f1e7d0';
  ctx.fillRect(0, 0, size, size);

  // 為了無縫重複，跨越邊界的圖樣在九個位移處各畫一次
  const wrapped = (draw: (ox: number, oy: number) => void): void => {
    for (let ox = -1; ox <= 1; ox++) for (let oy = -1; oy <= 1; oy++) draw(ox * size, oy * size);
  };

  // 大面積的淡雲紋（讓紙面不均勻）
  for (let i = 0; i < 14; i++) {
    const x = rnd() * size;
    const y = rnd() * size;
    const r = size * (0.15 + rnd() * 0.3);
    const dark = rnd() > 0.5;
    wrapped((ox, oy) => {
      const g = ctx.createRadialGradient(x + ox, y + oy, 0, x + ox, y + oy, r);
      g.addColorStop(0, dark ? 'rgba(150,120,80,0.06)' : 'rgba(255,250,235,0.10)');
      g.addColorStop(1, 'rgba(0,0,0,0)');
      ctx.fillStyle = g;
      ctx.fillRect(x + ox - r, y + oy - r, r * 2, r * 2);
    });
  }

  // 纖維條紋：略彎的細線
  ctx.lineWidth = 1;
  for (let i = 0; i < 260; i++) {
    const x = rnd() * size;
    const y = rnd() * size;
    const len = 10 + rnd() * 60;
    const ang = (rnd() - 0.5) * 0.9 + (rnd() > 0.5 ? 0 : Math.PI / 2);
    const a = 0.03 + rnd() * 0.07;
    const c1 = (rnd() - 0.5) * 6, c2 = (rnd() - 0.5) * 6;
    ctx.strokeStyle = rnd() > 0.3 ? `rgba(120,95,60,${a})` : `rgba(255,255,255,${a + 0.05})`;
    wrapped((ox, oy) => {
      ctx.beginPath();
      ctx.moveTo(x + ox, y + oy);
      ctx.quadraticCurveTo(
        x + ox + Math.cos(ang) * len * 0.5 + c1,
        y + oy + Math.sin(ang) * len * 0.5 + c2,
        x + ox + Math.cos(ang) * len,
        y + oy + Math.sin(ang) * len,
      );
      ctx.stroke();
    });
  }

  // 斑點
  for (let i = 0; i < 2600; i++) {
    const x = rnd() * size;
    const y = rnd() * size;
    const r = 0.4 + rnd() * 1.3;
    const a = 0.04 + rnd() * 0.12;
    ctx.fillStyle = rnd() > 0.25 ? `rgba(110,85,50,${a})` : `rgba(60,50,40,${a})`;
    ctx.beginPath();
    ctx.arc(x, y, r, 0, Math.PI * 2);
    ctx.fill();
  }

  const tex = new THREE.CanvasTexture(canvas);
  tex.wrapS = THREE.RepeatWrapping;
  tex.wrapT = THREE.RepeatWrapping;
  tex.colorSpace = THREE.SRGBColorSpace;
  tex.anisotropy = 4;
  paperCache = tex;
  return tex;
}

// ---------------------------------------------------------------------------
// Toon 漸層 / 材質
// ---------------------------------------------------------------------------

let gradientCache: THREE.DataTexture | null = null;

/** 三階漸層貼圖，給 MeshToonMaterial 用。 */
export function makeToonGradient(): THREE.DataTexture {
  if (gradientCache) return gradientCache;
  const data = new Uint8Array([120, 190, 255]);
  const tex = new THREE.DataTexture(data, 3, 1, THREE.RedFormat);
  tex.minFilter = THREE.NearestFilter;
  tex.magFilter = THREE.NearestFilter;
  tex.generateMipmaps = false;
  tex.needsUpdate = true;
  gradientCache = tex;
  return tex;
}

/** 使用三階漸層的 toon 材質。 */
export function inkMaterial(color: number, opts: { opacity?: number } = {}): THREE.MeshToonMaterial {
  const opacity = opts.opacity ?? 1;
  return new THREE.MeshToonMaterial({
    color,
    gradientMap: makeToonGradient(),
    transparent: opacity < 1,
    opacity,
  });
}

// ---------------------------------------------------------------------------
// 墨線描邊
// ---------------------------------------------------------------------------

/**
 * 以背面放大的方式替網格加上深色「墨線」。
 * `thickness` 為世界單位（依包圍球半徑換算成縮放比例）。
 * 回傳的描邊網格已加為 `mesh` 的子物件。
 */
export function addOutline(mesh: THREE.Mesh, thickness = 0.12, color: number = INK): THREE.Mesh {
  const geom = mesh.geometry;
  if (!geom.boundingSphere) geom.computeBoundingSphere();
  const r = Math.max(geom.boundingSphere?.radius ?? 1, 0.01);
  const s = 1 + thickness / r;
  const mat = new THREE.MeshBasicMaterial({ color, side: THREE.BackSide });
  const outline = new THREE.Mesh(geom, mat);
  outline.scale.setScalar(s);
  outline.name = 'outline';
  outline.raycast = () => {};
  mesh.add(outline);
  return outline;
}

// ---------------------------------------------------------------------------
// 家紋圖像 / sprite
// ---------------------------------------------------------------------------

const imageCache = new Map<string, Promise<HTMLImageElement>>();

/** 載入家紋 SVG 成 HTMLImageElement（依 id+color 快取）。 */
export function loadKamonImage(kamonId: string, color: string): Promise<HTMLImageElement> {
  const key = `${kamonId}|${color}`;
  let p = imageCache.get(key);
  if (!p) {
    p = new Promise<HTMLImageElement>((resolve, reject) => {
      const img = new Image();
      img.onload = () => resolve(img);
      img.onerror = () => reject(new Error(`kamon load failed: ${kamonId}`));
      img.src = kamonDataUrl(kamonId as KamonId, color);
    });
    imageCache.set(key, p);
  }
  return p;
}

const kamonTexCache = new Map<string, THREE.CanvasTexture>();

export interface KamonOpts {
  /** 在家紋後面加一個圓形底（顏色字串），並以墨線描圓 */
  badge?: string;
}

/**
 * 家紋貼圖（透明底）。先回傳空白貼圖，SVG 載入後再更新。
 * 以 id+color(+badge) 快取，重複使用同一張貼圖。
 */
export function kamonTexture(kamonId: string, color: string, px = 256, opts: KamonOpts = {}): THREE.CanvasTexture {
  const key = `${kamonId}|${color}|${px}|${opts.badge ?? ''}`;
  const cached = kamonTexCache.get(key);
  if (cached) return cached;
  const canvas = document.createElement('canvas');
  canvas.width = px;
  canvas.height = px;
  const ctx = canvas.getContext('2d')!;
  const drawBadge = (): void => {
    if (!opts.badge) return;
    ctx.beginPath();
    ctx.arc(px / 2, px / 2, px * 0.47, 0, Math.PI * 2);
    ctx.fillStyle = opts.badge;
    ctx.fill();
    ctx.lineWidth = px * 0.035;
    ctx.strokeStyle = '#1c1915';
    ctx.stroke();
  };
  drawBadge();
  const tex = new THREE.CanvasTexture(canvas);
  tex.colorSpace = THREE.SRGBColorSpace;
  tex.anisotropy = 4;
  kamonTexCache.set(key, tex);
  loadKamonImage(kamonId, color)
    .then((img) => {
      ctx.clearRect(0, 0, px, px);
      drawBadge();
      const inset = opts.badge ? px * 0.17 : 0;
      ctx.drawImage(img, inset, inset, px - inset * 2, px - inset * 2);
      tex.needsUpdate = true;
    })
    .catch(() => {});
  return tex;
}

/** 家紋 sprite；材質透明，大小以世界單位計。 */
export function kamonSprite(kamonId: string, color: string, size: number, opts: KamonOpts = {}): THREE.Sprite {
  const mat = new THREE.SpriteMaterial({
    map: kamonTexture(kamonId, color, 256, opts),
    transparent: true,
    depthWrite: false,
  });
  const sprite = new THREE.Sprite(mat);
  sprite.scale.set(size, size, 1);
  sprite.name = `kamon:${kamonId}`;
  return sprite;
}

// ---------------------------------------------------------------------------
// 文字 sprite（CanvasTexture）
// ---------------------------------------------------------------------------

export interface TextStyle {
  /** 字高（px），貼圖解析度 */
  px?: number;
  color?: string;
  font?: string;
  /** 外暈（增加可讀性） */
  halo?: string;
}

const textTexCache = new Map<string, { tex: THREE.CanvasTexture; aspect: number }>();

/** 產生（並快取）文字貼圖。回傳貼圖與寬高比。 */
export function textTexture(text: string, style: TextStyle = {}): { tex: THREE.CanvasTexture; aspect: number } {
  const px = style.px ?? 48;
  const color = style.color ?? '#1c1915';
  const font = style.font ?? `700 ${px}px "Noto Serif TC", "Noto Serif JP", "Yu Mincho", "Hiragino Mincho ProN", "PMingLiU", Georgia, serif`;
  const halo = style.halo ?? 'rgba(241,231,208,0.95)';
  const key = `${text}|${px}|${color}|${font}|${halo}`;
  const cached = textTexCache.get(key);
  if (cached) return cached;

  const measure = document.createElement('canvas').getContext('2d')!;
  measure.font = font;
  const w = Math.ceil(measure.measureText(text).width) + px * 0.6;
  const h = Math.ceil(px * 1.4);
  const canvas = document.createElement('canvas');
  canvas.width = w;
  canvas.height = h;
  const ctx = canvas.getContext('2d')!;
  ctx.font = font;
  ctx.textAlign = 'center';
  ctx.textBaseline = 'middle';
  ctx.lineJoin = 'round';
  ctx.strokeStyle = halo;
  ctx.lineWidth = px * 0.22;
  ctx.strokeText(text, w / 2, h / 2);
  ctx.fillStyle = color;
  ctx.fillText(text, w / 2, h / 2);

  const tex = new THREE.CanvasTexture(canvas);
  tex.colorSpace = THREE.SRGBColorSpace;
  tex.minFilter = THREE.LinearFilter;
  const entry = { tex, aspect: w / h };
  textTexCache.set(key, entry);
  return entry;
}

/** 文字 sprite，`height` 為世界單位的字高。 */
export function textSprite(text: string, height: number, style: TextStyle = {}): THREE.Sprite {
  const { tex, aspect } = textTexture(text, style);
  const mat = new THREE.SpriteMaterial({ map: tex, transparent: true, depthWrite: false });
  const sprite = new THREE.Sprite(mat);
  sprite.scale.set(height * aspect, height, 1);
  sprite.name = `text:${text}`;
  return sprite;
}

/** 更新既有文字 sprite 的內容（沿用快取貼圖）。 */
export function setSpriteText(sprite: THREE.Sprite, text: string, height: number, style: TextStyle = {}): void {
  if (sprite.name === `text:${text}`) return;
  const { tex, aspect } = textTexture(text, style);
  sprite.material.map = tex;
  sprite.material.needsUpdate = true;
  sprite.scale.set(height * aspect, height, 1);
  sprite.name = `text:${text}`;
}

// ---------------------------------------------------------------------------
// 墨漬島形
// ---------------------------------------------------------------------------

/** 不規則的有機多邊形（墨漬島），以 seed 決定抖動；用 Catmull-Rom 平滑。 */
export function blobShape(radius: number, seed: number, points = 14): THREE.Shape {
  const rnd = mulberry32(seed);
  const pts: THREE.Vector2[] = [];
  // 低頻起伏讓島不是「圓加噪音」而是有長短軸
  const squash = 0.78 + rnd() * 0.3;
  const rot = rnd() * Math.PI;
  const lobes = 2 + Math.floor(rnd() * 2);
  const lobePhase = rnd() * Math.PI * 2;
  for (let i = 0; i < points; i++) {
    const base = (i / points) * Math.PI * 2;
    const a = base + (rnd() - 0.5) * (Math.PI / points) * 0.9;
    const lobe = 1 + 0.16 * Math.sin(a * lobes + lobePhase);
    const jitter = 0.82 + rnd() * 0.3;
    const r = radius * lobe * jitter;
    const x = Math.cos(a) * r;
    const y = Math.sin(a) * r * squash;
    pts.push(new THREE.Vector2(
      x * Math.cos(rot) - y * Math.sin(rot),
      x * Math.sin(rot) + y * Math.cos(rot),
    ));
  }
  const shape = new THREE.Shape();
  shape.moveTo(pts[0].x, pts[0].y);
  shape.splineThru([...pts.slice(1), pts[0]]);
  return shape;
}

/** 平面的墨漬網格（濺墨、陰影用）：躺在 XZ 平面上。 */
export function inkBlotMesh(radius: number, seed: number, color = INK, opacity = 0.8): THREE.Mesh {
  const geom = new THREE.ShapeGeometry(blobShape(radius, seed, 12));
  geom.rotateX(-Math.PI / 2);
  const mat = new THREE.MeshBasicMaterial({ color, transparent: true, opacity, depthWrite: false });
  return new THREE.Mesh(geom, mat);
}

// ---------------------------------------------------------------------------
// 清理
// ---------------------------------------------------------------------------

/** 遞迴釋放物件下所有幾何與材質（不釋放共用的快取貼圖）。 */
export function disposeObject(root: THREE.Object3D): void {
  root.traverse((o) => {
    const anyO = o as THREE.Mesh;
    if (anyO.geometry) anyO.geometry.dispose();
    const m = anyO.material as THREE.Material | THREE.Material[] | undefined;
    if (Array.isArray(m)) m.forEach((mm) => mm.dispose());
    else if (m) m.dispose();
  });
}

/** 緩動函式 */
export const ease = {
  linear: (t: number) => t,
  inOut: (t: number) => (t < 0.5 ? 2 * t * t : -1 + (4 - 2 * t) * t),
  out: (t: number) => 1 - (1 - t) * (1 - t),
  in: (t: number) => t * t,
  outBack: (t: number) => {
    const c = 1.70158;
    return 1 + (c + 1) * Math.pow(t - 1, 3) + c * Math.pow(t - 1, 2);
  },
};

/** 極簡時間補間器：每幀由場景呼叫 `update(now)`。 */
export class Tweener {
  private items: { start: number; dur: number; fn: (t: number) => void; e: (t: number) => number; done: () => void }[] = [];
  private now = 0;

  update(now: number): void {
    this.now = now;
    for (let i = this.items.length - 1; i >= 0; i--) {
      const it = this.items[i];
      const raw = Math.min(1, (now - it.start) / it.dur);
      it.fn(it.e(raw));
      if (raw >= 1) {
        this.items.splice(i, 1);
        it.done();
      }
    }
  }

  /** 在 `dur` 毫秒內以 `fn(t)`（t 已緩動）逐幀更新；完成時 resolve。 */
  run(dur: number, fn: (t: number) => void, e: (t: number) => number = ease.inOut): Promise<void> {
    return new Promise((resolve) => {
      this.items.push({ start: this.now, dur: Math.max(1, dur), fn, e, done: resolve });
    });
  }

  wait(ms: number): Promise<void> {
    return this.run(ms, () => {}, ease.linear);
  }

  clear(): void {
    const items = this.items;
    this.items = [];
    items.forEach((it) => it.done());
  }
}
