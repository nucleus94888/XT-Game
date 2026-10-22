// ===== 戰略地圖（three.js，水墨風） =====
// 地形來自 data/geo.ts（真實日本輪廓合併成 19 區）。平面座標 (x, y) → world (x, 0, -y)。
// 區域依領主上色；同一勢力之間的邊界淡化、不同勢力之間的邊界加粗，海岸線以墨筆描出。

import * as THREE from 'three';
import { LineSegments2 } from 'three/examples/jsm/lines/LineSegments2.js';
import { LineSegmentsGeometry } from 'three/examples/jsm/lines/LineSegmentsGeometry.js';
import { LineMaterial } from 'three/examples/jsm/lines/LineMaterial.js';
import type { GameState, RegionId } from '../core/types';
import { REGIONS, REGION_MAP } from '../data/regions';
import { FACTION_MAP } from '../data/factions';
import { GEO_ARCS, GEO_BOUNDS, GEO_REGIONS } from '../data/geo';
import { t } from '../i18n';
import {
  INK, PAPER_CREAM, addOutline, disposeObject, ease, inkMaterial, kamonSprite,
  makePaperTexture, mixColor, mulberry32, mutedColor, setSpriteText, textSprite, Tweener,
} from './ink';

const NEUTRAL_COLOR = 0x9a948a;
const HIGHLIGHT_COLOR = 0xc0392b;
const SELECT_COLOR = 0xa8281c;
const SEA_TINT = 0xeaede8;      // 海面：把和紙微微染成青灰
const LAND_H = 0.5;             // 陸地厚度
const TOP_Y = LAND_H + 0.03;    // 邊界線所在高度
const TAP_THRESHOLD_PX = 8;
const ZOOM_MIN = 0.7;
const ZOOM_MAX = 4.5;
const CAMERA_PITCH = THREE.MathUtils.degToRad(60);
const CAMERA_DIST = 140;

type Pt = [number, number];

interface RegionNode {
  id: RegionId;
  group: THREE.Group;
  meshes: THREE.Mesh[];
  material: THREE.MeshToonMaterial;
  kamon: THREE.Sprite | null;
  kamonKey: string;
  label: THREE.Sprite;
  castle: THREE.Group;
  baseColor: number;
  highlighted: boolean;
}

function fmt(n: number): string {
  return n.toLocaleString('en-US');
}

function hexStr(c: number): string {
  return '#' + c.toString(16).padStart(6, '0');
}

/** 射線法：點是否在多邊形內 */
function pointInRing(x: number, y: number, ring: Pt[]): boolean {
  let inside = false;
  for (let i = 0, j = ring.length - 1; i < ring.length; j = i++) {
    const [xi, yi] = ring[i], [xj, yj] = ring[j];
    if ((yi > y) !== (yj > y) && x < ((xj - xi) * (y - yi)) / (yj - yi) + xi) inside = !inside;
  }
  return inside;
}

function pointOnLand(x: number, y: number): boolean {
  for (const g of Object.values(GEO_REGIONS)) for (const ring of g.polys) if (pointInRing(x, y, ring)) return true;
  return false;
}

/** 多邊形外環 → THREE.Shape（shape y 經 rotateX(-90°) 後對應 world -z） */
function ringShape(ring: Pt[]): THREE.Shape {
  const s = new THREE.Shape();
  s.moveTo(ring[0][0], ring[0][1]);
  for (let i = 1; i < ring.length; i++) s.lineTo(ring[i][0], ring[i][1]);
  s.closePath();
  return s;
}

/** 折線 → LineSegments2 用的 [x1,y1,z1,x2,y2,z2,...] */
function polylineSegments(pts: Pt[], y: number, out: number[]): void {
  for (let i = 0; i < pts.length - 1; i++) out.push(pts[i][0], y, -pts[i][1], pts[i + 1][0], y, -pts[i + 1][1]);
}

export class MapScene {
  /** UI 指定：點擊區域或空白處時呼叫 */
  onSelect: ((id: RegionId | null) => void) | null = null;

