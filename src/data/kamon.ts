/**
 * Procedural Japanese family crests (家紋) rendered as SVG strings.
 *
 * Every crest is drawn inside a 100x100 viewBox, monochrome, on a transparent
 * background. Filled shapes inherit `fill` from the root <svg>; stroked shapes
 * use `currentColor`, which the root sets via its `color` attribute.
 */

export type KamonId =
  | 'oda_mokko'
  | 'ashikaga_futatsubiki'
  | 'takeda_bishi'
  | 'uesugi_take_ni_suzume'
  | 'hojo_mitsuuroko'
  | 'mori_ichimonji_mitsuboshi'
  | 'miyoshi_sangaibishi'
  | 'chosokabe_katabami'
  | 'shimazu_juji'
  | 'otomo_gyoyo'
  | 'ryuzoji_hiashi'
  | 'amago_yotsumeyui'
  | 'tsutsui_umebachi'
  | 'azai_kikko'
  | 'asakura_mokko'
  | 'saito_tatsunami'
  | 'kitabatake_waribishi'
  | 'date_mitsubiki';

export const KAMON_IDS: KamonId[] = [
  'oda_mokko',
  'ashikaga_futatsubiki',
  'takeda_bishi',
  'uesugi_take_ni_suzume',
  'hojo_mitsuuroko',
  'mori_ichimonji_mitsuboshi',
  'miyoshi_sangaibishi',
  'chosokabe_katabami',
  'shimazu_juji',
  'otomo_gyoyo',
  'ryuzoji_hiashi',
  'amago_yotsumeyui',
  'tsutsui_umebachi',
  'azai_kikko',
  'asakura_mokko',
  'saito_tatsunami',
  'kitabatake_waribishi',
  'date_mitsubiki',
];

// ---------------------------------------------------------------------------
// Geometry helpers
// ---------------------------------------------------------------------------

/** Centre of the 100x100 viewBox. */
const C = 50;
/** Radius of the outer ring used by 丸に〜 crests (leaves a 6px margin). */
const RING_R = 44;
const RING_W = 4;

type Pt = [number, number];

const f = (n: number): string => String(Math.round(n * 100) / 100);
const pt = (p: Pt): string => `${f(p[0])},${f(p[1])}`;

function polar(r: number, deg: number, cx = C, cy = C): Pt {
  const a = (deg * Math.PI) / 180;
  return [cx + r * Math.cos(a), cy + r * Math.sin(a)];
}

/** Path data for a full circle (usable as a sub-path for even-odd holes). */
function circleD(cx: number, cy: number, r: number): string {
  return `M${pt([cx - r, cy])}a${f(r)},${f(r)} 0 1,0 ${f(2 * r)},0a${f(r)},${f(r)} 0 1,0 ${f(-2 * r)},0Z`;
}

function path(d: string, attrs = ''): string {
  return `<path d="${d}"${attrs}/>`;
}

function evenodd(d: string): string {
  return path(d, ' fill-rule="evenodd"');
}

function circle(cx: number, cy: number, r: number): string {
  return `<circle cx="${f(cx)}" cy="${f(cy)}" r="${f(r)}"/>`;
}

/** Hollow circle: `r` is the outer radius, `w` the band width. */
function ring(r: number, w: number, cx = C, cy = C): string {
  return `<circle cx="${f(cx)}" cy="${f(cy)}" r="${f(r - w / 2)}" fill="none" stroke="currentColor" stroke-width="${f(w)}"/>`;
}

function stroke(d: string, w: number): string {
  return `<path d="${d}" fill="none" stroke="currentColor" stroke-width="${f(w)}" stroke-linecap="round" stroke-linejoin="round"/>`;
}

function polygon(pts: Pt[]): string {
  return `<polygon points="${pts.map(pt).join(' ')}"/>`;
}

function polygonD(pts: Pt[]): string {
  return `M${pts.map(pt).join('L')}Z`;
}

function rect(x: number, y: number, w: number, h: number): string {
  return `<rect x="${f(x)}" y="${f(y)}" width="${f(w)}" height="${f(h)}"/>`;
}

