// ===== 戰略地圖（three.js，水墨風） =====
// 地圖座標：pos.x 往東 → world x；pos.y 往北 → world -z。

import * as THREE from 'three';
import type { GameState, RegionId } from '../core/types';
import { REGIONS, REGION_MAP } from '../data/regions';
import { FACTION_MAP } from '../data/factions';
import {
  INK, PAPER_CREAM, addOutline, blobShape, disposeObject, ease, inkMaterial, kamonSprite,
  makePaperTexture, mixColor, mulberry32, mutedColor, setSpriteText, textSprite, Tweener,
} from './ink';

const NEUTRAL_COLOR = 0x8d8a82;
const HIGHLIGHT_COLOR = 0xc0392b;
const SELECT_COLOR = 0xa8281c;
const TAP_THRESHOLD_PX = 8;
const ZOOM_MIN = 0.75;
const ZOOM_MAX = 4;
const CAMERA_PITCH = THREE.MathUtils.degToRad(56); // 與水平面的夾角
const CAMERA_DIST = 120;

interface RegionNode {
  id: RegionId;
  group: THREE.Group;
  mesh: THREE.Mesh;
  material: THREE.MeshToonMaterial;
  outline: THREE.Mesh;
  selectOutline: THREE.Mesh;
  kamon: THREE.Sprite | null;
  kamonKey: string;
  label: THREE.Sprite;
  baseColor: number;
  highlighted: boolean;
}

function fmt(n: number): string {
  return n.toLocaleString('en-US');
}

