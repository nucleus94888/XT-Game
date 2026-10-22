// ===== 戰鬥場景（three.js，水墨風，即時版） =====
// 左 = 攻方，右 = 守方。每一方由數十名士兵（instanced）+ 幾面家紋幟旗組成，依陣形排列：
//   突擊：楔形、衝向敵陣、交鋒時前排猛刺      方陣：密集方形、槍林豎立
//   鐵砲：兩列橫隊、前排跪射、箭矢與硝煙      迂迴：縱隊繞向側翼
// 傷亡時士兵倒下、濺墨、飄出數字；部隊頭上有兵力條（勢力色）與士氣條（金）；
// 事件（火計、一騎討、鼓舞、撤退、潰敗）以大字宣告 + 動畫。

import * as THREE from 'three';
import type { BattleState } from '../core/types';
import type { RtEvent, SideKey, Stance } from '../systems/rtbattle';
import { t } from '../i18n';
import {
  INK, PAPER_CREAM, Tweener, addOutline, disposeObject, ease, inkBlotMesh, inkMaterial,
  loadKamonImage, makePaperTexture, mixColor, mulberry32, mutedColor, setSpriteText, textSprite,
} from './ink';

export interface BattleSideInfo {
  kamon: string;
  color: number;
  name: string;
}

interface Slot {
  /** 陣形內的目標位置（區域座標） */
  target: THREE.Vector3;
  pos: THREE.Vector3;
  phase: number;
  alive: boolean;
  /** 倒下進度 0..1（>0 表示正在倒下） */
  fall: number;
  kneel: boolean;
  row: number;
}

interface Banner {
  group: THREE.Group;
  mats: THREE.Material[];
  target: THREE.Vector3;
}

interface Block {
  side: SideKey;
  info: BattleSideInfo;
  group: THREE.Group;
  baseX: number;
  dir: number;
  stance: Stance;
  switching: boolean;
  retreated: boolean;
  routed: boolean;
  advance: number;          // 目前前進量（沿 dir）
  targetAdvance: number;
  sideShift: number;        // 迂迴時的側向位移
  slots: Slot[];
  body: THREE.InstancedMesh;
  head: THREE.InstancedMesh;
  spear: THREE.InstancedMesh;
  banners: Banner[];
  flagTex: THREE.CanvasTexture;
  label: THREE.Sprite;
  telegraph: THREE.Sprite;
  telegraphText: string;
  hpBg: THREE.Sprite;
  hpFill: THREE.Sprite;
  moraleFill: THREE.Sprite;
  volleyTimer: number;
  opacity: number;
}

const ATK_X = -8.5;
const DEF_X = 8.5;
const FRONT_DEPTH = 1.5;
const BAR_W = 4.2;
const SOLDIER_CAP = 40;

function troopsOf(s: BattleState['attacker']): number {
  return s.troops.ashigaru + s.troops.cavalry + s.troops.gun;
}

/** 士兵數：每 350 人一個，6〜40 */
function soldiersFor(troops: number): number {
  return Math.max(6, Math.min(SOLDIER_CAP, Math.round(troops / 350)));
}

function hexStr(c: number): string {
  return '#' + c.toString(16).padStart(6, '0');
}

const _m = new THREE.Matrix4();
const _q = new THREE.Quaternion();
const _s = new THREE.Vector3();
const _p = new THREE.Vector3();
const _e = new THREE.Euler();

export class BattleScene {
  private container: HTMLElement;
  private renderer: THREE.WebGLRenderer;
  private scene = new THREE.Scene();
  private camera: THREE.PerspectiveCamera;
  private tween = new Tweener();
  private root = new THREE.Group();
  private fx = new THREE.Group();
  private atk: Block | null = null;
  private def: Block | null = null;
  private battle: BattleState | null = null;
  private rain: { lines: THREE.LineSegments; pos: Float32Array } | null = null;
  private resizeObs: ResizeObserver | null = null;
  private disposed = false;
  private clock = new THREE.Clock();
  private seed = 1;
  private elapsed = 0;
  private melee = false;
  private meleeSplat = 0;
  private started = false;
  private camX = 0;
  private camDist = 40;
  private camPitch = 0.6;
  private rnd = mulberry32(11);

  constructor(container: HTMLElement) {
    this.container = container;
    this.renderer = new THREE.WebGLRenderer({ antialias: true, powerPreference: 'high-performance' });
    this.renderer.setPixelRatio(Math.min(window.devicePixelRatio || 1, 2));
    this.renderer.outputColorSpace = THREE.SRGBColorSpace;
    this.renderer.setClearColor(PAPER_CREAM, 1);
    const canvas = this.renderer.domElement;
    canvas.style.display = 'block';
    canvas.style.width = '100%';
    canvas.style.height = '100%';
    canvas.style.touchAction = 'none';
    container.appendChild(canvas);

    this.camera = new THREE.PerspectiveCamera(38, 1, 0.5, 300);
    this.scene.fog = new THREE.Fog(PAPER_CREAM, 60, 130);

    this.scene.add(new THREE.HemisphereLight(0xfff6e3, 0x9c8a6c, 1.5));
    const dir = new THREE.DirectionalLight(0xffffff, 1.5);
    dir.position.set(-20, 40, 30);
    this.scene.add(dir);

    const tex = makePaperTexture();
    tex.repeat.set(9, 9);
    const ground = new THREE.Mesh(new THREE.PlaneGeometry(260, 260), new THREE.MeshBasicMaterial({ map: tex }));
    ground.rotateX(-Math.PI / 2);
    ground.position.y = -0.01;
    this.scene.add(ground);

    // 戰場中線（淡墨）
    const mid = new THREE.Mesh(new THREE.PlaneGeometry(0.12, 26), new THREE.MeshBasicMaterial({ color: INK, transparent: true, opacity: 0.10 }));
    mid.rotateX(-Math.PI / 2);
    mid.position.set(0, 0.005, 0);
    this.scene.add(mid);

    const horizon = new THREE.Mesh(new THREE.PlaneGeometry(220, 1.2), new THREE.MeshBasicMaterial({ color: INK, transparent: true, opacity: 0.08 }));
    horizon.rotateX(-Math.PI / 2);
    horizon.position.set(0, 0.0, -30);
    this.scene.add(horizon);

    this.scene.add(this.root, this.fx);

    this.resize();
    this.resizeObs = new ResizeObserver(() => this.resize());
    this.resizeObs.observe(container);
    window.addEventListener('resize', this.onWindowResize);
    this.renderer.setAnimationLoop(this.tick);
  }