/** Rhombus with horizontal half-width `hw` and vertical half-height `hh`. */
function rhombus(cx: number, cy: number, hw: number, hh: number): string {
  return polygon([
    [cx, cy - hh],
    [cx + hw, cy],
    [cx, cy + hh],
    [cx - hw, cy],
  ]);
}

/** Upward-pointing equilateral triangle with apex at (cx, apexY). */
function triangle(cx: number, apexY: number, side: number): string {
  const h = (side * Math.sqrt(3)) / 2;
  return polygon([
    [cx, apexY],
    [cx + side / 2, apexY + h],
    [cx - side / 2, apexY + h],
  ]);
}

/** Pointy-top regular hexagon outline points. */
function hexPts(cx: number, cy: number, r: number): Pt[] {
  return [0, 1, 2, 3, 4, 5].map((i) => polar(r, -90 + i * 60, cx, cy));
}

/** Repeat `inner` n times, rotated evenly around (cx, cy). */
function repeat(n: number, inner: string, cx = C, cy = C, offset = 0): string {
  let s = '';
  for (let i = 0; i < n; i++) {
    const a = offset + (360 * i) / n;
    s += a === 0 ? inner : `<g transform="rotate(${f(a)} ${f(cx)} ${f(cy)})">${inner}</g>`;
  }
  return s;
}

function translate(x: number, y: number, inner: string): string {
  return `<g transform="translate(${f(x)} ${f(y)})">${inner}</g>`;
}

/**
 * Horizontal bar between y1 and y2 whose ends are clipped to a circle of
 * radius R (used for 引両 crests so the bars merge into the ring).
 */
function chordBar(y1: number, y2: number, R: number, cx = C, cy = C): string {
  const hw = (y: number) => Math.sqrt(Math.max(0, R * R - (y - cy) ** 2));
  const a = hw(y1);
  const b = hw(y2);
  const arc = `A${f(R)},${f(R)} 0 0,1 `;
  return path(
    `M${pt([cx - a, y1])}L${pt([cx + a, y1])}${arc}${pt([cx + b, y2])}` +
      `L${pt([cx - b, y2])}${arc}${pt([cx - a, y1])}Z`,
  );
}

/** Ring with `n` evenly spaced horizontal bars (引両). */
function hikiryo(n: number, barH: number, gap: number): string {
  const R = RING_R - RING_W + 1; // overlap slightly into the band
  const total = n * barH + (n - 1) * gap;
  let s = ring(RING_R, RING_W);
  for (let i = 0; i < n; i++) {
    const y1 = C - total / 2 + i * (barH + gap);
    s += chordBar(y1, y1 + barH, R);
  }
  return s;
}

// ---------------------------------------------------------------------------
// Reusable motifs
// ---------------------------------------------------------------------------

/**
 * Outline of a 木瓜 (mokko) lobe ring: four overlapping circles of radius `r`
 * whose centres sit `d` from the middle, traced as a single closed path.
 */
function mokkoOutline(cx: number, cy: number, d: number, r: number): string {
  // Distance from centre to the cusp where adjacent lobes meet (on the diagonal).
  const rho = d * Math.SQRT1_2 + Math.sqrt(r * r - (d * d) / 2);
  const cusps = [45, 135, 225, 315].map((a) => polar(rho, a, cx, cy));
  let s = `M${pt(cusps[0])}`;
  for (let i = 1; i <= 4; i++) {
    s += `A${f(r)},${f(r)} 0 0,1 ${pt(cusps[i % 4])}`;
  }
  return s + 'Z';
}

/** Complete 木瓜 crest at scale `s` (s = 1 fills the whole viewBox). */
function mokko(cx: number, cy: number, s: number): string {
  const band = evenodd(mokkoOutline(cx, cy, 20 * s, 24 * s) + mokkoOutline(cx, cy, 15.5 * s, 18.5 * s));
  const petal = path(
    `M${pt([cx, cy - 6 * s])}Q${pt([cx - 16 * s, cy - 18 * s])} ${pt([cx, cy - 31 * s])}` +
      `Q${pt([cx + 16 * s, cy - 18 * s])} ${pt([cx, cy - 6 * s])}Z`,
  );
  return band + repeat(4, petal, cx, cy) + circle(cx, cy, 4 * s);
}

