// 產生 src/data/geo.ts：把 47 都道府縣的多邊形合併成遊戲的 19 區，並算出共用邊界（arc）
// 用法：npx tsx tools/geo/build-geo.ts [簡化強度]
// 來源：tools/geo/japan.topojson（dataofjapan/land；原始資料為國土地理院「地球地図日本」）
//   https://raw.githubusercontent.com/dataofjapan/land/master/japan.topojson
import { readFileSync, writeFileSync } from 'node:fs';
import * as tc from 'topojson-client';
import * as ts from 'topojson-server';
import * as tsimp from 'topojson-simplify';
import type { Topology, GeometryCollection } from 'topojson-specification';
import type { Feature, MultiPolygon, Polygon, Position } from 'geojson';

type RegionId =
  | 'satsuma' | 'bungo' | 'hizen' | 'suo' | 'izumo' | 'tosa' | 'awa' | 'kinai' | 'yamato'
  | 'omi' | 'echizen' | 'mino' | 'ise' | 'owari' | 'mikawa' | 'kai' | 'echigo' | 'sagami' | 'oshu';

// 都道府縣 JIS 代碼 → 區域（愛知另行以經度切成尾張 / 三河；北海道、沖繩不納入）
const PREF_TO_REGION: Record<number, RegionId | null> = {
  1: null,
  2: 'oshu', 3: 'oshu', 4: 'oshu', 5: 'oshu', 6: 'oshu', 7: 'oshu',
  8: 'sagami', 9: 'sagami', 10: 'sagami', 11: 'sagami', 12: 'sagami', 13: 'sagami', 14: 'sagami',
  15: 'echigo',
  16: 'echizen', 17: 'echizen', 18: 'echizen',
  19: 'kai', 20: 'kai',
  21: 'mino',
  22: 'mikawa',
  23: 'owari', // 之後再切
  24: 'ise',
  25: 'omi',
  26: 'kinai', 27: 'kinai', 28: 'kinai',
  29: 'yamato', 30: 'yamato',
  31: 'izumo', 32: 'izumo', 33: 'izumo',
  34: 'suo', 35: 'suo',
  36: 'awa', 37: 'awa',
  38: 'tosa', 39: 'tosa',
  40: 'hizen', 41: 'hizen', 42: 'hizen', 43: 'hizen',
  44: 'bungo', 45: 'bungo',
  46: 'satsuma',
  47: null,
};
const AICHI_SPLIT_LON = 137.0; // 境川附近：以西尾張、以東三河

// 主城經緯度（lat, lon）。美濃 / 尾張略為錯開以免家紋重疊。
const CASTLES: Record<RegionId, [number, number]> = {
  satsuma: [31.60, 130.56], bungo: [33.24, 131.61], hizen: [33.25, 130.30], suo: [34.66, 132.69],
  izumo: [35.37, 133.19], tosa: [33.58, 133.63], awa: [34.12, 134.49], kinai: [35.01, 135.75],
  yamato: [34.60, 135.78], omi: [35.45, 136.27], echizen: [36.00, 136.30], mino: [35.65, 136.85],
  ise: [34.56, 136.48], owari: [35.15, 136.80], mikawa: [34.98, 138.38], kai: [35.68, 138.58],
  echigo: [37.15, 138.22], sagami: [35.25, 139.15], oshu: [37.92, 140.12],
};

// 投影：等距圓柱 + 旋轉，讓列島大致橫躺
const LAT0 = 35.5, LON0 = 135.5, SCALE = 9.0, ROT = -35 * Math.PI / 180;
const K = Math.cos(LAT0 * Math.PI / 180);
function project([lon, lat]: Position): [number, number] {
  const x0 = (lon - LON0) * K * SCALE, y0 = (lat - LAT0) * SCALE;
  const x = x0 * Math.cos(ROT) - y0 * Math.sin(ROT);
  const y = x0 * Math.sin(ROT) + y0 * Math.cos(ROT);
  return [+x.toFixed(2), +y.toFixed(2)];
}

// ---------------------------------------------------------------------------
const raw = JSON.parse(readFileSync(new URL('./japan.topojson', import.meta.url), 'utf8')) as Topology;
const MIN_WEIGHT = Number(process.argv[2] ?? 1e-6); // 簡化強度（球面三角面積）
let topo = tsimp.presimplify(raw as never, tsimp.sphericalTriangleArea);
topo = tsimp.simplify(topo, MIN_WEIGHT);
const japan = topo.objects.japan as GeometryCollection;
const fc = tc.feature(topo as never, japan as never) as unknown as { features: Feature<Polygon | MultiPolygon, { id: number; nam_ja: string }>[] };