  private container: HTMLElement;
  private renderer: THREE.WebGLRenderer;
  private scene = new THREE.Scene();
  private camera: THREE.OrthographicCamera;
  private target = new THREE.Vector3();
  private forward = new THREE.Vector3();
  private bounds = new THREE.Box3();
  private baseView = { w: 100, h: 50 };
  private regions = new Map<RegionId, RegionNode>();
  private regionMeshes: THREE.Mesh[] = [];
  private armyGroup = new THREE.Group();
  private borderGroup = new THREE.Group();
  private selectGroup = new THREE.Group();
  private hintGroup = new THREE.Group();
  private hinted: RegionId | null = null;
  private lineMaterials: LineMaterial[] = [];
  private borderSignature = '';
  private selected: RegionId | null = null;
  private tween = new Tweener();
  private raycaster = new THREE.Raycaster();
  private plane = new THREE.Plane(new THREE.Vector3(0, 1, 0), 0);
  private resizeObs: ResizeObserver | null = null;
  private disposed = false;
  private resolution = new THREE.Vector2(1, 1);

  // 指標狀態
  private pointers = new Map<number, { x: number; y: number }>();
  private pressStart: { x: number; y: number } | null = null;
  private moved = false;
  private panAnchor = new THREE.Vector3();
  private pinchStart: { dist: number; zoom: number } | null = null;

  constructor(container: HTMLElement) {
    this.container = container;

    this.renderer = new THREE.WebGLRenderer({ antialias: true, alpha: false, powerPreference: 'high-performance' });
    this.renderer.setPixelRatio(Math.min(window.devicePixelRatio || 1, 2));
    this.renderer.outputColorSpace = THREE.SRGBColorSpace;
    this.renderer.setClearColor(mixColor(PAPER_CREAM, SEA_TINT, 0.7), 1);
    const canvas = this.renderer.domElement;
    canvas.style.display = 'block';
    canvas.style.width = '100%';
    canvas.style.height = '100%';
    canvas.style.touchAction = 'none';
    canvas.style.userSelect = 'none';
    (canvas.style as unknown as Record<string, string>).webkitUserSelect = 'none';
    container.appendChild(canvas);

    this.camera = new THREE.OrthographicCamera(-50, 50, 25, -25, 1, 500);
    this.forward.set(0, -Math.sin(CAMERA_PITCH), -Math.cos(CAMERA_PITCH)).normalize();

    this.buildLights();
    this.buildSea();
    this.buildRegions();
    this.buildCoast();
    this.buildSeaRoutes();
    this.scene.add(this.borderGroup, this.selectGroup, this.hintGroup, this.armyGroup);

    this.computeBounds();
    this.target.copy(this.bounds.getCenter(new THREE.Vector3()));
    this.target.y = 0;
    this.resize();

    this.bindInput();
    this.resizeObs = new ResizeObserver(() => this.resize());
    this.resizeObs.observe(container);
    window.addEventListener('resize', this.onWindowResize);

    this.renderer.setAnimationLoop(this.tick);
  }

  // -------------------------------------------------------------------------
  // 建構
  // -------------------------------------------------------------------------

  private buildLights(): void {
    const hemi = new THREE.HemisphereLight(0xfff6e3, 0x9c8a6c, 1.7);
    this.scene.add(hemi);
    const dir = new THREE.DirectionalLight(0xffffff, 1.3);
    dir.position.set(-30, 60, 20);
    this.scene.add(dir);
  }

  private buildSea(): void {
    const tex = makePaperTexture();
    tex.repeat.set(9, 9);
    const geom = new THREE.PlaneGeometry(520, 520);
    geom.rotateX(-Math.PI / 2);
    const mat = new THREE.MeshBasicMaterial({ map: tex, color: SEA_TINT });
    const paper = new THREE.Mesh(geom, mat);
    const cx = (GEO_BOUNDS.minX + GEO_BOUNDS.maxX) / 2, cy = (GEO_BOUNDS.minY + GEO_BOUNDS.maxY) / 2;
    paper.position.set(cx, -0.02, -cy);
    paper.name = 'sea';
    this.scene.add(paper);

    // 海波墨線：只畫在海上
    const rnd = mulberry32(7);
    const pts: number[] = [];
    let tries = 0;
    for (let i = 0; i < 160 && tries < 2000; tries++) {
      const x = GEO_BOUNDS.minX - 12 + rnd() * (GEO_BOUNDS.maxX - GEO_BOUNDS.minX + 24);
      const y = GEO_BOUNDS.minY - 10 + rnd() * (GEO_BOUNDS.maxY - GEO_BOUNDS.minY + 20);
      const len = 2 + rnd() * 3.5;
      if (pointOnLand(x, y) || pointOnLand(x + len, y)) continue;
      i++;
      const segs = 6;
      for (let s = 0; s < segs; s++) {
        const t0 = s / segs, t1 = (s + 1) / segs;
        pts.push(x + t0 * len, 0.01, -(y + Math.sin(t0 * Math.PI * 2) * 0.22));
        pts.push(x + t1 * len, 0.01, -(y + Math.sin(t1 * Math.PI * 2) * 0.22));
      }
    }
    const g = new THREE.BufferGeometry();
    g.setAttribute('position', new THREE.Float32BufferAttribute(pts, 3));
    const waves = new THREE.LineSegments(g, new THREE.LineBasicMaterial({ color: INK, transparent: true, opacity: 0.13 }));
    waves.name = 'waves';
    this.scene.add(waves);
  }