  // -------------------------------------------------------------------------
  // 公開 API
  // -------------------------------------------------------------------------

  setup(battle: BattleState, atk: BattleSideInfo, def: BattleSideInfo, stances: Record<SideKey, Stance>): void {
    this.tween.clear();
    disposeObject(this.root);
    this.root.clear();
    disposeObject(this.fx);
    this.fx.clear();
    this.rain = null;
    this.battle = battle;
    this.melee = false;
    this.started = false;
    this.camX = 0;
    this.seed = battle.id.length * 97 + battle.round;
    this.rnd = mulberry32(this.seed);

    const defX = battle.siege ? DEF_X - 2 : DEF_X;
    this.atk = this.buildBlock('attacker', atk, troopsOf(battle.attacker), ATK_X, +1, stances.attacker);
    this.def = this.buildBlock('defender', def, troopsOf(battle.defender), defX, -1, stances.defender);
    this.root.add(this.atk.group, this.def.group);
    for (const b of [this.atk, this.def]) { this.applyFormation(b, true); this.updateBars(b); }

    if (battle.siege) this.buildCastle(battle.defense);
    if (battle.terrain === 'mountain') this.buildMountains();
    if (battle.weather === 'rain') this.buildRain();
  }

  /** 改陣：switching = true 表示改陣中 */
  setStance(side: SideKey, stance: Stance, switching: boolean): void {
    const b = this.block(side);
    if (!b) return;
    if (b.stance === stance && b.switching === switching) return;
    b.stance = stance;
    b.switching = switching;
    this.applyFormation(b, false);
    setSpriteText(b.label, switching ? t('battle.rt.stanceLabel.switching') : t(`tactic.${stance}`), 1.25, { color: '#1c1915', halo: 'rgba(241,231,208,0.92)' });
  }

  /** 敵方預告（給玩家看）；stance 為 null 則隱藏 */
  setTelegraph(side: SideKey, stance: Stance | null): void {
    const b = this.block(side);
    if (!b) return;
    const text = stance ? `▶ ${t(`tactic.${stance}`)}` : '';
    if (text === b.telegraphText) return;
    b.telegraphText = text;
    b.telegraph.visible = !!stance;
    if (stance) setSpriteText(b.telegraph, text, 1.3, { color: '#b23a2c', halo: 'rgba(241,231,208,0.95)' });
  }

  /** 開戰：部隊開始推進（布陣階段凍結不動） */
  begin(): void {
    this.started = true;
  }

  /** 事件動畫（不阻塞） */
  showEvent(ev: RtEvent): void {
    const me = this.block(ev.side), foe = this.block(ev.side === 'attacker' ? 'defender' : 'attacker');
    if (!me || !foe) return;
    switch (ev.kind) {
      case 'fire': void this.animFire(foe, !!ev.ok); break;
      case 'duel': void this.animDuel(me, foe, !!ev.ok); break;
      case 'rally': void this.animRally(me); break;
      case 'retreat': this.beginRetreat(me); break;
      case 'rout': if (!me.retreated) this.beginRout(me); break;
      default: break;
    }
  }

  /** 依兵力同步士兵數；loss > 0 時士兵倒下、濺墨、飄出數字 */
  syncTroops(battle: BattleState, lossA: number, lossD: number): void {
    if (!this.atk || !this.def) return;
    this.battle = battle;
    if (lossA > 0) this.casualties(this.atk, lossA);
    if (lossD > 0) this.casualties(this.def, lossD);
    this.cullTo(this.atk, soldiersFor(troopsOf(battle.attacker)));
    this.cullTo(this.def, soldiersFor(troopsOf(battle.defender)));
    this.updateBars(this.atk);
    this.updateBars(this.def);
  }

  resize(): void {
    const w = Math.max(1, this.container.clientWidth);
    const h = Math.max(1, this.container.clientHeight);
    this.renderer.setSize(w, h, false);
    const aspect = w / h;
    this.camera.aspect = aspect;
    const halfW = aspect < 1 ? 12.5 : 13.5;
    const vfov = THREE.MathUtils.degToRad(this.camera.fov);
    const hfov = 2 * Math.atan(Math.tan(vfov / 2) * aspect);
    const distW = halfW / Math.tan(hfov / 2);
    this.camDist = Math.max(26, distW);
    this.camPitch = THREE.MathUtils.degToRad(aspect < 1 ? 38 : 30);
    this.placeCamera();
    this.camera.updateProjectionMatrix();
  }

  dispose(): void {
    if (this.disposed) return;
    this.disposed = true;
    this.renderer.setAnimationLoop(null);
    this.resizeObs?.disconnect();
    window.removeEventListener('resize', this.onWindowResize);
    this.tween.clear();
    disposeObject(this.scene);
    this.renderer.dispose();
    this.renderer.domElement.remove();
  }

  // -------------------------------------------------------------------------
  // 建構
  // -------------------------------------------------------------------------

