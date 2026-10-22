// ===== 戰鬥場景（three.js，水墨風，即時版） =====
// 左 = 攻方，右 = 守方。軍隊以家紋旗幟表示；陣形（突擊 / 方陣 / 鐵砲 / 迂迴）決定旗幟排列與動態，
// 事件（火計、一騎討、鼓舞、撤退、潰敗）以短動畫表現。

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

interface Banner {
  group: THREE.Group;
  mats: THREE.Material[];
  /** 目前陣形下的目標位置（區域座標） */
  target: THREE.Vector3;
}

interface Block {
  side: SideKey;
  info: BattleSideInfo;
  group: THREE.Group;
  banners: Banner[];
  baseX: number;
  dir: number; // 面向敵方的 x 方向
  flagTex: THREE.CanvasTexture;
  opacity: number;
  stance: Stance;
  switching: boolean;
  /** 整個方塊的目標偏移（依陣形） */
  offset: THREE.Vector3;
  label: THREE.Sprite;
  telegraph: THREE.Sprite;
  telegraphText: string;
  volleyTimer: number;
  retreated: boolean;
}

const ATK_X = -9;
const DEF_X = 9;

function bannerCount(troops: number): number {
  return Math.max(2, Math.min(12, Math.round(troops / 1500)));
}

function sideTroops(s: BattleState['attacker']): number {
  return s.troops.ashigaru + s.troops.cavalry + s.troops.gun;
}

function hexStr(c: number): string {
  return '#' + c.toString(16).padStart(6, '0');
}

export class BattleScene {
  private container: HTMLElement;
  private renderer: THREE.WebGLRenderer;
  private scene = new THREE.Scene();
  private camera: THREE.PerspectiveCamera;
  private tween = new Tweener();
  private root = new THREE.Group();     // setup() 建立的一切
  private fx = new THREE.Group();       // 暫時特效
  private atk: Block | null = null;
  private def: Block | null = null;
  private rain: { lines: THREE.LineSegments; pos: Float32Array } | null = null;
  private resizeObs: ResizeObserver | null = null;
  private disposed = false;
  private clock = new THREE.Clock();
  private seed = 1;
  private elapsed = 0;

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

    const hemi = new THREE.HemisphereLight(0xfff6e3, 0x9c8a6c, 1.5);
    this.scene.add(hemi);
    const dir = new THREE.DirectionalLight(0xffffff, 1.5);
    dir.position.set(-20, 40, 30);
    this.scene.add(dir);

    const tex = makePaperTexture();
    tex.repeat.set(9, 9);
    const ground = new THREE.Mesh(new THREE.PlaneGeometry(260, 260), new THREE.MeshBasicMaterial({ map: tex }));
    ground.rotateX(-Math.PI / 2);
    ground.position.y = -0.01;
    this.scene.add(ground);

    const horizon = new THREE.Mesh(
      new THREE.PlaneGeometry(220, 1.2),
      new THREE.MeshBasicMaterial({ color: INK, transparent: true, opacity: 0.08 }),
    );
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
    this.seed = battle.id.length * 97 + battle.round;

    this.atk = this.buildBlock('attacker', atk, bannerCount(sideTroops(battle.attacker)), ATK_X, +1, stances.attacker);
    this.def = this.buildBlock('defender', def, bannerCount(sideTroops(battle.defender)), DEF_X, -1, stances.defender);
    this.root.add(this.atk.group, this.def.group);
    for (const b of [this.atk, this.def]) this.applyFormation(b, true);