  private buildRegions(): void {
    REGIONS.forEach((def, idx) => {
      const geo = GEO_REGIONS[def.id];
      const group = new THREE.Group();
      group.name = `region:${def.id}`;
      const material = inkMaterial(mutedColor(NEUTRAL_COLOR));
      const meshes: THREE.Mesh[] = [];

      for (const ring of geo.polys) {
        if (ring.length < 3) continue;
        const shape = ringShape(ring);
        const geom = new THREE.ExtrudeGeometry(shape, { depth: LAND_H, bevelEnabled: false, curveSegments: 1 });
        geom.rotateX(-Math.PI / 2);
        geom.computeBoundingSphere();
        const mesh = new THREE.Mesh(geom, material);
        mesh.userData.regionId = def.id;
        group.add(mesh);
        meshes.push(mesh);
        this.regionMeshes.push(mesh);

        // 地面墨影（讓陸地像是浮在紙上）
        const shadowGeom = new THREE.ShapeGeometry(shape, 1);
        shadowGeom.rotateX(-Math.PI / 2);
        const shadow = new THREE.Mesh(shadowGeom, new THREE.MeshBasicMaterial({ color: INK, transparent: true, opacity: 0.14, depthWrite: false }));
        shadow.position.set(0.3, 0.0, 0.4);
        shadow.raycast = () => {};
        group.add(shadow);
      }

      if (def.terrain === 'mountain') this.addMountains(group, def.id, idx);
      const castle = this.addCastle(group, geo.castle);

      // 地名 + 兵力（城下方，一行）
      const label = textSprite(t(`region.short.${def.id}`), 1.15);
      label.position.set(geo.castle[0], TOP_Y + 0.35, -geo.castle[1] + 1.45);
      label.raycast = () => {};
      group.add(label);

      this.scene.add(group);
      this.regions.set(def.id, {
        id: def.id, group, meshes, material, kamon: null, kamonKey: '', label, castle,
        baseColor: material.color.getHex(), highlighted: false,
      });
    });
  }

  /** 山：在本體多邊形內均勻取樣幾個點（避開主城） */
  private addMountains(group: THREE.Group, id: RegionId, idx: number): void {
    const geo = GEO_REGIONS[id];
    const ring = geo.polys[0];
    const rnd = mulberry32(500 + idx);
    const n = Math.max(2, Math.min(6, Math.round(geo.radius * 0.7)));
    const mat = inkMaterial(0x8d877c);
    let placed = 0, tries = 0;
    let minX = 1e9, minY = 1e9, maxX = -1e9, maxY = -1e9;
    for (const [x, y] of ring) { minX = Math.min(minX, x); maxX = Math.max(maxX, x); minY = Math.min(minY, y); maxY = Math.max(maxY, y); }
    while (placed < n && tries < 200) {
      tries++;
      const x = minX + rnd() * (maxX - minX), y = minY + rnd() * (maxY - minY);
      if (!pointInRing(x, y, ring)) continue;
      if (Math.hypot(x - geo.castle[0], y - geo.castle[1]) < 1.6) continue;
      // 離海岸遠一點：四個方向都還在陸地內
      if (!pointInRing(x + 0.7, y, ring) || !pointInRing(x - 0.7, y, ring) || !pointInRing(x, y + 0.7, ring) || !pointInRing(x, y - 0.7, ring)) continue;
      const h = 1.0 + rnd() * 1.0;
      const geom = new THREE.ConeGeometry(0.7 + rnd() * 0.4, h, 5, 1);
      geom.translate(0, h / 2, 0);
      const m = new THREE.Mesh(geom, mat);
      m.position.set(x, LAND_H, -y);
      m.rotation.y = rnd() * Math.PI;
      m.raycast = () => {};
      addOutline(m, 0.05);
      group.add(m);
      placed++;
    }
  }