function ringArea(r: Position[]): number {
  let a = 0;
  for (let i = 0, n = r.length; i < n; i++) { const [x1, y1] = r[i], [x2, y2] = r[(i + 1) % n]; a += x1 * y2 - x2 * y1; }
  return Math.abs(a) / 2;
}
const MIN_ISLAND = 0.012; // 平方度，約 120 km²：濾掉小島
const MIN_LAT = 30.9;     // 奄美、屋久、種子島等南方離島不納入

/** Sutherland–Hodgman：保留 keepWest ? lon<=split : lon>=split 的部分 */
function clipLon(ring: Position[], split: number, keepWest: boolean): Position[] {
  const inside = (p: Position) => keepWest ? p[0] <= split : p[0] >= split;
  const inter = (a: Position, b: Position): Position => {
    const t = (split - a[0]) / (b[0] - a[0]);
    return [split, +(a[1] + (b[1] - a[1]) * t).toFixed(6)];
  };
  const out: Position[] = [];
  for (let i = 0; i < ring.length; i++) {
    const cur = ring[i], prev = ring[(i + ring.length - 1) % ring.length];
    if (inside(cur)) { if (!inside(prev)) out.push(inter(prev, cur)); out.push(cur); }
    else if (inside(prev)) out.push(inter(prev, cur));
  }
  return out;
}

// 每個都道府縣片段 → 一個 feature（帶 region 標籤），之後用拓撲合併成區
const pieces: Feature<Polygon, { region: string }>[] = [];
function addPoly(region: string, ring: Position[]) {
  if (ring.length < 4 || ringArea(ring) < MIN_ISLAND) return;
  if (ring.reduce((s, p) => s + p[1], 0) / ring.length < MIN_LAT) return;
  pieces.push({ type: 'Feature', properties: { region }, geometry: { type: 'Polygon', coordinates: [ring] } });
}

for (const f of fc.features) {
  const target = PREF_TO_REGION[f.properties.id];
  if (target === null || target === undefined) continue;
  const polys: Position[][][] = f.geometry.type === 'Polygon' ? [f.geometry.coordinates] : f.geometry.coordinates;
  for (const poly of polys) {
    const outer = poly[0];
    if (f.properties.id === 23) {
      addPoly('owari', clipLon(outer, AICHI_SPLIT_LON, true));
      addPoly('mikawa', clipLon(outer, AICHI_SPLIT_LON, false));
      continue;
    }
    addPoly(target, outer);
  }
}

// 以 topojson-server 建拓撲：相鄰片段共用 arc → 可判斷哪些是區內界線、區界、海岸
const topo2 = ts.topology({ pieces: { type: 'FeatureCollection', features: pieces } }, 1e5);
const piecesObj = topo2.objects.pieces as GeometryCollection<{ region: string }>;
const decode = tc.transform(topo2.transform!);

// arc → 使用它的區域（含重複，用來判斷同區內界線）
const arcOwners = new Map<number, string[]>();
for (const g of piecesObj.geometries) {
  const id = g.properties!.region;
  const walk = (arcs: unknown): void => {
    if (typeof arcs === 'number') { const i = arcs < 0 ? ~arcs : arcs; if (!arcOwners.has(i)) arcOwners.set(i, []); arcOwners.get(i)!.push(id); return; }
    for (const a of arcs as unknown[]) walk(a);
  };
  walk((g as unknown as { arcs: unknown }).arcs);
}
function dedupPts(pts: [number, number][]): [number, number][] {
  const out: [number, number][] = [];
  for (const p of pts) { const l = out[out.length - 1]; if (!l || l[0] !== p[0] || l[1] !== p[1]) out.push(p); }
  return out;
}
const arcsOut: { a: string; b: string | null; pts: [number, number][] }[] = [];
let arcPts = 0, internalArcs = 0;
topo2.arcs.forEach((arc, i) => {
  const uses = arcOwners.get(i) ?? [];
  if (!uses.length) return;
  const owners = [...new Set(uses)];
  if (owners.length === 1 && uses.length > 1) { internalArcs++; return; } // 同區內的都道府縣界：不畫
  const pts = dedupPts(arc.map((p, j) => project(decode(p as [number, number], j) as Position)));
  if (pts.length < 2) return;
  arcPts += pts.length;
  arcsOut.push({ a: owners[0], b: owners[1] ?? null, pts });
});