  private block(side: SideKey): Block | null {
    return side === 'attacker' ? this.atk : this.def;
  }

  private flagTexture(info: BattleSideInfo): THREE.CanvasTexture {
    const w = 128, h = 256;
    const canvas = document.createElement('canvas');
    canvas.width = w;
    canvas.height = h;
    const ctx = canvas.getContext('2d')!;
    const clothHex = mutedColor(info.color, 0.2);
    const cloth = hexStr(clothHex);
    const cc = new THREE.Color(clothHex);
    const lum = 0.2126 * cc.r + 0.7152 * cc.g + 0.0722 * cc.b;
    const kamonColor = lum > 0.2 ? '#1c1915' : '#f3ead8';
    const draw = (img: HTMLImageElement | null): void => {
      ctx.fillStyle = cloth;
      ctx.fillRect(0, 0, w, h);
      ctx.strokeStyle = 'rgba(0,0,0,0.07)';
      ctx.lineWidth = 2;
      for (let y = 6; y < h; y += 10) { ctx.beginPath(); ctx.moveTo(0, y); ctx.lineTo(w, y); ctx.stroke(); }
      if (img) ctx.drawImage(img, w * 0.12, h * 0.07, w * 0.76, w * 0.76);
      ctx.fillStyle = kamonColor;
      ctx.globalAlpha = 0.85;
      ctx.fillRect(w * 0.18, h * 0.62, w * 0.64, h * 0.03);
      ctx.fillRect(w * 0.18, h * 0.72, w * 0.64, h * 0.03);
      ctx.globalAlpha = 1;
      ctx.strokeStyle = 'rgba(28,25,21,0.9)';
      ctx.lineWidth = 8;
      ctx.strokeRect(0, 0, w, h);
    };
    draw(null);
    const tex = new THREE.CanvasTexture(canvas);
    tex.colorSpace = THREE.SRGBColorSpace;
    loadKamonImage(info.kamon, kamonColor).then((img) => { draw(img); tex.needsUpdate = true; }).catch(() => {});
    return tex;
  }

  private buildBlock(side: SideKey, info: BattleSideInfo, troops: number, baseX: number, dir: number, stance: Stance): Block {
    const group = new THREE.Group();
    group.position.set(baseX, 0, 0);
    const flagTex = this.flagTexture(info);
    const n = soldiersFor(troops);
    const cloth = mutedColor(info.color, 0.15);

    // 士兵：身（勢力色）、頭（墨）、槍（墨）
    const bodyGeom = new THREE.CylinderGeometry(0.24, 0.34, 1.1, 6);
    bodyGeom.translate(0, 0.55, 0);
    const body = new THREE.InstancedMesh(bodyGeom, inkMaterial(cloth), 64);
    const headGeom = new THREE.SphereGeometry(0.21, 7, 6);
    headGeom.translate(0, 1.3, 0);
    const head = new THREE.InstancedMesh(headGeom, inkMaterial(0x2a2622), 64);
    const spearGeom = new THREE.CylinderGeometry(0.03, 0.03, 2.5, 4);
    spearGeom.translate(0.3, 1.35, 0);
    const spear = new THREE.InstancedMesh(spearGeom, inkMaterial(0x1c1915), 64);
    for (const im of [body, head, spear]) { im.frustumCulled = false; im.count = n; group.add(im); }

    const slots: Slot[] = [];
    for (let i = 0; i < 64; i++) slots.push({ target: new THREE.Vector3(), pos: new THREE.Vector3(), phase: this.rnd() * Math.PI * 2, alive: i < n, fall: 0, kneel: false, row: 0 });

    const label = textSprite(t(`tactic.${stance}`), 1.25, { color: '#1c1915', halo: 'rgba(241,231,208,0.92)' });
    label.position.set(-dir * 1.6, 5.6, 0);
    const telegraph = textSprite(' ', 1.3, { color: '#b23a2c' });
    telegraph.position.set(-dir * 1.6, 8.0, 0);
    telegraph.visible = false;

    // 兵力條 / 士氣條（sprite，從左側伸縮）
    const mkBar = (color: number, h: number, opacity = 1) => {
      const sp = new THREE.Sprite(new THREE.SpriteMaterial({ color, transparent: true, opacity, depthWrite: false, depthTest: false }));
      sp.center.set(0, 0.5);
      sp.scale.set(BAR_W, h, 1);
      sp.renderOrder = 5;
      return sp;
    };
    const hpBg = mkBar(0x1c1915, 0.62, 0.75);
    const hpFill = mkBar(mixColor(info.color, 0xffffff, 0.1), 0.34);
    const moraleFill = mkBar(0xd9a93a, 0.16);
    hpBg.position.set(-dir * 1.6 - BAR_W / 2, 6.9, 0);
    hpFill.position.set(-dir * 1.6 - BAR_W / 2 + 0.08, 6.98, 0.01);
    moraleFill.position.set(-dir * 1.6 - BAR_W / 2 + 0.08, 6.72, 0.01);
    group.add(label, telegraph, hpBg, hpFill, moraleFill);

    const block: Block = {
      side, info, group, baseX, dir, stance, switching: false, retreated: false, routed: false,
      advance: 0, targetAdvance: 0, sideShift: 0, slots, body, head, spear, banners: [], flagTex,
      label, telegraph, telegraphText: '', hpBg, hpFill, moraleFill, volleyTimer: 0, opacity: 1,
    };
    const bannerN = Math.max(1, Math.min(5, Math.round(troops / 3000)));
    for (let i = 0; i < bannerN; i++) block.banners.push(this.makeBanner(block, i));
    return block;
  }