  private addCastle(group: THREE.Group, at: Pt): THREE.Group {
    const g = new THREE.Group();
    const mat = inkMaterial(0x2a2622);
    const base = new THREE.Mesh(new THREE.BoxGeometry(0.7, 0.45, 0.7), mat);
    base.position.set(0, LAND_H + 0.225, 0);
    const roof = new THREE.ConeGeometry(0.62, 0.42, 4, 1);
    roof.rotateY(Math.PI / 4);
    const roofMesh = new THREE.Mesh(roof, mat);
    roofMesh.position.set(0, LAND_H + 0.45 + 0.21, 0);
    base.raycast = () => {};
    roofMesh.raycast = () => {};
    addOutline(base, 0.05, 0x0e0d0b);
    g.add(base, roofMesh);
    g.position.set(at[0], 0, -at[1]);
    group.add(g);
    return g;
  }

  private makeLines(segments: number[], opts: { color: number; width: number; opacity?: number; dashed?: boolean; dash?: number; gap?: number }): LineSegments2 {
    const geom = new LineSegmentsGeometry();
    geom.setPositions(segments);
    const mat = new LineMaterial({
      color: opts.color, linewidth: opts.width, worldUnits: false,
      transparent: true, opacity: opts.opacity ?? 1, depthWrite: false,
      dashed: !!opts.dashed, dashSize: opts.dash ?? 0.6, gapSize: opts.gap ?? 0.4,
    });
    mat.resolution.copy(this.resolution);
    this.lineMaterials.push(mat);
    const lines = new LineSegments2(geom, mat);
    lines.computeLineDistances();
    lines.raycast = () => {};
    return lines;
  }

  /** 海岸線：固定不變，先畫一道淡而寬的「暈」，再畫一道細而深的墨線 */
  private buildCoast(): void {
    const segs: number[] = [];
    for (const arc of GEO_ARCS) if (!arc.b) polylineSegments(arc.pts, TOP_Y, segs);
    this.scene.add(this.makeLines(segs, { color: INK, width: 4.2, opacity: 0.16 }));
    this.scene.add(this.makeLines(segs, { color: INK, width: 1.7, opacity: 0.92 }));
  }

  /** 遊戲相鄰但沒有陸地邊界 → 畫成航路（虛線） */
  private buildSeaRoutes(): void {
    const land = new Set<string>();
    for (const arc of GEO_ARCS) if (arc.b) land.add([arc.a, arc.b].sort().join('|'));
    const seen = new Set<string>();
    const segs: number[] = [];
    for (const r of REGIONS) {
      for (const adj of r.adjacent) {
        const key = [r.id, adj].sort().join('|');
        if (seen.has(key) || land.has(key)) continue;
        seen.add(key);
        const a = GEO_REGIONS[r.id].castle, b = GEO_REGIONS[adj].castle;
        // 從城邊緣出發，微彎
        const dx = b[0] - a[0], dy = b[1] - a[1];
        const len = Math.hypot(dx, dy);
        const ux = dx / len, uy = dy / len;
        const nx = -uy, ny = ux;
        const pts: Pt[] = [];
        const steps = 10;
        for (let i = 0; i <= steps; i++) {
          const tt = i / steps;
          const bow = Math.sin(tt * Math.PI) * len * 0.12;
          pts.push([a[0] + dx * tt + nx * bow, a[1] + dy * tt + ny * bow]);
        }
        polylineSegments(pts, 0.03, segs);
      }
    }
    if (segs.length) this.scene.add(this.makeLines(segs, { color: INK, width: 1.3, opacity: 0.35, dashed: true, dash: 0.7, gap: 0.5 }));
  }