/** Four rhombi forming a larger rhombus; `shrink` < 1 opens gaps between them. */
function fourBishi(W: number, H: number, shrink: number): string {
  // Each sub-rhombus is half the parent's size and centred on the parent's half-diagonals.
  const hw = (W / 4) * shrink;
  const hh = (H / 4) * shrink;
  return (
    rhombus(C - W / 4, C, hw, hh) +
    rhombus(C + W / 4, C, hw, hh) +
    rhombus(C, C - H / 4, hw, hh) +
    rhombus(C, C + H / 4, hw, hh)
  );
}

/** Hexagon band (亀甲) with a 花菱 flower inside. */
function kikko(cx: number, cy: number, R: number): string {
  const band = evenodd(polygonD(hexPts(cx, cy, R)) + polygonD(hexPts(cx, cy, R * 0.8)));
  const k = R / 21;
  const petal = polygon([
    [cx, cy - 2.2 * k],
    [cx + 2 * k, cy - 5.6 * k],
    [cx, cy - 9.2 * k],
    [cx - 2 * k, cy - 5.6 * k],
  ]);
  return band + repeat(4, petal, cx, cy) + circle(cx, cy, 1.5 * k);
}

/** Heart-shaped 片喰 leaf pointing towards (cx, cy) from above. */
function katabamiLeaf(cx: number, cy: number, L: number): string {
  const k = L / 22;
  const P = (x: number, y: number): string => pt([cx + x * k, cy + y * k]);
  return path(
    `M${P(0, -3)}` +
      `C${P(-10, -7)} ${P(-14, -16)} ${P(-9.5, -20)}` +
      `C${P(-6, -23)} ${P(-1.5, -22)} ${P(0, -18)}` +
      `C${P(1.5, -22)} ${P(6, -23)} ${P(9.5, -20)}` +
      `C${P(14, -16)} ${P(10, -7)} ${P(0, -3)}Z`,
  );
}

/** Scalloped teardrop outline for the 杏葉 crest, scaled by `s` about the centre. */
function gyoyoOutline(s: number): string {
  // Right-hand profile from the top down to the bottom tip.
  const right: Pt[] = [
    [50, 14],
    [63, 19],
    [71, 33],
    [70.5, 50],
    [64, 68],
    [50, 86],
  ].map(([x, y]) => [C + (x - C) * s, C + (y - C) * s] as Pt);
  const left = right.map(([x, y]) => [2 * C - x, y] as Pt).reverse();
  const seg = (a: Pt, b: Pt): string => {
    const r = (Math.hypot(b[0] - a[0], b[1] - a[1]) / 2) * 1.15;
    return `A${f(r)},${f(r)} 0 0,1 ${pt(b)}`;
  };
  let d = `M${pt(right[0])}`;
  for (let i = 1; i < right.length; i++) d += seg(right[i - 1], right[i]);
  for (let i = 1; i < left.length; i++) d += seg(left[i - 1], left[i]);
  return d + 'Z';
}

/** One stylised 立波 wave crest in local coordinates (about 44 wide, 76 tall). */
function wave(): string {
  const outer =
    'M3,76C0,50 6,24 22,12C36,2 48,16 38,28C32,35 22,31 25,22';
  const mid = 'M13,76C12,54 18,36 30,27';
  const inner = 'M23,76C23,60 27,48 34,40';
  const base = 'M0,76Q22,70 44,76';
  return stroke(outer, 4.5) + stroke(mid, 4) + stroke(inner, 3.5) + stroke(base, 3);
}