// 各區多邊形：用 merge 把同區的片段合併（去掉內部界線），再投影
function polyCentroid(ring: [number, number][]): [number, number] {
  let a = 0, cx = 0, cy = 0;
  for (let i = 0, n = ring.length; i < n; i++) {
    const [x1, y1] = ring[i], [x2, y2] = ring[(i + 1) % n];
    const c = x1 * y2 - x2 * y1; a += c; cx += (x1 + x2) * c; cy += (y1 + y2) * c;
  }
  a /= 2; return [+(cx / (6 * a)).toFixed(2), +(cy / (6 * a)).toFixed(2)];
}
const regionsOut: Record<string, { polys: [number, number][][]; center: [number, number]; castle: [number, number]; radius: number }> = {};
let polyPts = 0;
const regionIds = [...new Set(piecesObj.geometries.map(g => g.properties!.region))] as RegionId[];
for (const id of regionIds) {
  const merged = tc.merge(topo2 as never, piecesObj.geometries.filter(g => g.properties!.region === id) as never) as MultiPolygon;
  const rings: [number, number][][] = merged.coordinates.map(p => {
    const pts = dedupPts(p[0].map(project));
    if (pts.length > 1 && pts[0][0] === pts[pts.length - 1][0] && pts[0][1] === pts[pts.length - 1][1]) pts.pop();
    return pts;
  }).filter(r => r.length >= 3);
  rings.sort((r1, r2) => ringArea(r2) - ringArea(r1));
  polyPts += rings.reduce((s, r) => s + r.length, 0);
  const center = polyCentroid(rings[0]);
  const area = rings.reduce((s, r) => s + ringArea(r), 0);
  regionsOut[id] = { polys: rings, center, castle: project([CASTLES[id][1], CASTLES[id][0]]), radius: +Math.sqrt(area / Math.PI).toFixed(2) };
}

// 邊界框
let minX = 1e9, minY = 1e9, maxX = -1e9, maxY = -1e9;
for (const r of Object.values(regionsOut)) for (const ring of r.polys) for (const [x, y] of ring) { minX = Math.min(minX, x); maxX = Math.max(maxX, x); minY = Math.min(minY, y); maxY = Math.max(maxY, y); }

const order: RegionId[] = ['satsuma', 'bungo', 'hizen', 'suo', 'izumo', 'tosa', 'awa', 'kinai', 'yamato', 'omi', 'echizen', 'mino', 'ise', 'owari', 'mikawa', 'kai', 'echigo', 'sagami', 'oshu'];
const missing = order.filter(id => !regionsOut[id]);
if (missing.length) throw new Error(`缺少區域：${missing.join(',')}`);

const fmtPts = (pts: [number, number][]) => '[' + pts.map(p => `[${p[0]},${p[1]}]`).join(',') + ']';
let out = `// 自動產生：npx tsx tools/geo/build-geo.ts（請勿手動編輯）
// 地理資料來源：國土地理院「地球地図日本」（經 dataofjapan/land 轉換），已合併為 19 區並簡化。
// 座標為遊戲平面座標（x 向右、y 向上），由經緯度投影並旋轉 ${-ROT * 180 / Math.PI}° 而得。
import type { RegionId } from '../core/types';

export interface GeoRegion {
  /** 多邊形（只含外環；第一個為最大的本體） */
  polys: [number, number][][];
  /** 最大多邊形的形心 */
  center: [number, number];
  /** 主城位置 */
  castle: [number, number];
  /** 面積等效半徑 */
  radius: number;
}

/** 區與區之間（或海岸）的邊界線段；b 為 null 表示海岸線 */
export interface GeoArc { a: RegionId; b: RegionId | null; pts: [number, number][] }

export const GEO_BOUNDS = { minX: ${minX}, minY: ${minY}, maxX: ${maxX}, maxY: ${maxY} };

export const GEO_REGIONS: Record<RegionId, GeoRegion> = {
`;
for (const id of order) {
  const r = regionsOut[id];
  out += `  ${id}: { center: [${r.center}], castle: [${r.castle}], radius: ${r.radius}, polys: [\n`;
  for (const ring of r.polys) out += `    ${fmtPts(ring)},\n`;
  out += `  ] },\n`;
}
out += `};\n\nexport const GEO_ARCS: GeoArc[] = [\n`;
for (const a of arcsOut) out += `  { a: '${a.a}', b: ${a.b ? `'${a.b}'` : 'null'}, pts: ${fmtPts(a.pts)} },\n`;
out += `];\n`;

writeFileSync(new URL('../../src/data/geo.ts', import.meta.url), out);
console.log(`regions=${order.length} polys=${Object.values(regionsOut).reduce((s, r) => s + r.polys.length, 0)} polyPts=${polyPts} arcs=${arcsOut.length} arcPts=${arcPts} internalArcs=${internalArcs} bytes=${Buffer.byteLength(out)}`);
console.log(`bounds x ${minX}..${maxX} (${(maxX - minX).toFixed(1)})  y ${minY}..${maxY} (${(maxY - minY).toFixed(1)})`);
for (const id of order) console.log(`  ${id.padEnd(8)} polys=${regionsOut[id].polys.length} center=${regionsOut[id].center} castle=${regionsOut[id].castle} r=${regionsOut[id].radius}`);
const sea = arcsOut.filter(a => !a.b).length;
console.log(`coast arcs=${sea} border arcs=${arcsOut.length - sea}`);
const pairs = new Set(arcsOut.filter(a => a.b).map(a => [a.a, a.b].sort().join('-')));
console.log('land borders:', [...pairs].sort().join(' '));