  /** 依領主重建內部邊界 / 國境線 */
  private rebuildBorders(state: GameState): void {
    const sig = REGIONS.map(r => state.regions[r.id].owner ?? '-').join(',');
    if (sig === this.borderSignature) return;
    this.borderSignature = sig;
    disposeObject(this.borderGroup);
    this.borderGroup.clear();
    const inner: number[] = [], frontier: number[] = [];
    for (const arc of GEO_ARCS) {
      if (!arc.b) continue;
      const oa = state.regions[arc.a].owner, ob = state.regions[arc.b].owner;
      polylineSegments(arc.pts, TOP_Y, oa && oa === ob ? inner : frontier);
    }
    if (inner.length) this.borderGroup.add(this.makeLines(inner, { color: INK, width: 0.9, opacity: 0.32, dashed: true, dash: 0.5, gap: 0.35 }));
    if (frontier.length) {
      this.borderGroup.add(this.makeLines(frontier, { color: INK, width: 3.6, opacity: 0.14 }));
      this.borderGroup.add(this.makeLines(frontier, { color: INK, width: 1.5, opacity: 0.9 }));
    }
  }

  private computeBounds(): void {
    this.bounds.set(
      new THREE.Vector3(GEO_BOUNDS.minX - 1.5, 0, -GEO_BOUNDS.maxY - 1.5),
      new THREE.Vector3(GEO_BOUNDS.maxX + 1.5, 3, -GEO_BOUNDS.minY + 1.5),
    );
  }

  // -------------------------------------------------------------------------
  // 公開 API
  // -------------------------------------------------------------------------

  /** 依遊戲狀態更新顏色、家紋、兵力、軍團、邊界。 */
  update(state: GameState): void {
    for (const node of this.regions.values()) {
      const rs = state.regions[node.id];
      if (!rs) continue;
      const faction = rs.owner ? FACTION_MAP[rs.owner] : undefined;
      const base = faction ? mutedColor(faction.color, 0.38) : mutedColor(NEUTRAL_COLOR, 0.5);
      node.baseColor = base;
      this.applyColor(node);

      const troops = rs.troops.ashigaru + rs.troops.cavalry + rs.troops.gun;
      setSpriteText(node.label, `${t(`region.short.${node.id}`)} ${fmt(troops)}`, 1.15);

      const kamonKey = faction ? `${faction.kamon}|${faction.color}` : '';
      if (kamonKey !== node.kamonKey) {
        if (node.kamon) {
          node.group.remove(node.kamon);
          node.kamon.material.dispose();
          node.kamon = null;
        }
        if (faction) {
          const at = GEO_REGIONS[node.id].castle;
          const s = kamonSprite(faction.kamon, hexStr(mixColor(faction.color, INK, 0.45)), 1.7, { badge: '#f5eedc' });
          s.position.set(at[0], LAND_H + 1.85, -at[1] - 0.15);
          s.raycast = () => {};
          node.group.add(s);
          node.kamon = s;
        }
        node.kamonKey = kamonKey;
      }
    }
    this.rebuildBorders(state);
    this.rebuildArmies(state);
  }

  /** 在區域主城上方飄出一行字（指令結果回饋） */
  floatText(id: RegionId, text: string, color = '#b23a2c'): void {
    const geo = GEO_REGIONS[id];
    if (!geo) return;
    const sprite = textSprite(text, 1.5, { color, halo: 'rgba(241,231,208,0.95)' });
    const x = geo.castle[0], z = -geo.castle[1];
    sprite.position.set(x, LAND_H + 3.2, z);
    sprite.raycast = () => {};
    this.scene.add(sprite);
    const mat = sprite.material;
    void this.tween.run(1600, (tt) => {
      sprite.position.y = LAND_H + 3.2 + tt * 2.4;
      mat.opacity = tt < 0.6 ? 1 : 1 - (tt - 0.6) / 0.4;
    }, ease.out).then(() => { this.scene.remove(sprite); mat.dispose(); });
  }

  /** 選取區域（null 取消）：加上脈動描邊並微微抬高。 */
  select(id: RegionId | null): void {
    if (this.selected && this.selected !== id) {
      const prev = this.regions.get(this.selected);
      if (prev) prev.group.position.y = 0;
    }
    disposeObject(this.selectGroup);
    this.selectGroup.clear();
    this.selected = id;
    if (id) {
      const node = this.regions.get(id);
      if (node) {
        node.group.position.y = 0.2;
        const segs: number[] = [];
        for (const ring of GEO_REGIONS[id].polys) polylineSegments([...ring, ring[0]], TOP_Y + 0.2, segs);
        this.selectGroup.add(this.makeLines(segs, { color: SELECT_COLOR, width: 3.2, opacity: 0.9 }));
      }
    }
  }