/** Simple stylised sparrow for 竹に雀, centred roughly on (cx, cy), facing left. */
function sparrow(cx: number, cy: number): string {
  const body =
    circleD(cx + 2, cy + 2, 10) +
    // wing line (hole)
    `M${pt([cx - 3, cy + 1])}Q${pt([cx + 6, cy - 5])} ${pt([cx + 13, cy + 1])}` +
    `Q${pt([cx + 6, cy - 2.5])} ${pt([cx - 3, cy + 1])}Z`;
  const head = circleD(cx - 7, cy - 6, 6) + circleD(cx - 8.5, cy - 7.5, 1.3);
  const beak = polygon([
    [cx - 12, cy - 7],
    [cx - 18, cy - 5],
    [cx - 12, cy - 3.5],
  ]);
  const tail = polygon([
    [cx + 10, cy + 1],
    [cx + 22, cy - 3],
    [cx + 22, cy + 7],
    [cx + 10, cy + 6],
  ]);
  const legs = stroke(
    `M${pt([cx - 1, cy + 12])}L${pt([cx - 3, cy + 17])}M${pt([cx + 5, cy + 12])}L${pt([cx + 4, cy + 17])}`,
    1.6,
  );
  return evenodd(body + head) + beak + tail + legs;
}

// ---------------------------------------------------------------------------
// Crest definitions
// ---------------------------------------------------------------------------