function hexStr(c: number): string {
  return '#' + c.toString(16).padStart(6, '0');
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
  private baseView = { w: 100, h: 50 }; // zoom = 1 時的視野（世界單位）
  private regions = new Map<RegionId, RegionNode>();
  private regionMeshes: THREE.Mesh[] = [];
  private armyGroup = new THREE.Group();
  private selected: RegionId | null = null;
  private tween = new Tweener();
  private raycaster = new THREE.Raycaster();
  private plane = new THREE.Plane(new THREE.Vector3(0, 1, 0), 0);
  private resizeObs: ResizeObserver | null = null;
  private disposed = false;
  private clock = new THREE.Clock();

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
    this.renderer.setClearColor(PAPER_CREAM, 1);
    const canvas = this.renderer.domElement;
    canvas.style.display = 'block';
    canvas.style.width = '100%';
    canvas.style.height = '100%';
    canvas.style.touchAction = 'none';
    canvas.style.userSelect = 'none';
    (canvas.style as unknown as Record<string, string>).webkitUserSelect = 'none';
    container.appendChild(canvas);

    this.camera = new THREE.OrthographicCamera(-50, 50, 25, -25, 1, 400);
    this.forward.set(0, -Math.sin(CAMERA_PITCH), -Math.cos(CAMERA_PITCH)).normalize();

    this.buildLights();
    this.buildPaper();
    this.buildRegions();
    this.buildRoads();
    this.scene.add(this.armyGroup);

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
    const hemi = new THREE.HemisphereLight(0xfff6e3, 0x9c8a6c, 1.6);
    this.scene.add(hemi);
    const dir = new THREE.DirectionalLight(0xffffff, 1.4);
    dir.position.set(-30, 60, 20);
    this.scene.add(dir);
  }

  private buildPaper(): void {
    const tex = makePaperTexture();
    tex.repeat.set(7, 7);
    const geom = new THREE.PlaneGeometry(420, 420);
    geom.rotateX(-Math.PI / 2);
    const mat = new THREE.MeshBasicMaterial({ map: tex });
    const paper = new THREE.Mesh(geom, mat);
    paper.position.set(48, -0.02, -20);
    paper.name = 'paper';
    this.scene.add(paper);

    // 淡淡的海波墨線（暗示海面）
    const rnd = mulberry32(7);
    const pts: number[] = [];
    for (let i = 0; i < 70; i++) {
      const x = -10 + rnd() * 116;
      const z = 12 - rnd() * 64;
      const len = 2 + rnd() * 4;
      const segs = 6;
      for (let s = 0; s < segs; s++) {
        const t0 = s / segs;
        const t1 = (s + 1) / segs;
        pts.push(x + t0 * len, 0.01, z + Math.sin(t0 * Math.PI * 2) * 0.25);
        pts.push(x + t1 * len, 0.01, z + Math.sin(t1 * Math.PI * 2) * 0.25);
      }
    }
    const g = new THREE.BufferGeometry();
    g.setAttribute('position', new THREE.Float32BufferAttribute(pts, 3));
    const waves = new THREE.LineSegments(g, new THREE.LineBasicMaterial({ color: INK, transparent: true, opacity: 0.1 }));
    waves.name = 'waves';
    this.scene.add(waves);
  }

  private buildRegions(): void {
    REGIONS.forEach((def, idx) => {
      const group = new THREE.Group();
      group.position.set(def.pos.x, 0, -def.pos.y);
      group.name = `region:${def.id}`;

      const shape = blobShape(def.size * 0.92, 1000 + idx * 17, 14);
      const geom = new THREE.ExtrudeGeometry(shape, {
        depth: 0.6,
        bevelEnabled: true,
        bevelThickness: 0.08,
        bevelSize: 0.12,
        bevelSegments: 1,
        curveSegments: 6,
      });
      geom.rotateX(-Math.PI / 2);
      geom.computeBoundingSphere();
      const material = inkMaterial(mutedColor(NEUTRAL_COLOR));
      const mesh = new THREE.Mesh(geom, material);
      mesh.userData.regionId = def.id;
      group.add(mesh);

      const outline = addOutline(mesh, 0.16);
      // 描邊沿 y 稍微下壓，避免底部露出一圈
      outline.position.y = -0.05;

      const selectOutline = addOutline(mesh, 0.75, SELECT_COLOR);
      selectOutline.position.y = -0.05;
      const selMat = selectOutline.material as THREE.MeshBasicMaterial;
      selMat.transparent = true;
      selMat.opacity = 0;
      selectOutline.visible = false;

      // 地面墨影（讓島像是浮在紙上）
      const shadowGeom = new THREE.ShapeGeometry(shape, 6);
      shadowGeom.rotateX(-Math.PI / 2);
      const shadow = new THREE.Mesh(shadowGeom, new THREE.MeshBasicMaterial({ color: INK, transparent: true, opacity: 0.12, depthWrite: false }));
      shadow.position.set(0.35, 0.0, 0.45);
      shadow.scale.setScalar(1.04);
      shadow.raycast = () => {};
      group.add(shadow);

      if (def.terrain === 'mountain') this.addMountains(group, def.size, idx);
      this.addCastle(group);

      const label = textSprite('0', 1.5);
      label.position.set(0, 0.8, 3.8);
      label.raycast = () => {};
      group.add(label);

      this.scene.add(group);
      this.regionMeshes.push(mesh);
      this.regions.set(def.id, {
        id: def.id, group, mesh, material, outline, selectOutline,
        kamon: null, kamonKey: '', label, baseColor: material.color.getHex(), highlighted: false,
      });
    });
  }

  private addMountains(group: THREE.Group, size: number, idx: number): void {
    const rnd = mulberry32(500 + idx);
    const n = 2 + Math.floor(rnd() * 2);
    const mat = inkMaterial(0x5b5752);
    for (let i = 0; i < n; i++) {
      const h = 1.1 + rnd() * 1.1;
      const geom = new THREE.ConeGeometry(0.8 + rnd() * 0.5, h, 4, 1);
      geom.translate(0, h / 2, 0);
      const m = new THREE.Mesh(geom, mat);
      const ang = rnd() * Math.PI * 2;
      const r = size * (0.25 + rnd() * 0.3);
      m.position.set(Math.cos(ang) * r, 0.62, Math.sin(ang) * r * 0.8);
      m.rotation.y = rnd() * Math.PI;
      m.raycast = () => {};
      addOutline(m, 0.08);
      group.add(m);
    }
  }

  private addCastle(group: THREE.Group): void {
    const mat = inkMaterial(0x2a2622);
    const base = new THREE.Mesh(new THREE.BoxGeometry(0.9, 0.55, 0.9), mat);
    base.position.set(0, 0.62 + 0.275, 0);
    const roof = new THREE.ConeGeometry(0.8, 0.5, 4, 1);
    roof.rotateY(Math.PI / 4);
    const roofMesh = new THREE.Mesh(roof, mat);
    roofMesh.position.set(0, 0.62 + 0.55 + 0.25, 0);
    base.raycast = () => {};
    roofMesh.raycast = () => {};
    addOutline(base, 0.06, 0x0e0d0b);
    group.add(base, roofMesh);
  }

  private buildRoads(): void {
    const seen = new Set<string>();
    const pts: number[] = [];
    for (const r of REGIONS) {
      for (const adj of r.adjacent) {
        const key = [r.id, adj].sort().join('|');
        if (seen.has(key)) continue;
        seen.add(key);
        const o = REGION_MAP[adj];
        if (!o) continue;
        // 把路線切成數段並略微抖動，像是手繪線
        const rnd = mulberry32(key.length * 31 + key.charCodeAt(0) * 7 + key.charCodeAt(key.length - 1));
        const segs = 5;
        let px = r.pos.x, pz = -r.pos.y;
        for (let s = 1; s <= segs; s++) {
          const t = s / segs;
          const jx = s === segs ? 0 : (rnd() - 0.5) * 0.9;
          const jz = s === segs ? 0 : (rnd() - 0.5) * 0.9;
          const nx = r.pos.x + (o.pos.x - r.pos.x) * t + jx;
          const nz = -(r.pos.y + (o.pos.y - r.pos.y) * t) + jz;
          pts.push(px, 0.78, pz, nx, 0.78, nz);
          px = nx; pz = nz;
        }
      }
    }
    const geom = new THREE.BufferGeometry();
    geom.setAttribute('position', new THREE.Float32BufferAttribute(pts, 3));
    const mat = new THREE.LineBasicMaterial({ color: INK, transparent: true, opacity: 0.4 });
    const roads = new THREE.LineSegments(geom, mat);
    roads.name = 'roads';
    this.scene.add(roads);
  }

  private computeBounds(): void {
    this.bounds.makeEmpty();
    for (const r of REGIONS) {
      const p = new THREE.Vector3(r.pos.x, 0, -r.pos.y);
      this.bounds.expandByPoint(p.clone().add(new THREE.Vector3(r.size + 1.5, 0, r.size + 1.5)));
      this.bounds.expandByPoint(p.clone().sub(new THREE.Vector3(r.size + 1.5, 0, r.size + 1.5)));
    }
    this.bounds.max.y = 3;
  }

  // -------------------------------------------------------------------------
  // 公開 API
  // -------------------------------------------------------------------------

  /** 依遊戲狀態更新顏色、家紋、兵力、軍團。 */
  update(state: GameState): void {
    for (const node of this.regions.values()) {
      const rs = state.regions[node.id];
      if (!rs) continue;
      const faction = rs.owner ? FACTION_MAP[rs.owner] : undefined;
      const base = faction ? mutedColor(faction.color, 0.5) : mutedColor(NEUTRAL_COLOR, 0.45);
      node.baseColor = base;
      this.applyColor(node);

      const troops = rs.troops.ashigaru + rs.troops.cavalry + rs.troops.gun;
      setSpriteText(node.label, fmt(troops), 1.5);

      const kamonKey = faction ? `${faction.kamon}|${faction.color}` : '';
      if (kamonKey !== node.kamonKey) {
        if (node.kamon) {
          node.group.remove(node.kamon);
          node.kamon.material.dispose();
          node.kamon = null;
        }
        if (faction) {
          const s = kamonSprite(faction.kamon, hexStr(mixColor(faction.color, INK, 0.45)), 2.4, { badge: '#f5eedc' });
          s.position.set(0, 2.4, -1.0);
          s.raycast = () => {};
          node.group.add(s);
          node.kamon = s;
        }
        node.kamonKey = kamonKey;
      }
    }
    this.rebuildArmies(state);
  }

  /** 選取區域（null 取消）：加上脈動描邊並微微抬高。 */
  select(id: RegionId | null): void {
    if (this.selected && this.selected !== id) {
      const prev = this.regions.get(this.selected);
      if (prev) {
        prev.selectOutline.visible = false;
        prev.group.position.y = 0;
      }
    }
    this.selected = id;
    if (id) {
      const node = this.regions.get(id);
      if (node) {
        node.selectOutline.visible = true;
        node.group.position.y = 0.35;
      }
    }
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
    const def = REGION_MAP[id];
    if (!def) return;
    const to = new THREE.Vector3(def.pos.x, 0, -def.pos.y);
    // viewWidth：希望畫面橫向顯示的世界單位寬度（例如 40 ≈ 主城附近 6〜8 區）
    if (viewWidth) this.setZoom(Math.max(this.baseView.w / viewWidth, this.baseView.h / (viewWidth * 0.9)));
    if (!animate) {
      this.target.copy(to);
      this.updateCamera();
      return;
    }
    const from = this.target.clone();
    void this.tween.run(450, (t) => {
      this.target.lerpVectors(from, to, t);
      this.updateCamera();
    }, ease.inOut);
  }

  resize(): void {
    const w = Math.max(1, this.container.clientWidth);
    const h = Math.max(1, this.container.clientHeight);
    this.renderer.setSize(w, h, false);
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
    const c = node.highlighted ? mixColor(node.baseColor, HIGHLIGHT_COLOR, 0.5) : node.baseColor;
    node.material.color.setHex(c);
    const om = node.outline.material as THREE.MeshBasicMaterial;
    om.color.setHex(node.highlighted ? 0x7a1f14 : INK);
  }

  private rebuildArmies(state: GameState): void {
    disposeObject(this.armyGroup);
    this.armyGroup.clear();
    for (const army of state.armies) {
      const a = REGION_MAP[army.from];
      const b = REGION_MAP[army.target];
      const faction = FACTION_MAP[army.faction];
      if (!a || !b || !faction) continue;
      const from = new THREE.Vector3(a.pos.x, 0, -a.pos.y);
      const to = new THREE.Vector3(b.pos.x, 0, -b.pos.y);
      const dir = to.clone().sub(from);
      const len = dir.length();
      dir.normalize();
      const color = mixColor(faction.color, INK, 0.2);

      // 虛線（從出發區邊緣到目標區邊緣）
      const p0 = from.clone().addScaledVector(dir, Math.min(a.size * 0.6, len * 0.3));
      const p1 = to.clone().addScaledVector(dir, -Math.min(b.size * 0.7, len * 0.3));
      p0.y = p1.y = 1.0;
      const lg = new THREE.BufferGeometry().setFromPoints([p0, p1]);
      const line = new THREE.Line(lg, new THREE.LineDashedMaterial({ color, dashSize: 1.0, gapSize: 0.6, transparent: true, opacity: 0.9 }));
      line.computeLineDistances();
      this.armyGroup.add(line);

      // 箭頭
      const head = new THREE.Mesh(new THREE.ConeGeometry(0.55, 1.4, 3), new THREE.MeshBasicMaterial({ color }));
      head.position.copy(p1).setY(1.0);
      head.quaternion.setFromUnitVectors(new THREE.Vector3(0, 1, 0), dir);
      this.armyGroup.add(head);

      // 行軍標記：35% 處的家紋
      const pos = from.clone().lerp(to, 0.35);
      const marker = kamonSprite(faction.kamon, hexStr(color), 1.2, { badge: '#f5eedc' });
      marker.position.set(pos.x, 1.4, pos.z);
      this.armyGroup.add(marker);
    }
  }

  /** 讓整張地圖在目前長寬比下剛好放得進畫面（zoom = 1）。 */
  private fitToBounds(aspect: number): void {
    // 把包圍盒八個角轉到相機空間，取 x/y 範圍
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
    const pad = 1.06;
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
    // 限制平移範圍
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
    return hits.length ? (hits[0].object.userData.regionId as RegionId) : null;
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
      // 由雙指回到單指：重設平移錨點，避免跳動
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
    const dt = this.clock.getDelta();
    void dt;
    if (this.selected) {
      const node = this.regions.get(this.selected);
      if (node) {
        const m = node.selectOutline.material as THREE.MeshBasicMaterial;
        m.opacity = 0.55 + 0.35 * Math.sin(now * 0.004);
      }
    }
    this.renderer.render(this.scene, this.camera);
  };
}