  /** 教學提示：金色脈動框標出要點的區域；null 清除 */
  hint(id: RegionId | null): void {
    if (id === this.hinted) return;
    this.hinted = id;
    disposeObject(this.hintGroup);
    this.hintGroup.clear();
    if (!id) return;
    const segs: number[] = [];
    for (const ring of GEO_REGIONS[id].polys) polylineSegments([...ring, ring[0]], TOP_Y + 0.25, segs);
    this.hintGroup.add(this.makeLines(segs, { color: 0xd9a93a, width: 5, opacity: 0.9 }));
  }

  /** 標示一組區域（例如可出陣目標）；空陣列清除。 */
  highlight(ids: RegionId[]): void {
    const set = new Set(ids);
    for (const node of this.regions.values()) {
      node.highlighted = set.has(node.id);
      this.applyColor(node);
    }
  }

  /** 把鏡頭移到該區域。 */
  focus(id: RegionId, animate = true, viewWidth?: number): void {
    const geo = GEO_REGIONS[id];
    if (!geo) return;
    const to = new THREE.Vector3(geo.castle[0], 0, -geo.castle[1]);
    if (viewWidth) this.setZoom(Math.max(this.baseView.w / viewWidth, this.baseView.h / (viewWidth * 0.9)));
    if (!animate) {
      this.target.copy(to);
      this.updateCamera();
      return;
    }
    const from = this.target.clone();
    void this.tween.run(450, (tt) => {
      this.target.lerpVectors(from, to, tt);
      this.updateCamera();
    }, ease.inOut);
  }

  resize(): void {
    const w = Math.max(1, this.container.clientWidth);
    const h = Math.max(1, this.container.clientHeight);
    this.renderer.setSize(w, h, false);
    this.resolution.set(w * this.renderer.getPixelRatio(), h * this.renderer.getPixelRatio());
    for (const m of this.lineMaterials) m.resolution.copy(this.resolution);
    this.fitToBounds(w / h);
    this.updateCamera();
  }

  dispose(): void {
    if (this.disposed) return;
    this.disposed = true;
    this.renderer.setAnimationLoop(null);
    this.resizeObs?.disconnect();
    window.removeEventListener('resize', this.onWindowResize);
    const c = this.renderer.domElement;
    c.removeEventListener('pointerdown', this.onPointerDown);
    c.removeEventListener('pointermove', this.onPointerMove);
    c.removeEventListener('pointerup', this.onPointerUp);
    c.removeEventListener('pointercancel', this.onPointerUp);
    c.removeEventListener('wheel', this.onWheel);
    this.tween.clear();
    disposeObject(this.scene);
    this.renderer.dispose();
    c.remove();
  }

  // -------------------------------------------------------------------------
  // 內部
  // -------------------------------------------------------------------------

  private applyColor(node: RegionNode): void {
    const c = node.highlighted ? mixColor(node.baseColor, HIGHLIGHT_COLOR, 0.45) : node.baseColor;
    node.material.color.setHex(c);
  }

  private rebuildArmies(state: GameState): void {
    disposeObject(this.armyGroup);
    this.armyGroup.clear();
    for (const army of state.armies) {
      const a = GEO_REGIONS[army.from];
      const b = GEO_REGIONS[army.target];
      const faction = FACTION_MAP[army.faction];
      if (!a || !b || !faction) continue;
      const from = new THREE.Vector3(a.castle[0], 0, -a.castle[1]);
      const to = new THREE.Vector3(b.castle[0], 0, -b.castle[1]);
      const dir = to.clone().sub(from);
      const len = dir.length();
      dir.normalize();
      const color = mixColor(faction.color, INK, 0.25);

      const p0 = from.clone().addScaledVector(dir, Math.min(1.2, len * 0.25));
      const p1 = to.clone().addScaledVector(dir, -Math.min(1.4, len * 0.3));
      p0.y = p1.y = TOP_Y + 0.5;
      const segs = [p0.x, p0.y, p0.z, p1.x, p1.y, p1.z];
      this.armyGroup.add(this.makeLines(segs, { color, width: 2.6, opacity: 0.95, dashed: true, dash: 0.8, gap: 0.45 }));

      const head = new THREE.Mesh(new THREE.ConeGeometry(0.5, 1.2, 3), new THREE.MeshBasicMaterial({ color }));
      head.position.copy(p1);
      head.quaternion.setFromUnitVectors(new THREE.Vector3(0, 1, 0), dir);
      head.raycast = () => {};
      this.armyGroup.add(head);

      const pos = from.clone().lerp(to, 0.4);
      const marker = kamonSprite(faction.kamon, hexStr(color), 1.3, { badge: '#f5eedc' });
      marker.position.set(pos.x, TOP_Y + 1.3, pos.z);
      marker.raycast = () => {};
      this.armyGroup.add(marker);
    }
  }