  private makeBanner(block: Block, i: number): Banner {
    const g = new THREE.Group();
    const poleMat = inkMaterial(0x2a2622);
    const pole = new THREE.Mesh(new THREE.CylinderGeometry(0.05, 0.07, 4.2, 6), poleMat);
    pole.position.y = 2.1;
    g.add(pole);
    const flagMat = new THREE.MeshBasicMaterial({ map: block.flagTex, side: THREE.DoubleSide });
    const flagGeom = new THREE.PlaneGeometry(0.9, 1.8);
    flagGeom.translate(block.dir * 0.45, 0, 0);
    const flag = new THREE.Mesh(flagGeom, flagMat);
    flag.position.set(0, 3.2, 0.0);
    flag.rotation.y = (mulberry32(i * 13 + 5)() - 0.5) * 0.4;
    g.add(flag);
    const top = new THREE.Mesh(new THREE.SphereGeometry(0.1, 6, 6), poleMat);
    top.position.y = 4.25;
    g.add(top);
    block.group.add(g);
    return { group: g, mats: [poleMat, flagMat], target: new THREE.Vector3() };
  }

  /** 各陣形的士兵位置（區域座標；x 朝敵方為 dir） */
  private layoutSlots(b: Block): void {
    const d = b.dir;
    const alive = b.slots.filter(s => s.alive && s.fall === 0);
    const n = alive.length;
    alive.forEach((s, i) => {
      s.kneel = false;
      let x = 0, z = 0, row = 0;
      switch (b.stance) {
        case 'charge': {
          // 楔形：1,3,5,7… 由前往後
          let r = 0, first = 0;
          while (first + (2 * r + 1) <= i) { first += 2 * r + 1; r++; }
          const k = i - first;
          row = r;
          x = d * (1.6 - r * 1.0);
          z = (k - r) * 1.05;
          break;
        }
        case 'volley': {
          const cols = Math.ceil(n / 2);
          row = i < cols ? 0 : 1;
          const col = row === 0 ? i : i - cols;
          const c = row === 0 ? cols : n - cols;
          x = d * (1.2 - row * 1.1);
          z = (col - (c - 1) / 2) * 0.8;
          s.kneel = row === 0;
          break;
        }
        case 'maneuver': {
          const cols = 4;
          row = Math.floor(i / cols);
          const col = i % cols;
          x = d * (1.4 - row * 0.95);
          z = (col - 1.5) * 0.9;
          break;
        }
        default: {
          const cols = 6;
          row = Math.floor(i / cols);
          const col = i % cols;
          x = d * (1.0 - row * 0.9);
          z = (col - (Math.min(cols, n) - 1) / 2) * 0.9 + (row % 2 ? 0.25 : -0.25);
        }
      }
      s.row = row;
      s.target.set(x, 0, z);
    });
    // 旗幟：插在幾個士兵之間
    const step = Math.max(1, Math.floor(n / (b.banners.length + 1)));
    b.banners.forEach((bn, i) => {
      const ref = alive[Math.min(n - 1, (i + 1) * step)];
      bn.target.copy(ref ? ref.target : new THREE.Vector3());
      bn.target.x -= d * 0.5;
    });
  }

  private applyFormation(b: Block, instant: boolean): void {
    this.layoutSlots(b);
    if (instant) {
      for (const s of b.slots) s.pos.copy(s.target);
      for (const bn of b.banners) bn.group.position.copy(bn.target);
      b.group.position.x = b.baseX;
    }
  }

  private buildCastle(defense: number): void {
    const g = new THREE.Group();
    const wallH = 1.2 + (defense / 100) * 2.6;
    const wallLen = 16;
    const wallMat = inkMaterial(0xb3ada2);
    const wall = new THREE.Mesh(new THREE.BoxGeometry(1.6, wallH, wallLen), wallMat);
    wall.position.set(0, wallH / 2, 0);
    addOutline(wall, 0.1);
    g.add(wall);
    for (let z = -wallLen / 2 + 0.8; z <= wallLen / 2 - 0.8; z += 1.6) {
      const m = new THREE.Mesh(new THREE.BoxGeometry(1.7, 0.45, 0.8), wallMat);
      m.position.set(0, wallH + 0.22, z);
      g.add(m);
    }
    const stone = new THREE.Mesh(new THREE.BoxGeometry(2.6, 0.5, wallLen + 1.2), inkMaterial(0x7c7670));
    stone.position.set(0.1, 0.25, 0);
    g.add(stone);
    const keepMat = inkMaterial(0xece4cf);
    const roofMat = inkMaterial(0x2a2622);
    const keepBase = wallH * 0.7;
    const keep = new THREE.Mesh(new THREE.BoxGeometry(3.0, 3.2, 3.4), keepMat);
    keep.position.set(2.6, keepBase + 1.6, -4);
    addOutline(keep, 0.1);
    g.add(keep);
    const roof2 = new THREE.Mesh(new THREE.ConeGeometry(2.9, 0.9, 4), roofMat);
    roof2.rotation.y = Math.PI / 4;
    roof2.position.set(2.6, keepBase + 2.0, -4);
    g.add(roof2);
    const upper = new THREE.Mesh(new THREE.BoxGeometry(2.2, 1.8, 2.4), keepMat);
    upper.position.set(2.6, keepBase + 3.2 + 0.9, -4);
    addOutline(upper, 0.08);
    g.add(upper);
    const roof1 = new THREE.Mesh(new THREE.ConeGeometry(2.4, 1.2, 4), roofMat);
    roof1.rotation.y = Math.PI / 4;
    roof1.position.set(2.6, keepBase + 5.0 + 0.6, -4);
    g.add(roof1);
    g.position.set(DEF_X + 2.8, 0, 0);
    g.name = 'castle';
    this.root.add(g);
  }