    if (battle.siege) this.buildCastle(battle.defense);
    if (battle.terrain === 'mountain') this.buildMountains();
    if (battle.weather === 'rain') this.buildRain();
  }

  /** 改陣：switching = true 表示改陣中（旗幟移動、標籤顯示改陣中） */
  setStance(side: SideKey, stance: Stance, switching: boolean): void {
    const b = this.block(side);
    if (!b) return;
    if (b.stance === stance && b.switching === switching) return;
    b.stance = stance;
    b.switching = switching;
    this.applyFormation(b, false);
    setSpriteText(b.label, switching ? t('battle.rt.stanceLabel.switching') : t(`tactic.${stance}`), 0.9, { color: '#1c1915', halo: 'rgba(241,231,208,0.9)' });
  }

  /** 敵方預告（給玩家看）；stance 為 null 則隱藏 */
  setTelegraph(side: SideKey, stance: Stance | null): void {
    const b = this.block(side);
    if (!b) return;
    const text = stance ? `▶ ${t(`tactic.${stance}`)}` : '';
    if (text === b.telegraphText) return;
    b.telegraphText = text;
    b.telegraph.visible = !!stance;
    if (stance) setSpriteText(b.telegraph, text, 1.1, { color: '#b23a2c', halo: 'rgba(241,231,208,0.95)' });
  }

  /** 事件動畫（不阻塞） */
  showEvent(ev: RtEvent): void {
    const me = this.block(ev.side), foe = this.block(ev.side === 'attacker' ? 'defender' : 'attacker');
    if (!me || !foe) return;
    switch (ev.kind) {
      case 'fire': void this.animFire(foe, !!ev.ok); break;
      case 'duel': void this.animDuel(me, foe, !!ev.ok); break;
      case 'rally': void this.animRally(me); break;
      case 'retreat': void this.animRetreat(me); break;
      case 'rout': if (!me.retreated) void this.animRout(me); break;
      default: break;
    }
  }

  /** 依兵力同步旗幟數量；loss > 0 時濺墨 */
  syncTroops(battle: BattleState, lossA: number, lossD: number): void {
    if (!this.atk || !this.def) return;
    if (lossA > 0) void this.splash(this.atk, lossA);
    if (lossD > 0) void this.splash(this.def, lossD);
    void this.shrinkTo(this.atk, bannerCount(sideTroops(battle.attacker)));
    void this.shrinkTo(this.def, bannerCount(sideTroops(battle.defender)));
  }

  resize(): void {
    const w = Math.max(1, this.container.clientWidth);
    const h = Math.max(1, this.container.clientHeight);
    this.renderer.setSize(w, h, false);
    const aspect = w / h;
    this.camera.aspect = aspect;
    const halfW = aspect < 1 ? 14 : 15.5;
    const vfov = THREE.MathUtils.degToRad(this.camera.fov);
    const hfov = 2 * Math.atan(Math.tan(vfov / 2) * aspect);
    const distW = halfW / Math.tan(hfov / 2);
    const dist = Math.max(30, distW);
    const pitch = THREE.MathUtils.degToRad(aspect < 1 ? 42 : 32);
    this.camera.position.set(0, Math.sin(pitch) * dist + 1, Math.cos(pitch) * dist);
    this.camera.lookAt(0, 1.2, -1);
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

  private buildBlock(side: SideKey, info: BattleSideInfo, count: number, baseX: number, dir: number, stance: Stance): Block {
    const group = new THREE.Group();
    group.position.set(baseX, 0, 0);
    const flagTex = this.flagTexture(info);
    const label = textSprite(t(`tactic.${stance}`), 0.9, { color: '#1c1915', halo: 'rgba(241,231,208,0.9)' });
    label.position.set(0, 5.4, 0);
    const telegraph = textSprite(' ', 1.1, { color: '#b23a2c' });
    telegraph.position.set(0, 6.8, 0);
    telegraph.visible = false;
    group.add(label, telegraph);
    const block: Block = {
      side, info, group, banners: [], baseX, dir, flagTex, opacity: 1, stance, switching: false,
      offset: new THREE.Vector3(), label, telegraph, telegraphText: '', volleyTimer: 0, retreated: false,
    };
    for (let i = 0; i < count; i++) block.banners.push(this.makeBanner(block, i));
    return block;
  }

  /** 各陣形的旗幟排列（區域座標，x 朝敵方為 dir 方向） */
  private formationTarget(b: Block, i: number, n: number): THREE.Vector3 {
    const d = b.dir;
    switch (b.stance) {
      case 'charge': {
        // 楔形：第 0 面旗在最前，之後兩側展開
        const row = Math.floor((Math.sqrt(8 * i + 1) - 1) / 2); // 0,1,1,2,2,2,...
        const first = (row * (row + 1)) / 2;
        const k = i - first;
        const z = (k - row / 2) * 1.6;
        return new THREE.Vector3(d * (2.2 - row * 1.5), 0, z);
      }
      case 'volley': {
        // 兩列橫隊
        const cols = Math.ceil(n / 2);
        const row = i < cols ? 0 : 1;
        const col = row === 0 ? i : i - cols;
        const c = row === 0 ? cols : n - cols;
        const z = (col - (c - 1) / 2) * 1.5;
        return new THREE.Vector3(d * (1.2 - row * 1.4), 0, z);
      }
      case 'maneuver': {
        // 斜向側翼縱隊
        const z = 3.2 + (i % 2 ? 0.8 : -0.8) + Math.floor(i / 2) * 0.1;
        return new THREE.Vector3(d * (1.5 - Math.floor(i / 2) * 1.3), 0, z - Math.floor(i / 2) * 0.35);
      }
      default: {
        // 方陣：3 欄緊密
        const cols = 3;
        const row = Math.floor(i / cols), col = i % cols;
        const z = (col - 1) * 1.5 + (row % 2 ? 0.3 : -0.3);
        return new THREE.Vector3(d * (0.4 - row * 1.3), 0, z);
      }
    }
  }

  private applyFormation(b: Block, instant: boolean): void {
    const n = b.banners.length;
    b.banners.forEach((bn, i) => {
      const tgt = this.formationTarget(b, i, n);
      bn.target.copy(tgt);
      if (instant) bn.group.position.copy(tgt);
    });
    const off = b.stance === 'charge' ? b.dir * 2.0 : b.stance === 'volley' ? b.dir * 0.6 : b.stance === 'maneuver' ? b.dir * 1.0 : 0;
    b.offset.set(off, 0, 0);
    if (instant) b.group.position.x = b.baseX + off;
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
    const footMat = new THREE.MeshBasicMaterial({ color: INK, transparent: true, opacity: 0.18, depthWrite: false });
    footMat.name = 'foot';
    const foot = new THREE.Mesh(new THREE.CircleGeometry(0.45, 10), footMat);
    foot.rotateX(-Math.PI / 2);
    foot.position.y = 0.01;
    g.add(foot);
    block.group.add(g);
    return { group: g, mats: [poleMat, flagMat, foot.material as THREE.Material], target: new THREE.Vector3() };
  }

  private buildCastle(defense: number): void {
    const g = new THREE.Group();
    const wallH = 1.2 + (defense / 100) * 2.6;
    const wallLen = 13;
    const wallMat = inkMaterial(0xb3ada2);
    const wall = new THREE.Mesh(new THREE.BoxGeometry(wallLen, wallH, 1.6), wallMat);
    wall.position.set(0, wallH / 2, 0);
    addOutline(wall, 0.1);
    g.add(wall);
    for (let x = -wallLen / 2 + 0.8; x <= wallLen / 2 - 0.8; x += 1.6) {
      const m = new THREE.Mesh(new THREE.BoxGeometry(0.8, 0.45, 1.7), wallMat);
      m.position.set(x, wallH + 0.22, 0);
      g.add(m);
    }
    const stone = new THREE.Mesh(new THREE.BoxGeometry(wallLen + 1.2, 0.5, 2.6), inkMaterial(0x7c7670));
    stone.position.set(0, 0.25, 0.1);
    g.add(stone);
    const keepMat = inkMaterial(0xece4cf);
    const roofMat = inkMaterial(0x2a2622);
    const keepBase = wallH * 0.7;
    const keep = new THREE.Mesh(new THREE.BoxGeometry(3.4, 3.2, 3.0), keepMat);
    keep.position.set(0.5, keepBase + 1.6, -2.2);
    addOutline(keep, 0.1);
    g.add(keep);
    const roof2 = new THREE.Mesh(new THREE.ConeGeometry(2.9, 0.9, 4), roofMat);
    roof2.rotation.y = Math.PI / 4;
    roof2.position.set(0.5, keepBase + 2.0, -2.2);
    g.add(roof2);
    const upper = new THREE.Mesh(new THREE.BoxGeometry(2.4, 1.8, 2.2), keepMat);
    upper.position.set(0.5, keepBase + 3.2 + 0.9, -2.2);
    addOutline(upper, 0.08);
    g.add(upper);
    const roof1 = new THREE.Mesh(new THREE.ConeGeometry(2.4, 1.2, 4), roofMat);
    roof1.rotation.y = Math.PI / 4;
    roof1.position.set(0.5, keepBase + 5.0 + 0.6, -2.2);
    g.add(roof1);
    g.position.set(DEF_X + 3.5, 0, -8.5);
    g.name = 'castle';
    this.root.add(g);
  }

  private buildMountains(): void {
    const rnd = mulberry32(this.seed + 11);
    const n = 4 + Math.floor(rnd() * 2);
    const mat = inkMaterial(0x8a847a);
    for (let i = 0; i < n; i++) {
      const h = 5 + rnd() * 5;
      const r = 7 + rnd() * 5;
      const geom = new THREE.ConeGeometry(r, h, 4, 1);
      geom.translate(0, h / 2, 0);
      const m = new THREE.Mesh(geom, mat);
      m.position.set(-36 + (i / (n - 1)) * 72 + (rnd() - 0.5) * 10, 0, -46 - rnd() * 14);
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
      const x = -32 + rnd() * 64;
      const y = rnd() * 24;
      const z = -24 + rnd() * 40;
      pos.set([x, y, z, x + 0.12, y - 0.8, z], i * 6);
    }
    const geom = new THREE.BufferGeometry();
    geom.setAttribute('position', new THREE.BufferAttribute(pos, 3));
    const mat = new THREE.LineBasicMaterial({ color: 0x3b4a5a, transparent: true, opacity: 0.35 });
    const lines = new THREE.LineSegments(geom, mat);
    lines.frustumCulled = false;
    this.root.add(lines);
    this.rain = { lines, pos };
  }

  // -------------------------------------------------------------------------
  // 事件動畫
  // -------------------------------------------------------------------------

  private volleyFlash(b: Block): void {
    const rnd = mulberry32(this.seed + 21 + Math.round(this.elapsed * 10));
    for (let k = 0; k < 2; k++) {
      const x = b.offset.x + b.dir * 2.2;
      const z = (rnd() - 0.5) * 6;
      const flash = new THREE.Mesh(new THREE.CircleGeometry(0.7, 12), new THREE.MeshBasicMaterial({ color: 0xfff3c8, transparent: true, opacity: 1, depthWrite: false }));
      flash.rotateX(-Math.PI / 2);
      flash.position.set(b.baseX + x, 0.9, z);
      const puff = new THREE.Mesh(new THREE.CircleGeometry(0.6, 10), new THREE.MeshBasicMaterial({ color: 0x8a8378, transparent: true, opacity: 0.45, depthWrite: false }));
      puff.rotateX(-Math.PI / 2);
      puff.position.set(b.baseX + x + b.dir * 0.4, 1.2, z);
      this.fx.add(flash, puff);
      const fm = flash.material as THREE.MeshBasicMaterial, pm = puff.material as THREE.MeshBasicMaterial;
      void Promise.all([
        this.tween.run(240, (tt) => { flash.scale.setScalar(0.3 + 1.2 * tt); fm.opacity = 1 - tt; }, ease.out),
        this.tween.run(650, (tt) => { puff.scale.setScalar(0.6 + 1.6 * tt); puff.position.y = 1.2 + tt * 1.6; pm.opacity = 0.45 * (1 - tt); }, ease.out),
      ]).then(() => { this.fx.remove(flash, puff); disposeObject(flash); disposeObject(puff); });
    }
  }

  private async animFire(target: Block, ok: boolean): Promise<void> {
    const rnd = mulberry32(this.seed + 33 + Math.round(this.elapsed));
    const n = ok ? 9 : 3;
    const items: { m: THREE.Mesh; mat: THREE.MeshBasicMaterial; delay: number; z: number; x: number }[] = [];
    for (let i = 0; i < n; i++) {
      const mat = new THREE.MeshBasicMaterial({ color: mixColor(0xe8762b, 0xc0392b, rnd()), transparent: true, opacity: 0, depthWrite: false, side: THREE.DoubleSide });
      const m = new THREE.Mesh(new THREE.CircleGeometry(0.7 + rnd() * 0.6, 12), mat);
      m.rotateX(-Math.PI / 2);
      const x = target.group.position.x - target.dir * (rnd() * 3);
      const z = (rnd() - 0.5) * 6.5;
      m.position.set(x, 0.2, z);
      this.fx.add(m);
      items.push({ m, mat, delay: rnd() * 0.35, z, x });
    }
    const scorch = inkBlotMesh(ok ? 3.4 : 1.4, this.seed + 8, INK, 0);
    scorch.position.set(target.group.position.x - target.dir * 1.2, 0.02, 0);
    this.fx.add(scorch);
    const sm = scorch.material as THREE.MeshBasicMaterial;
    await this.tween.run(ok ? 1600 : 900, (tt) => {
      for (const it of items) {
        const u = THREE.MathUtils.clamp((tt - it.delay) / (1 - it.delay), 0, 1);
        it.m.position.y = 0.2 + u * 4.5;
        it.m.position.x = it.x + Math.sin(u * 9 + it.z) * 0.4;
        it.m.scale.setScalar(0.5 + u * 1.2);
        it.mat.opacity = u < 0.15 ? u / 0.15 : 1 - (u - 0.15) / 0.85;
      }
      sm.opacity = (ok ? 0.4 : 0.15) * Math.sin(tt * Math.PI);
    }, ease.linear);
    for (const it of items) { this.fx.remove(it.m); disposeObject(it.m); }
    this.fx.remove(scorch);
    disposeObject(scorch);
  }

  private async animDuel(me: Block, foe: Block, meWins: boolean): Promise<void> {
    const a = me.banners[0], d = foe.banners[0];
    if (!a || !d) return;
    const aStart = a.group.position.clone(), dStart = d.group.position.clone();
    const aMeet = new THREE.Vector3(-me.group.position.x - 1.0, 0, 0);
    const dMeet = new THREE.Vector3(-foe.group.position.x + 1.0, 0, 0);
    await this.tween.run(450, (tt) => {
      a.group.position.lerpVectors(aStart, aMeet, tt);
      d.group.position.lerpVectors(dStart, dMeet, tt);
    }, ease.in);
    const clash = inkBlotMesh(1.2, this.seed + 77, INK, 0.9);
    clash.position.set(0, 0.03, 0);
    this.fx.add(clash);
    const cm = clash.material as THREE.MeshBasicMaterial;
    await Promise.all([
      this.tween.run(320, (tt) => {
        const k = Math.sin(tt * Math.PI) * 0.9;
        a.group.position.x = aMeet.x - k; d.group.position.x = dMeet.x + k;
        a.group.rotation.z = -0.25 * Math.sin(tt * Math.PI); d.group.rotation.z = 0.25 * Math.sin(tt * Math.PI);
      }, ease.linear),
      this.tween.run(500, (tt) => { clash.scale.setScalar(0.3 + tt * 1.5); cm.opacity = 0.9 * (1 - tt); }, ease.out),
    ]);
    this.fx.remove(clash);
    disposeObject(clash);
    // 敗者倒旗
    const loser = meWins ? d : a;
    const loserDir = meWins ? foe.dir : me.dir;
    await this.tween.run(380, (tt) => { loser.group.rotation.z = -loserDir * 0.9 * tt; }, ease.out);
    await this.tween.wait(200);
    await this.tween.run(450, (tt) => {
      a.group.position.lerpVectors(aMeet, aStart, tt);
      d.group.position.lerpVectors(dMeet, dStart, tt);
      loser.group.rotation.z = -loserDir * 0.9 * (1 - tt);
    }, ease.inOut);
    a.group.rotation.z = 0; d.group.rotation.z = 0;
  }

  private async animRally(b: Block): Promise<void> {
    const ring = new THREE.Mesh(
      new THREE.RingGeometry(3.0, 3.5, 32),
      new THREE.MeshBasicMaterial({ color: 0xb8923a, transparent: true, opacity: 0, side: THREE.DoubleSide, depthWrite: false }),
    );
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

  private async animRetreat(b: Block): Promise<void> {
    b.retreated = true;
    const x0 = b.group.position.x;
    b.offset.x -= b.dir * 6;
    await this.tween.run(1800, (tt) => {
      b.group.position.x = x0 - b.dir * 6 * tt;
      this.setBlockOpacity(b, 1 - 0.6 * tt);
    }, ease.inOut);
  }

  private async animRout(b: Block): Promise<void> {
    b.retreated = true;
    const starts = b.banners.map((bn) => bn.group.position.clone());
    const rnd = mulberry32(this.seed + 99);
    const dirs = b.banners.map(() => new THREE.Vector3(-b.dir * (3 + rnd() * 3), 0, (rnd() - 0.5) * 6));
    await this.tween.run(1400, (tt) => {
      b.banners.forEach((bn, i) => {
        bn.group.position.copy(starts[i]).addScaledVector(dirs[i], tt);
        bn.group.rotation.z = -b.dir * 0.5 * tt * (i % 2 ? 1 : 0.4);
      });
      this.setBlockOpacity(b, 1 - 0.7 * tt);
    }, ease.out);
  }

  private setBlockOpacity(b: Block, o: number): void {
    b.opacity = o;
    for (const bn of b.banners) {
      for (const m of bn.mats) {
        const mm = m as THREE.MeshBasicMaterial;
        if (mm.name === 'foot') continue;
        mm.transparent = true;
        mm.opacity = o;
      }
    }
  }

  private async splash(b: Block, loss: number): Promise<void> {
    const r = THREE.MathUtils.clamp(loss / 900, 0.5, 2.6);
    const seed = this.seed + Math.round(loss) + b.dir * 5 + Math.round(this.elapsed * 7);
    const blot = inkBlotMesh(r, seed, INK, 0.8);
    const rnd = mulberry32(seed);
    blot.position.set(b.group.position.x + b.dir * (1.0 + rnd() * 1.5), 0.025, (rnd() - 0.5) * 4);
    this.fx.add(blot);
    const m = blot.material as THREE.MeshBasicMaterial;
    await this.tween.run(650, (tt) => { blot.scale.setScalar(0.2 + 0.8 * tt); m.opacity = 0.8 * (1 - tt * tt); }, ease.out);
    this.fx.remove(blot);
    disposeObject(blot);
  }

  private async shrinkTo(b: Block, count: number): Promise<void> {
    if (b.banners.length <= count || b.retreated) return;
    const removed = b.banners.splice(count);
    const start = removed.map((bn) => (bn.mats[0] as THREE.MeshBasicMaterial).opacity ?? 1);
    this.applyFormation(b, false);
    await this.tween.run(500, (tt) => {
      removed.forEach((bn, i) => {
        for (const m of bn.mats) {
          const mm = m as THREE.MeshBasicMaterial;
          mm.transparent = true;
          mm.opacity = start[i] * (1 - tt);
        }
        bn.group.rotation.z = -b.dir * 0.6 * tt;
        bn.group.position.y = -0.3 * tt;
      });
    }, ease.in);
    for (const bn of removed) {
      b.group.remove(bn.group);
      disposeObject(bn.group);
    }
  }

  // -------------------------------------------------------------------------
  // 每幀
  // -------------------------------------------------------------------------

  private onWindowResize = (): void => this.resize();

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

    const sway = Math.sin(now * 0.003) * 0.06;
    for (const b of [this.atk, this.def]) {
      if (!b) continue;
      // 方塊整體往目標偏移靠攏；突擊時前後擺動、迂迴時左右游移
      let tx = b.baseX + b.offset.x, tz = 0;
      if (!b.retreated) {
        if (b.stance === 'charge' && !b.switching) tx += b.dir * Math.max(0, Math.sin(this.elapsed * 3.2)) * 1.1;
        if (b.stance === 'maneuver' && !b.switching) tz = Math.sin(this.elapsed * 1.3) * 1.2;
      }
      b.group.position.x += (tx - b.group.position.x) * Math.min(1, dt * 4);
      b.group.position.z += (tz - b.group.position.z) * Math.min(1, dt * 3);
      // 旗幟靠向陣形目標位置
      for (let i = 0; i < b.banners.length; i++) {
        const bn = b.banners[i];
        if (!b.retreated) {
          bn.group.position.x += (bn.target.x - bn.group.position.x) * Math.min(1, dt * 3.5);
          bn.group.position.z += (bn.target.z - bn.group.position.z) * Math.min(1, dt * 3.5);
        }
        const flag = bn.group.children[1];
        if (flag) flag.rotation.y = sway * (i % 2 ? 1 : -1) + Math.sin(now * 0.002 + i) * 0.08;
      }
      // 鐵砲：週期性齊射閃光
      if (b.stance === 'volley' && !b.switching && !b.retreated) {
        b.volleyTimer -= dt;
        if (b.volleyTimer <= 0) { b.volleyTimer = 0.75; this.volleyFlash(b); }
      }
      // 標籤跟著方塊
      b.label.position.set(0, 5.4, 0);
      b.telegraph.position.set(0, 6.6, 0);
    }

    this.renderer.render(this.scene, this.camera);
  };
}