  /** 讓整張地圖在目前長寬比下剛好放得進畫面（zoom = 1）。 */
  private fitToBounds(aspect: number): void {
    const cam = new THREE.Matrix4().lookAt(new THREE.Vector3(), this.forward, new THREE.Vector3(0, 1, 0));
    const inv = cam.clone().invert();
    const center = this.bounds.getCenter(new THREE.Vector3());
    let maxX = 0, maxY = 0;
    const v = new THREE.Vector3();
    for (let i = 0; i < 8; i++) {
      v.set(
        i & 1 ? this.bounds.min.x : this.bounds.max.x,
        i & 2 ? this.bounds.min.y : this.bounds.max.y,
        i & 4 ? this.bounds.min.z : this.bounds.max.z,
      ).sub(center).applyMatrix4(inv);
      maxX = Math.max(maxX, Math.abs(v.x));
      maxY = Math.max(maxY, Math.abs(v.y));
    }
    const pad = 1.05;
    let w = maxX * 2 * pad;
    let h = maxY * 2 * pad;
    if (w / h < aspect) w = h * aspect; else h = w / aspect;
    this.baseView = { w, h };
    this.camera.left = -w / 2;
    this.camera.right = w / 2;
    this.camera.top = h / 2;
    this.camera.bottom = -h / 2;
    this.camera.updateProjectionMatrix();
  }

  private updateCamera(): void {
    const pad = 6;
    this.target.x = THREE.MathUtils.clamp(this.target.x, this.bounds.min.x - pad, this.bounds.max.x + pad);
    this.target.z = THREE.MathUtils.clamp(this.target.z, this.bounds.min.z - pad, this.bounds.max.z + pad);
    this.target.y = 0;
    this.camera.position.copy(this.target).addScaledVector(this.forward, -CAMERA_DIST);
    this.camera.lookAt(this.target);
    this.camera.updateMatrixWorld();
  }

  private setZoom(z: number): void {
    this.camera.zoom = THREE.MathUtils.clamp(z, ZOOM_MIN, ZOOM_MAX);
    this.camera.updateProjectionMatrix();
  }

  private ndc(x: number, y: number): THREE.Vector2 {
    const r = this.renderer.domElement.getBoundingClientRect();
    return new THREE.Vector2(((x - r.left) / r.width) * 2 - 1, -((y - r.top) / r.height) * 2 + 1);
  }

  private hitPlane(x: number, y: number): THREE.Vector3 | null {
    this.raycaster.setFromCamera(this.ndc(x, y), this.camera);
    const out = new THREE.Vector3();
    return this.raycaster.ray.intersectPlane(this.plane, out) ? out : null;
  }

  private pickRegion(x: number, y: number): RegionId | null {
    this.raycaster.setFromCamera(this.ndc(x, y), this.camera);
    const hits = this.raycaster.intersectObjects(this.regionMeshes, false);
    if (hits.length) return hits[0].object.userData.regionId as RegionId;
    // 沒點到陸地：若落在某區主城附近（例如點到家紋）也算選中
    const p = this.hitPlane(x, y);
    if (p) {
      let best: RegionId | null = null, bd = 2.2;
      for (const r of REGIONS) {
        const c = GEO_REGIONS[r.id].castle;
        const d = Math.hypot(c[0] - p.x, -c[1] - p.z);
        if (d < bd) { bd = d; best = r.id; }
      }
      return best;
    }
    return null;
  }

  // ---- 輸入 ----

  private bindInput(): void {
    const c = this.renderer.domElement;
    c.addEventListener('pointerdown', this.onPointerDown);
    c.addEventListener('pointermove', this.onPointerMove);
    c.addEventListener('pointerup', this.onPointerUp);
    c.addEventListener('pointercancel', this.onPointerUp);
    c.addEventListener('wheel', this.onWheel, { passive: false });
  }