  private buildMountains(): void {
    const rnd = mulberry32(this.seed + 11);
    const n = 4 + Math.floor(rnd() * 2);
    const mat = inkMaterial(0x9a948a);
    for (let i = 0; i < n; i++) {
      const h = 5 + rnd() * 5;
      const r = 7 + rnd() * 5;
      const geom = new THREE.ConeGeometry(r, h, 5, 1);
      geom.translate(0, h / 2, 0);
      const m = new THREE.Mesh(geom, mat);
      m.position.set(-36 + (i / (n - 1)) * 72 + (rnd() - 0.5) * 10, 0, -50 - rnd() * 14);
      m.rotation.y = rnd() * Math.PI;
      addOutline(m, 0.25);
      this.root.add(m);
    }
  }

  private buildRain(): void {
    const n = 320;
    const pos = new Float32Array(n * 6);
    const rnd = mulberry32(this.seed + 3);
    for (let i = 0; i < n; i++) {
      const x = -32 + rnd() * 64, y = rnd() * 24, z = -24 + rnd() * 40;
      pos.set([x, y, z, x + 0.12, y - 0.8, z], i * 6);
    }
    const geom = new THREE.BufferGeometry();
    geom.setAttribute('position', new THREE.BufferAttribute(pos, 3));
    const lines = new THREE.LineSegments(geom, new THREE.LineBasicMaterial({ color: 0x3b4a5a, transparent: true, opacity: 0.35 }));
    lines.frustumCulled = false;
    this.root.add(lines);
    this.rain = { lines, pos };
  }

  // -------------------------------------------------------------------------
  // 兵力條 / 傷亡
  // -------------------------------------------------------------------------

  private updateBars(b: Block): void {
    if (!this.battle) return;
    const s = this.battle[b.side];
    const hp = Math.max(0, Math.min(1, troopsOf(s) / Math.max(1, s.initial)));
    const morale = Math.max(0, Math.min(1, s.morale / 130));
    b.hpFill.scale.x = Math.max(0.001, (BAR_W - 0.16) * hp);
    b.moraleFill.scale.x = Math.max(0.001, (BAR_W - 0.16) * morale);
  }

  /** 傷亡：前排幾名士兵倒下 + 濺墨 + 飄字 */
  private casualties(b: Block, loss: number): void {
    const r = THREE.MathUtils.clamp(loss / 900, 0.5, 2.4);
    const seed = this.seed + Math.round(loss) + b.dir * 5 + Math.round(this.elapsed * 7);
    const blot = inkBlotMesh(r, seed, INK, 0.75);
    const rnd = mulberry32(seed);
    blot.position.set(b.group.position.x + b.dir * (1.2 + rnd() * 1.2), 0.025, (rnd() - 0.5) * 4);
    this.fx.add(blot);
    const m = blot.material as THREE.MeshBasicMaterial;
    void this.tween.run(700, (tt) => { blot.scale.setScalar(0.2 + 0.8 * tt); m.opacity = 0.75 * (1 - tt * tt); }, ease.out)
      .then(() => { this.fx.remove(blot); disposeObject(blot); });
    // 飄字
    const sp = textSprite(`−${loss.toLocaleString('en-US')}`, 1.15, { color: '#b23a2c', halo: 'rgba(241,231,208,0.95)' });
    sp.position.set(b.group.position.x - b.dir * 2.2 + (rnd() - 0.5), 3.6, 2.0 + rnd());
    this.fx.add(sp);
    const sm = sp.material;
    void this.tween.run(1300, (tt) => { sp.position.y = 4.2 + tt * 2.2; sm.opacity = tt < 0.5 ? 1 : 1 - (tt - 0.5) / 0.5; }, ease.out)
      .then(() => { this.fx.remove(sp); sm.dispose(); });
  }

  /** 讓存活士兵數降到 target：最前排先倒 */
  private cullTo(b: Block, target: number): void {
    let alive = b.slots.filter(s => s.alive && s.fall === 0);
    let excess = alive.length - target;
    if (excess <= 0) return;
    alive.sort((p, q) => p.row - q.row || this.rnd() - 0.5);
    for (let i = 0; i < excess && i < alive.length; i++) alive[i].fall = 0.001;
    this.layoutSlots(b);
  }

  // -------------------------------------------------------------------------
  // 事件動畫
  // -------------------------------------------------------------------------