const CRESTS: Record<KamonId, () => string> = {
  // 織田木瓜: lobed band enclosing a four-petal flower.
  oda_mokko: () => mokko(C, C, 1),

  // 足利二つ引両: circle with two thick horizontal bars.
  ashikaga_futatsubiki: () => hikiryo(2, 13, 11),

  // 武田菱: four flattened rhombi with clear gaps.
  takeda_bishi: () => fourBishi(88, 58, 0.86),

  // 竹に雀: bamboo-leaf wreath around a sparrow.
  uesugi_take_ni_suzume: () => {
    const leaf = (deg: number): string => {
      const [x, y] = polar(37, deg);
      return `<g transform="translate(${f(x)} ${f(y)}) rotate(${f(deg + 90)})">` +
        `<path d="M-10,0Q0,-4.8 10,0Q0,4.8 -10,0Z"/></g>`;
    };
    let wreath = ring(41, 1.6);
    for (let i = 0; i < 10; i++) {
      const a = i * 36;
      const [px, py] = polar(37, a);
      // Each cluster: a pair of leaves fanned +/- 28 degrees off the tangent.
      wreath += `<g transform="rotate(-28 ${f(px)} ${f(py)})">${leaf(a)}</g>`;
      wreath += `<g transform="rotate(28 ${f(px)} ${f(py)})">${leaf(a)}</g>`;
    }
    return wreath + sparrow(50, 50);
  },

  // 三つ鱗: three solid triangles.
  hojo_mitsuuroko: () => {
    const side = 42;
    const h = (side * Math.sqrt(3)) / 2;
    const top = C - h;
    return triangle(C, top, side) + triangle(C - side / 2, top + h, side) + triangle(C + side / 2, top + h, side);
  },

  // 一文字三星: bar above three stars.
  mori_ichimonji_mitsuboshi: () =>
    rect(10, 11, 80, 13) + circle(50, 45, 13) + circle(35.5, 70, 13) + circle(64.5, 70, 13),

  // 三階菱: three stacked rhombi, narrow-wide-narrow.
  miyoshi_sangaibishi: () => {
    const g = 0.93; // shrink factor to open thin gaps
    return (
      rhombus(C, 23, 21 * g, 13 * g) +
      rhombus(C, 50, 34 * g, 14 * g) +
      rhombus(C, 77, 21 * g, 13 * g)
    );
  },

  // 七つ片喰 (approx.): central katabami ringed by six dots.
  chosokabe_katabami: () => {
    const leaves = repeat(3, katabamiLeaf(C, C, 23));
    const stamen = repeat(3, rect(C - 0.8, C - 17, 1.6, 12), C, C, 60);
    let dots = '';
    for (let i = 0; i < 6; i++) {
      const [x, y] = polar(37, -90 + i * 60);
      dots += circle(x, y, 6.5);
    }
    return leaves + stamen + dots;
  },

  // 丸に十字: ring with a bold cross.
  shimazu_juji: () => {
    const R = RING_R - RING_W + 1;
    const bar = chordBar(C - 5.5, C + 5.5, R);
    return ring(RING_R, RING_W) + bar + `<g transform="rotate(90 ${C} ${C})">${bar}</g>`;
  },

  // 杏葉: scalloped teardrop band with veins and a top knob.
  otomo_gyoyo: () => {
    const band = evenodd(gyoyoOutline(1) + gyoyoOutline(0.82));
    const midrib = rect(C - 1.2, 26, 2.4, 50);
    let veins = '';
    for (let i = 0; i < 4; i++) {
      const y = 33 + i * 11;
      const len = [13, 14, 12, 8][i];
      veins += stroke(`M${pt([C, y])}L${pt([C - len, y + 7])}M${pt([C, y])}L${pt([C + len, y + 7])}`, 2);
    }
    const knob = ring(5, 2.4, C, 11) + circle(C, 11, 1.6);
    return band + midrib + veins + knob;
  },

  // 日足: sun with twelve tapered rays.
  ryuzoji_hiashi: () => {
    const ray = polygon([
      [C - 4.6, C - 14],
      [C + 4.6, C - 14],
      [C, C - 44],
    ]);
    return circle(C, C, 15) + repeat(12, ray);
  },

  // 平四つ目結: 2x2 grid of hollow squares.
  amago_yotsumeyui: () => {
    const side = 38;
    const hole = 17;
    const sq = (x: number, y: number): string =>
      polygonD([[x, y], [x + side, y], [x + side, y + side], [x, y + side]]) +
      polygonD([
        [x + (side - hole) / 2, y + (side - hole) / 2],
        [x + (side + hole) / 2, y + (side - hole) / 2],
        [x + (side + hole) / 2, y + (side + hole) / 2],
        [x + (side - hole) / 2, y + (side + hole) / 2],
      ]);
    const o = 10;
    const p = 100 - o - side;
    return evenodd(sq(o, o) + sq(p, o) + sq(o, p) + sq(p, p));
  },

  // 梅鉢: five petal discs joined to the centre by short bars.
  tsutsui_umebachi: () => {
    const petal = circle(C, C - 30, 13);
    const bar = polygon([
      [C - 3, C - 8],
      [C + 3, C - 8],
      [C + 4, C - 20],
      [C - 4, C - 20],
    ]);
    return circle(C, C, 11) + repeat(5, petal + bar);
  },

  // 三つ盛亀甲に花菱: three hexagons, each holding a flower.
  azai_kikko: () => {
    const R = 21;
    const dx = (R * Math.sqrt(3)) / 2;
    const dy = R * 1.5;
    return kikko(C, 34, R) + kikko(C - dx, 34 + dy, R) + kikko(C + dx, 34 + dy, R);
  },

  // 三つ盛木瓜: three small mokko in a triangle.
  asakura_mokko: () => {
    const s = 0.47;
    return mokko(C, 27.5, s) + mokko(30, 63.5, s) + mokko(70, 63.5, s);
  },

  // 二頭立波: two curling waves side by side.
  saito_tatsunami: () => translate(6, 10, wave()) + translate(50, 10, wave()),

  // 割菱: a rhombus split by a thin cross gap.
  kitabatake_waribishi: () => fourBishi(80, 64, 0.94),

  // 三つ引両: circle with three horizontal bars.
  date_mitsubiki: () => hikiryo(3, 10, 7.5),
};

// ---------------------------------------------------------------------------
// Public API
// ---------------------------------------------------------------------------

/**
 * Returns a complete `<svg>` string (100x100 viewBox) for the crest, drawn in
 * `color` on a transparent background.
 */
export function kamonSvg(id: KamonId, color = '#1a1a1a'): string {
  const body = CRESTS[id]();
  return (
    `<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 100 100" width="100" height="100" ` +
    `fill="${color}" color="${color}">${body}</svg>`
  );
}

/** Returns a `data:` URL usable as an `<img src>` or as a three.js TextureLoader input. */
export function kamonDataUrl(id: KamonId, color = '#1a1a1a'): string {
  return 'data:image/svg+xml;charset=utf-8,' + encodeURIComponent(kamonSvg(id, color));
}