  private onWindowResize = (): void => this.resize();

  private onPointerDown = (e: PointerEvent): void => {
    const c = this.renderer.domElement;
    try { c.setPointerCapture(e.pointerId); } catch { /* ignore */ }
    this.pointers.set(e.pointerId, { x: e.clientX, y: e.clientY });
    if (this.pointers.size === 1) {
      this.pressStart = { x: e.clientX, y: e.clientY };
      this.moved = false;
      const hit = this.hitPlane(e.clientX, e.clientY);
      if (hit) this.panAnchor.copy(hit);
    } else if (this.pointers.size === 2) {
      const [p1, p2] = [...this.pointers.values()];
      this.pinchStart = { dist: Math.hypot(p1.x - p2.x, p1.y - p2.y), zoom: this.camera.zoom };
      this.moved = true;
      const hit = this.hitPlane((p1.x + p2.x) / 2, (p1.y + p2.y) / 2);
      if (hit) this.panAnchor.copy(hit);
    }
  };

  private onPointerMove = (e: PointerEvent): void => {
    const p = this.pointers.get(e.pointerId);
    if (!p) return;
    p.x = e.clientX;
    p.y = e.clientY;
    if (this.pointers.size === 1) {
      if (this.pressStart && !this.moved) {
        if (Math.hypot(e.clientX - this.pressStart.x, e.clientY - this.pressStart.y) > TAP_THRESHOLD_PX) this.moved = true;
      }
      if (this.moved) this.panTo(e.clientX, e.clientY);
    } else if (this.pointers.size === 2 && this.pinchStart) {
      const [p1, p2] = [...this.pointers.values()];
      const d = Math.hypot(p1.x - p2.x, p1.y - p2.y);
      const mx = (p1.x + p2.x) / 2, my = (p1.y + p2.y) / 2;
      this.setZoom(this.pinchStart.zoom * (d / Math.max(1, this.pinchStart.dist)));
      this.panTo(mx, my);
    }
  };

  private onPointerUp = (e: PointerEvent): void => {
    const c = this.renderer.domElement;
    try { c.releasePointerCapture(e.pointerId); } catch { /* ignore */ }
    const wasSingle = this.pointers.size === 1;
    this.pointers.delete(e.pointerId);
    if (wasSingle && this.pressStart && !this.moved && e.type === 'pointerup') {
      const id = this.pickRegion(e.clientX, e.clientY);
      this.onSelect?.(id);
    }
    if (this.pointers.size === 0) {
      this.pressStart = null;
      this.pinchStart = null;
    } else if (this.pointers.size === 1) {
      const [p] = [...this.pointers.values()];
      const hit = this.hitPlane(p.x, p.y);
      if (hit) this.panAnchor.copy(hit);
      this.pinchStart = null;
      this.moved = true;
    }
  };

  private onWheel = (e: WheelEvent): void => {
    e.preventDefault();
    const factor = Math.exp(-e.deltaY * 0.0015);
    const before = this.hitPlane(e.clientX, e.clientY);
    this.setZoom(this.camera.zoom * factor);
    const after = this.hitPlane(e.clientX, e.clientY);
    if (before && after) {
      this.target.add(before.sub(after));
      this.updateCamera();
    }
  };

  /** 讓 panAnchor 所指的地面點移到指標 (x,y) 之下。 */
  private panTo(x: number, y: number): void {
    const hit = this.hitPlane(x, y);
    if (!hit) return;
    const delta = this.panAnchor.clone().sub(hit);
    delta.y = 0;
    this.target.add(delta);
    this.updateCamera();
  }

  // ---- 每幀 ----

  private tick = (): void => {
    if (this.disposed) return;
    const now = performance.now();
    this.tween.update(now);
    if (this.selected) {
      for (const o of this.selectGroup.children) {
        const m = (o as LineSegments2).material as LineMaterial;
        m.opacity = 0.55 + 0.35 * Math.sin(now * 0.004);
      }
    }
    if (this.hinted) {
      for (const o of this.hintGroup.children) {
        const m = (o as LineSegments2).material as LineMaterial;
        m.opacity = 0.45 + 0.5 * Math.abs(Math.sin(now * 0.005));
        m.linewidth = 3.5 + 2.5 * Math.abs(Math.sin(now * 0.005));
      }
    }
    this.renderer.render(this.scene, this.camera);
  };
}