  private volleyFlash(b: Block, foe: Block): void {
    const rnd = mulberry32(this.seed + 21 + Math.round(this.elapsed * 10));
    const front = b.group.position.x + b.dir * 1.4;
    for (let k = 0; k < 3; k++) {
      const z = (rnd() - 0.5) * 5;
      const flash = new THREE.Mesh(new THREE.CircleGeometry(0.55, 10), new THREE.MeshBasicMaterial({ color: 0xfff3c8, transparent: true, opacity: 1, depthWrite: false }));
      flash.rotateX(-Math.PI / 2);
      flash.position.set(front, 0.8, z);
      const puff = new THREE.Mesh(new THREE.CircleGeometry(0.5, 10), new THREE.MeshBasicMaterial({ color: 0x8a8378, transparent: true, opacity: 0.45, depthWrite: false }));
      puff.rotateX(-Math.PI / 2);
      puff.position.set(front + b.dir * 0.4, 1.1, z);
      this.fx.add(flash, puff);
      const fm = flash.material as THREE.MeshBasicMaterial, pm = puff.material as THREE.MeshBasicMaterial;
      void Promise.all([
        this.tween.run(220, (tt) => { flash.scale.setScalar(0.3 + 1.2 * tt); fm.opacity = 1 - tt; }, ease.out),
        this.tween.run(900, (tt) => { puff.scale.setScalar(0.6 + 2.0 * tt); puff.position.y = 1.1 + tt * 2.2; pm.opacity = 0.45 * (1 - tt); }, ease.out),
      ]).then(() => { this.fx.remove(flash, puff); disposeObject(flash); disposeObject(puff); });
    }
    // 箭矢 / 彈道：飛向敵陣
    const n = 7;
    const geom = new THREE.CylinderGeometry(0.02, 0.02, 0.9, 3);
    geom.rotateZ(Math.PI / 2);
    const arrows = new THREE.InstancedMesh(geom, new THREE.MeshBasicMaterial({ color: INK }), n);
    arrows.frustumCulled = false;
    this.fx.add(arrows);
    const x0 = front, x1 = foe.group.position.x - foe.dir * 1.0;
    const zs = Array.from({ length: n }, () => (rnd() - 0.5) * 5);
    const zt = Array.from({ length: n }, () => (rnd() - 0.5) * 4);
    const delays = Array.from({ length: n }, () => rnd() * 0.25);
    void this.tween.run(700, (tt) => {
      for (let i = 0; i < n; i++) {
        const u = THREE.MathUtils.clamp((tt - delays[i]) / (1 - delays[i]), 0, 1);
        const x = x0 + (x1 - x0) * u;
        const y = 1.0 + Math.sin(u * Math.PI) * 2.6;
        const z = zs[i] + (zt[i] - zs[i]) * u;
        const slope = Math.cos(u * Math.PI) * 2.6 * Math.PI / Math.abs(x1 - x0);
        _e.set(0, 0, Math.atan2(slope * Math.sign(x1 - x0), 1) * Math.sign(x1 - x0));
        _q.setFromEuler(_e);
        _m.compose(_p.set(x, y, z), _q, _s.set(1, 1, 1));
        arrows.setMatrixAt(i, _m);
      }
      arrows.instanceMatrix.needsUpdate = true;
    }, ease.linear).then(() => { this.fx.remove(arrows); arrows.dispose(); });
  }

  private async animFire(target: Block, ok: boolean): Promise<void> {
    const rnd = mulberry32(this.seed + 33 + Math.round(this.elapsed));
    const n = ok ? 11 : 3;
    const items: { m: THREE.Mesh; mat: THREE.MeshBasicMaterial; delay: number; z: number; x: number }[] = [];
    for (let i = 0; i < n; i++) {
      const mat = new THREE.MeshBasicMaterial({ color: mixColor(0xe8762b, 0xc0392b, rnd()), transparent: true, opacity: 0, depthWrite: false, side: THREE.DoubleSide });
      const m = new THREE.Mesh(new THREE.CircleGeometry(0.7 + rnd() * 0.7, 12), mat);
      m.rotateX(-Math.PI / 2);
      const x = target.group.position.x - target.dir * (rnd() * 3.5);
      const z = (rnd() - 0.5) * 6.5;
      m.position.set(x, 0.2, z);
      this.fx.add(m);
      items.push({ m, mat, delay: rnd() * 0.35, z, x });
    }
    const scorch = inkBlotMesh(ok ? 3.6 : 1.4, this.seed + 8, INK, 0);
    scorch.position.set(target.group.position.x - target.dir * 1.2, 0.02, 0);
    this.fx.add(scorch);
    const sm = scorch.material as THREE.MeshBasicMaterial;
    await this.tween.run(ok ? 1800 : 900, (tt) => {
      for (const it of items) {
        const u = THREE.MathUtils.clamp((tt - it.delay) / (1 - it.delay), 0, 1);
        it.m.position.y = 0.2 + u * 5;
        it.m.position.x = it.x + Math.sin(u * 9 + it.z) * 0.4;
        it.m.scale.setScalar(0.5 + u * 1.4);
        it.mat.opacity = u < 0.15 ? u / 0.15 : 1 - (u - 0.15) / 0.85;
      }
      sm.opacity = (ok ? 0.45 : 0.15) * Math.sin(tt * Math.PI);
    }, ease.linear);
    for (const it of items) { this.fx.remove(it.m); disposeObject(it.m); }
    this.fx.remove(scorch);
    disposeObject(scorch);
  }

  private async animDuel(me: Block, foe: Block, meWins: boolean): Promise<void> {
    const a = me.banners[0], d = foe.banners[0];
    if (!a || !d) return;
    const aStart = a.group.position.clone(), dStart = d.group.position.clone();
    const aMeet = new THREE.Vector3(-me.group.position.x - 1.0, 0, 5.5);
    const dMeet = new THREE.Vector3(-foe.group.position.x + 1.0, 0, 5.5);
    a.target.copy(aMeet); d.target.copy(dMeet);
    await this.tween.run(500, (tt) => {
      a.group.position.lerpVectors(aStart, aMeet, tt);
      d.group.position.lerpVectors(dStart, dMeet, tt);
    }, ease.in);
    const clash = inkBlotMesh(1.2, this.seed + 77, INK, 0.9);
    clash.position.set(0, 0.03, 5.5);
    this.fx.add(clash);
    const cm = clash.material as THREE.MeshBasicMaterial;
    await Promise.all([
      this.tween.run(360, (tt) => {
        const k = Math.sin(tt * Math.PI) * 0.9;
        a.group.position.x = aMeet.x - k; d.group.position.x = dMeet.x + k;
        a.group.rotation.z = -0.25 * Math.sin(tt * Math.PI); d.group.rotation.z = 0.25 * Math.sin(tt * Math.PI);
      }, ease.linear),
      this.tween.run(500, (tt) => { clash.scale.setScalar(0.3 + tt * 1.5); cm.opacity = 0.9 * (1 - tt); }, ease.out),
    ]);
    this.fx.remove(clash);
    disposeObject(clash);
    const loser = meWins ? d : a;
    const loserDir = meWins ? foe.dir : me.dir;
    await this.tween.run(400, (tt) => { loser.group.rotation.z = -loserDir * 0.9 * tt; }, ease.out);
    await this.tween.wait(300);
    this.layoutSlots(me); this.layoutSlots(foe);
    await this.tween.run(500, (tt) => {
      a.group.position.lerpVectors(aMeet, a.target, tt);
      d.group.position.lerpVectors(dMeet, d.target, tt);
      loser.group.rotation.z = -loserDir * 0.9 * (1 - tt);
    }, ease.inOut);
    a.group.rotation.z = 0; d.group.rotation.z = 0;
  }

  private async animRally(b: Block): Promise<void> {
    const ring = new THREE.Mesh(new THREE.RingGeometry(3.0, 3.5, 32), new THREE.MeshBasicMaterial({ color: 0xb8923a, transparent: true, opacity: 0, side: THREE.DoubleSide, depthWrite: false }));
    ring.rotateX(-Math.PI / 2);
    ring.position.set(b.group.position.x - b.dir * 1.2, 0.03, 0);
    this.fx.add(ring);
    const rm = ring.material as THREE.MeshBasicMaterial;
    await this.tween.run(900, (tt) => {
      rm.opacity = 0.8 * (1 - tt);
      ring.scale.setScalar(0.6 + 0.9 * tt);
      for (const bn of b.banners) bn.group.position.y = 0.35 * Math.sin(tt * Math.PI * 2) * (1 - tt);
    }, ease.out);
    for (const bn of b.banners) bn.group.position.y = 0;
    this.fx.remove(ring);
    disposeObject(ring);
  }

  private beginRetreat(b: Block): void {
    b.retreated = true;
    b.targetAdvance = -9;
    void this.tween.run(1800, (tt) => this.setBlockOpacity(b, 1 - 0.6 * tt), ease.inOut);
  }

  private beginRout(b: Block): void {
    b.retreated = true;
    b.routed = true;
    b.targetAdvance = -12;
    const rnd = mulberry32(this.seed + 99);
    for (const s of b.slots) { s.target.z += (rnd() - 0.5) * 6; s.target.x -= b.dir * rnd() * 4; }
    void this.tween.run(1600, (tt) => this.setBlockOpacity(b, 1 - 0.75 * tt), ease.out);
  }

  private setBlockOpacity(b: Block, o: number): void {
    b.opacity = o;
    for (const im of [b.body, b.head, b.spear]) { const m = im.material as THREE.Material; m.transparent = true; m.opacity = o; }
    for (const bn of b.banners) for (const m of bn.mats) { const mm = m as THREE.MeshBasicMaterial; mm.transparent = true; mm.opacity = o; }
  }

  // -------------------------------------------------------------------------
  // 每幀
  // -------------------------------------------------------------------------

  private onWindowResize = (): void => this.resize();

  private placeCamera(): void {
    this.camera.position.set(this.camX, Math.sin(this.camPitch) * this.camDist + 1, Math.cos(this.camPitch) * this.camDist);
    this.camera.lookAt(this.camX, 1.8, -1);
  }

  /** 前鋒所在的 world x */
  private frontX(b: Block): number {
    return b.group.position.x + b.dir * FRONT_DEPTH;
  }

  private updateAdvance(me: Block, foe: Block, dt: number): void {
    if (!this.started) return;
    if (me.retreated) {
      me.advance += (me.targetAdvance - me.advance) * Math.min(1, dt * 1.6);
      me.sideShift += (0 - me.sideShift) * Math.min(1, dt * 2);
      return;
    }
    // 兩軍前鋒距離（正值 = 未接觸）
    const gap = (this.frontX(foe) - this.frontX(me)) * me.dir;
    // 不衝鋒時最多走到離中線多遠：野戰雙方都往中場靠；攻城戰守方守在城前不動
    const siegeDef = !!this.battle?.siege && me.side === 'defender';
    const homeLimit = siegeDef ? 0 : Math.abs(me.baseX) - 2.8 - FRONT_DEPTH;
    let target = me.advance;
    const charging = me.stance === 'charge' && !me.switching;
    if (charging) target = me.advance + Math.max(0, gap - 0.4);
    else if (me.stance === 'maneuver' && !me.switching) target = Math.min(me.advance + Math.max(0, gap - 2.0), homeLimit + 2.0);
    else target = Math.min(homeLimit, me.advance + Math.max(0, gap - 1.6));
    if (foe.retreated) target = Math.min(target, me.advance + Math.max(0, gap - 1.5));
    const speed = charging ? 3.0 : 1.4;
    me.advance += (target - me.advance) * Math.min(1, dt * speed);
    const wantShift = me.stance === 'maneuver' && !me.switching ? 4.5 : 0;
    me.sideShift += (wantShift - me.sideShift) * Math.min(1, dt * 1.8);
  }

  private tick = (): void => {
    if (this.disposed) return;
    const now = performance.now();
    const dt = Math.min(0.05, this.clock.getDelta());
    this.elapsed += dt;
    this.tween.update(now);

    if (this.rain) {
      const p = this.rain.pos;
      const fall = 28 * dt;
      for (let i = 0; i < p.length; i += 6) {
        p[i + 1] -= fall; p[i + 4] -= fall;
        if (p[i + 1] < 0) { p[i + 1] += 24; p[i + 4] += 24; }
      }
      (this.rain.lines.geometry.getAttribute('position') as THREE.BufferAttribute).needsUpdate = true;
    }

    const A = this.atk, D = this.def;
    if (A && D) {
      this.updateAdvance(A, D, dt);
      this.updateAdvance(D, A, dt);
      A.group.position.x = A.baseX + A.dir * A.advance;
      D.group.position.x = D.baseX + D.dir * D.advance;
      A.group.position.z = A.sideShift;
      D.group.position.z = -D.sideShift;
      const gap = this.frontX(D) - this.frontX(A);
      this.melee = gap < 1.2 && !A.retreated && !D.retreated;
      // 鏡頭跟著兩軍前鋒的中點
      const focus = THREE.MathUtils.clamp((this.frontX(A) + this.frontX(D)) / 2, -5, 7);
      this.camX += (focus - this.camX) * Math.min(1, dt * 1.5);
      this.placeCamera();
      if (this.melee) {
        this.meleeSplat -= dt;
        if (this.meleeSplat <= 0) {
          this.meleeSplat = 0.35;
          const blot = inkBlotMesh(0.35 + this.rnd() * 0.4, this.seed + Math.round(this.elapsed * 13), INK, 0.6);
          blot.position.set((this.frontX(A) + this.frontX(D)) / 2 + (this.rnd() - 0.5), 0.03 + this.rnd() * 0.8, (this.rnd() - 0.5) * 5 + (A.sideShift - D.sideShift) / 2);
          this.fx.add(blot);
          const m = blot.material as THREE.MeshBasicMaterial;
          void this.tween.run(500, (tt) => { blot.scale.setScalar(0.3 + tt); m.opacity = 0.6 * (1 - tt); }, ease.out).then(() => { this.fx.remove(blot); disposeObject(blot); });
        }
      }
      for (const b of [A, D]) {
        const foe = b === A ? D : A;
        this.updateSoldiers(b, dt, now);
        // 鐵砲：週期性齊射
        if (b.stance === 'volley' && !b.switching && !b.retreated) {
          b.volleyTimer -= dt;
          if (b.volleyTimer <= 0) { b.volleyTimer = 0.9; this.volleyFlash(b, foe); }
        }
      }
    }

    this.renderer.render(this.scene, this.camera);
  };

  private updateSoldiers(b: Block, dt: number, now: number): void {
    const moving = Math.abs(b.targetAdvance - b.advance) > 0.2 || b.stance === 'maneuver' || b.switching || b.retreated;
    const charging = b.stance === 'charge' && !b.switching && !b.retreated;
    const sway = Math.sin(now * 0.003) * 0.06;
    let needLayout = false;
    for (let i = 0; i < b.slots.length; i++) {
      const s = b.slots[i];
      if (!s.alive) { _m.makeScale(0, 0, 0); b.body.setMatrixAt(i, _m); b.head.setMatrixAt(i, _m); b.spear.setMatrixAt(i, _m); continue; }
      if (s.fall > 0) {
        s.fall += dt * 1.6;
        if (s.fall >= 1) { s.alive = false; s.fall = 0; needLayout = true; _m.makeScale(0, 0, 0); b.body.setMatrixAt(i, _m); b.head.setMatrixAt(i, _m); b.spear.setMatrixAt(i, _m); continue; }
      } else {
        // 靠向陣形目標
        s.pos.x += (s.target.x - s.pos.x) * Math.min(1, dt * 3.2);
        s.pos.z += (s.target.z - s.pos.z) * Math.min(1, dt * 3.2);
      }
      const bob = (moving || charging) ? Math.abs(Math.sin(now * 0.012 + s.phase)) * 0.09 : 0;
      let lean = 0, lunge = 0;
      if (charging) lean = -b.dir * 0.25;
      if (this.melee && s.row <= 1 && !b.retreated) lunge = b.dir * Math.max(0, Math.sin(now * 0.02 + s.phase)) * 0.35;
      const fallAng = s.fall > 0 ? ease.out(Math.min(1, s.fall)) * (Math.PI / 2) : 0;
      const yScale = s.kneel ? 0.72 : 1;
      _e.set(0, b.dir > 0 ? 0 : Math.PI, 0);
      _q.setFromEuler(_e);
      // 傾身（繞 z）與倒下（繞 z，朝後方）
      const tilt = new THREE.Quaternion().setFromEuler(new THREE.Euler(0, 0, lean + -b.dir * fallAng));
      _q.multiply(tilt);
      _p.set(s.pos.x + lunge, bob - (s.fall > 0 ? s.fall * 0.3 : 0), s.pos.z);
      _m.compose(_p, _q, _s.set(1, yScale, 1));
      b.body.setMatrixAt(i, _m);
      b.head.setMatrixAt(i, _m);
      // 槍：方陣豎直、突擊前指、鐵砲平舉
      const spearTilt = b.stance === 'charge' ? -b.dir * 1.1 : b.stance === 'volley' ? -b.dir * 1.45 : -b.dir * 0.1;
      const sq = _q.clone().multiply(new THREE.Quaternion().setFromEuler(new THREE.Euler(0, 0, spearTilt)));
      _m.compose(_p, sq, _s.set(1, yScale, 1));
      b.spear.setMatrixAt(i, _m);
    }
    if (needLayout) this.layoutSlots(b);
    b.body.instanceMatrix.needsUpdate = true;
    b.head.instanceMatrix.needsUpdate = true;
    b.spear.instanceMatrix.needsUpdate = true;
    for (let i = 0; i < b.banners.length; i++) {
      const bn = b.banners[i];
      bn.group.position.x += (bn.target.x - bn.group.position.x) * Math.min(1, dt * 3);
      bn.group.position.z += (bn.target.z - bn.group.position.z) * Math.min(1, dt * 3);
      const flag = bn.group.children[1];
      if (flag) flag.rotation.y = sway * (i % 2 ? 1 : -1) + Math.sin(now * 0.002 + i) * 0.08;
    }
  }
}
