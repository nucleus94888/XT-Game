// ===== 戰鬥場景（three.js，水墨風） =====
// 左 = 攻方，右 = 守方。軍隊以家紋旗幟表示；每回合依戰術播放短動畫。

import * as THREE from 'three';
import type { BattleRoundLog, BattleState, Tactic } from '../core/types';
import {
  INK, PAPER_CREAM, Tweener, addOutline, disposeObject, ease, inkBlotMesh, inkMaterial,
  loadKamonImage, makePaperTexture, mixColor, mulberry32, mutedColor,
} from './ink';

export interface BattleSideInfo {
  kamon: string;
  color: number;
  name: string;
}

interface Banner {
  group: THREE.Group;
  mats: THREE.Material[];
  home: THREE.Vector3;
}

interface Block {
  info: BattleSideInfo;
  group: THREE.Group;
  banners: Banner[];
  baseX: number;
  dir: number; // 面向敵方的 x 方向
  flagTex: THREE.CanvasTexture;
  opacity: number;
}

const ATK_X = -9;
const DEF_X = 9;
const ROW_COLS = 4;
const COL_GAP = 1.9;
const ROW_GAP = 1.7;

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

    // 紙地
    const tex = makePaperTexture();
    tex.repeat.set(9, 9);
    const ground = new THREE.Mesh(new THREE.PlaneGeometry(260, 260), new THREE.MeshBasicMaterial({ map: tex }));
    ground.rotateX(-Math.PI / 2);
    ground.position.y = -0.01;
    this.scene.add(ground);

    // 地平線的幾筆淡墨（遠景）
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

  setup(battle: BattleState, atk: BattleSideInfo, def: BattleSideInfo): void {
    this.tween.clear();
    disposeObject(this.root);
    this.root.clear();
    disposeObject(this.fx);
    this.fx.clear();
    this.rain = null;
    this.seed = battle.id.length * 97 + battle.round;

    this.atk = this.buildBlock(atk, bannerCount(sideTroops(battle.attacker)), ATK_X, +1);
    this.def = this.buildBlock(def, bannerCount(sideTroops(battle.defender)), DEF_X, -1);
    this.root.add(this.atk.group, this.def.group);

    if (battle.siege) this.buildCastle(battle.defense);
    if (battle.terrain === 'mountain') this.buildMountains();
    if (battle.weather === 'rain') this.buildRain();
  }

  /** 播放一回合（約 1.6 秒），完成後 resolve。 */
  async playRound(round: BattleRoundLog, battle: BattleState): Promise<void> {
    if (!this.atk || !this.def) return;
    const atk = this.atk, def = this.def;

    await Promise.all([
      this.playTactic(round.atkTactic, atk, def, round.defTactic),
      this.playTactic(round.defTactic, def, atk, round.atkTactic),
    ]);

    // 傷亡：墨漬 + 旗幟減少
    const tasks: Promise<void>[] = [];
    if (round.atkLoss > 0) tasks.push(this.splash(atk, round.atkLoss));
    if (round.defLoss > 0) tasks.push(this.splash(def, round.defLoss));
    tasks.push(this.shrinkTo(atk, bannerCount(sideTroops(battle.attacker))));
    tasks.push(this.shrinkTo(def, bannerCount(sideTroops(battle.defender))));
    await Promise.all(tasks);
  }

  resize(): void {
    const w = Math.max(1, this.container.clientWidth);
    const h = Math.max(1, this.container.clientHeight);
    this.renderer.setSize(w, h, false);
    const aspect = w / h;
    this.camera.aspect = aspect;
    // 讓 x 方向約 ±22 單位在畫面內（直式時拉遠）
    const halfW = aspect < 1 ? 13.5 : 15;
    const vfov = THREE.MathUtils.degToRad(this.camera.fov);
    const hfov = 2 * Math.atan(Math.tan(vfov / 2) * aspect);
    const distW = halfW / Math.tan(hfov / 2);
    const dist = Math.max(30, distW);
    const pitch = THREE.MathUtils.degToRad(aspect < 1 ? 40 : 30);
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

  /** 幟旗（直式）貼圖：勢力色布面 + 家紋（依布色明度選墨色或米色）。 */
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
      // 布紋
      ctx.strokeStyle = 'rgba(0,0,0,0.07)';
      ctx.lineWidth = 2;
      for (let y = 6; y < h; y += 10) {
        ctx.beginPath(); ctx.moveTo(0, y); ctx.lineTo(w, y); ctx.stroke();
      }
      // 上方家紋、下方兩道橫線
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

  private buildBlock(info: BattleSideInfo, count: number, baseX: number, dir: number): Block {
    const group = new THREE.Group();
    group.position.set(baseX, 0, 0);
    const flagTex = this.flagTexture(info);
    const block: Block = { info, group, banners: [], baseX, dir, flagTex, opacity: 1 };
    for (let i = 0; i < count; i++) block.banners.push(this.makeBanner(block, i));
    return block;
  }

  private bannerHome(i: number, dir: number): THREE.Vector3 {
    const row = Math.floor(i / ROW_COLS);
    const col = i % ROW_COLS;
    const rowCount = Math.min(ROW_COLS, 12);
    const z = (col - (rowCount - 1) / 2) * COL_GAP + (row % 2 ? 0.5 : -0.5);
    const x = -dir * row * ROW_GAP;
    return new THREE.Vector3(x, 0, z);
  }

  private makeBanner(block: Block, i: number): Banner {
    const g = new THREE.Group();
    const home = this.bannerHome(i, block.dir);
    g.position.copy(home);

    const poleMat = inkMaterial(0x2a2622);
    const pole = new THREE.Mesh(new THREE.CylinderGeometry(0.05, 0.07, 4.2, 6), poleMat);
    pole.position.y = 2.1;
    g.add(pole);

    // 幟旗：直式長旗，掛在旗桿的敵方側
    const flagMat = new THREE.MeshBasicMaterial({ map: block.flagTex, side: THREE.DoubleSide });
    const flagGeom = new THREE.PlaneGeometry(0.9, 1.8);
    flagGeom.translate(block.dir * 0.45, 0, 0);
    const flag = new THREE.Mesh(flagGeom, flagMat);
    flag.position.set(0, 3.2, 0.0);
    flag.rotation.y = (mulberry32(i * 13 + 5)() - 0.5) * 0.4;
    g.add(flag);

    // 旗桿頂飾
    const top = new THREE.Mesh(new THREE.SphereGeometry(0.1, 6, 6), poleMat);
    top.position.y = 4.25;
    g.add(top);

    // 腳下的小墨影
    const footMat = new THREE.MeshBasicMaterial({ color: INK, transparent: true, opacity: 0.18, depthWrite: false });
    footMat.name = 'foot';
    const foot = new THREE.Mesh(new THREE.CircleGeometry(0.45, 10), footMat);
    foot.rotateX(-Math.PI / 2);
    foot.position.y = 0.01;
    g.add(foot);

    block.group.add(g);
    return { group: g, mats: [poleMat, flagMat, foot.material as THREE.Material], home };
  }

  /** 守方身後的城：正面城牆（沿 x）+ 天守；牆高依城防縮放。 */
  private buildCastle(defense: number): void {
    const g = new THREE.Group();
    const wallH = 1.2 + (defense / 100) * 2.6;
    const wallLen = 13;
    const wallMat = inkMaterial(0xb3ada2);
    const wall = new THREE.Mesh(new THREE.BoxGeometry(wallLen, wallH, 1.6), wallMat);
    wall.position.set(0, wallH / 2, 0);
    addOutline(wall, 0.1);
    g.add(wall);
    // 城垛
    for (let x = -wallLen / 2 + 0.8; x <= wallLen / 2 - 0.8; x += 1.6) {
      const m = new THREE.Mesh(new THREE.BoxGeometry(0.8, 0.45, 1.7), wallMat);
      m.position.set(x, wallH + 0.22, 0);
      g.add(m);
    }
    // 石垣（底座）
    const stone = new THREE.Mesh(new THREE.BoxGeometry(wallLen + 1.2, 0.5, 2.6), inkMaterial(0x7c7670));
    stone.position.set(0, 0.25, 0.1);
    g.add(stone);
    // 天守
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
    g.position.set(DEF_X + 2.5, 0, -8.5);
    g.name = 'castle';
    this.root.add(g);
  }

  /** 遠景的山：矮而遠，像幾筆淡墨。 */
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
  // 戰術動畫
  // -------------------------------------------------------------------------

  private playTactic(tactic: Tactic, me: Block, foe: Block, foeTactic: Tactic): Promise<void> {
    switch (tactic) {
      case 'charge': return this.animCharge(me);
      case 'hold': return this.animHold(me);
      case 'volley': return this.animVolley(me);
      case 'maneuver': return this.animManeuver(me);
      case 'fire': return this.animFire(foe);
      case 'duel':
        // 雙方都單挑時只由攻方播放一次，守方等待
        if (me.dir < 0 && foeTactic === 'duel') return this.tween.wait(1500);
        return this.animDuel(me, foe);
      case 'retreat': return this.animRetreat(me);
      default: return this.tween.wait(900);
    }
  }

  private async animCharge(b: Block): Promise<void> {
    const g = b.group;
    const x0 = b.baseX;
    await this.tween.run(380, (t) => { g.position.x = x0 + b.dir * 2 * t; }, ease.outBack);
    await this.tween.wait(120);
    await this.tween.run(420, (t) => { g.position.x = x0 + b.dir * 2 * (1 - t); }, ease.inOut);
  }

  private async animHold(b: Block): Promise<void> {
    const g = b.group;
    const ring = new THREE.Mesh(
      new THREE.RingGeometry(3.2, 3.8, 32),
      new THREE.MeshBasicMaterial({ color: INK, transparent: true, opacity: 0, side: THREE.DoubleSide, depthWrite: false }),
    );
    ring.rotateX(-Math.PI / 2);
    ring.position.set(b.baseX - b.dir * 1.2, 0.03, 0);
    this.fx.add(ring);
    const rm = ring.material as THREE.MeshBasicMaterial;
    await Promise.all([
      this.tween.run(900, (t) => {
        const s = 1 - 0.12 * Math.sin(t * Math.PI);
        g.scale.set(1, 1, s);
      }, ease.linear),
      (async () => {
        await this.tween.run(220, (t) => { rm.opacity = 0.75 * t; ring.scale.setScalar(0.7 + 0.3 * t); }, ease.out);
        await this.tween.run(500, (t) => { rm.opacity = 0.75 * (1 - t); }, ease.in);
        this.fx.remove(ring);
        disposeObject(ring);
      })(),
    ]);
    g.scale.set(1, 1, 1);
  }

  private async animVolley(b: Block): Promise<void> {
    const rnd = mulberry32(this.seed + 21);
    const one = async (delay: number): Promise<void> => {
      await this.tween.wait(delay);
      const x = b.baseX + b.dir * 3.2;
      const z = (rnd() - 0.5) * 6;
      const flash = new THREE.Mesh(
        new THREE.CircleGeometry(0.9, 14),
        new THREE.MeshBasicMaterial({ color: 0xfff3c8, transparent: true, opacity: 1, depthWrite: false }),
      );
      flash.rotateX(-Math.PI / 2);
      flash.position.set(x, 0.9, z);
      const puff = new THREE.Mesh(
        new THREE.CircleGeometry(0.8, 12),
        new THREE.MeshBasicMaterial({ color: 0x8a8378, transparent: true, opacity: 0.5, depthWrite: false }),
      );
      puff.rotateX(-Math.PI / 2);
      puff.position.set(x + b.dir * 0.4, 1.2, z);
      this.fx.add(flash, puff);
      const fm = flash.material as THREE.MeshBasicMaterial;
      const pm = puff.material as THREE.MeshBasicMaterial;
      await Promise.all([
        this.tween.run(260, (t) => { flash.scale.setScalar(0.3 + 1.2 * t); fm.opacity = 1 - t; }, ease.out),
        this.tween.run(700, (t) => { puff.scale.setScalar(0.6 + 1.6 * t); puff.position.y = 1.2 + t * 1.6; pm.opacity = 0.5 * (1 - t); }, ease.out),
      ]);
      this.fx.remove(flash, puff);
      disposeObject(flash);
      disposeObject(puff);
    };
    // 齊射時隊列微震
    const g = b.group;
    await Promise.all([
      one(0), one(180), one(360),
      this.tween.run(600, (t) => { g.position.x = b.baseX - b.dir * 0.25 * Math.sin(t * Math.PI * 3) * (1 - t); }, ease.linear),
    ]);
    g.position.x = b.baseX;
  }

  private async animManeuver(b: Block): Promise<void> {
    const g = b.group;
    await this.tween.run(1100, (t) => {
      const s = Math.sin(t * Math.PI);
      g.position.z = 4.5 * s;
      g.position.x = b.baseX + b.dir * 1.5 * s;
      g.rotation.y = -b.dir * 0.35 * Math.sin(t * Math.PI * 2);
    }, ease.inOut);
    g.position.set(b.baseX, 0, 0);
    g.rotation.y = 0;
  }

  private async animFire(target: Block): Promise<void> {
    const rnd = mulberry32(this.seed + 33);
    const n = 7;
    const items: { m: THREE.Mesh; mat: THREE.MeshBasicMaterial; delay: number; z: number; x: number }[] = [];
    for (let i = 0; i < n; i++) {
      const mat = new THREE.MeshBasicMaterial({
        color: mixColor(0xe8762b, 0xc0392b, rnd()),
        transparent: true, opacity: 0, depthWrite: false, side: THREE.DoubleSide,
      });
      const m = new THREE.Mesh(new THREE.CircleGeometry(0.7 + rnd() * 0.5, 12), mat);
      m.rotateX(-Math.PI / 2);
      const x = target.baseX - target.dir * (rnd() * 3);
      const z = (rnd() - 0.5) * 6.5;
      m.position.set(x, 0.2, z);
      this.fx.add(m);
      items.push({ m, mat, delay: rnd() * 0.35, z, x });
    }
    // 焦黑墨漬留在地上一下
    const scorch = inkBlotMesh(3.2, this.seed + 8, INK, 0);
    scorch.position.set(target.baseX - target.dir * 1.2, 0.02, 0);
    this.fx.add(scorch);
    const sm = scorch.material as THREE.MeshBasicMaterial;
    await this.tween.run(1200, (t) => {
      for (const it of items) {
        const u = THREE.MathUtils.clamp((t - it.delay) / (1 - it.delay), 0, 1);
        it.m.position.y = 0.2 + u * 4.5;
        it.m.position.x = it.x + Math.sin(u * 9 + it.z) * 0.4;
        const s = 0.5 + u * 1.2;
        it.m.scale.setScalar(s);
        it.mat.opacity = u < 0.15 ? u / 0.15 : 1 - (u - 0.15) / 0.85;
      }
      sm.opacity = 0.35 * Math.sin(t * Math.PI);
    }, ease.linear);
    for (const it of items) { this.fx.remove(it.m); disposeObject(it.m); }
    this.fx.remove(scorch);
    disposeObject(scorch);
  }

  private async animDuel(me: Block, foe: Block): Promise<void> {
    const a = me.banners[0];
    const d = foe.banners[0];
    if (!a || !d) { await this.tween.wait(900); return; }
    const aStart = a.group.position.clone();
    const dStart = d.group.position.clone();
    // 中央點換算到各自 block 的區域座標
    const aMeet = new THREE.Vector3(-me.baseX - 1.0, 0, 0);
    const dMeet = new THREE.Vector3(-foe.baseX + 1.0, 0, 0);
    await this.tween.run(450, (t) => {
      a.group.position.lerpVectors(aStart, aMeet, t);
      d.group.position.lerpVectors(dStart, dMeet, t);
    }, ease.in);
    // 衝撞：彈開
    const clash = inkBlotMesh(1.2, this.seed + 77, INK, 0.9);
    clash.position.set(0, 0.03, 0);
    this.fx.add(clash);
    const cm = clash.material as THREE.MeshBasicMaterial;
    await Promise.all([
      this.tween.run(260, (t) => {
        const k = Math.sin(t * Math.PI) * 0.9;
        a.group.position.x = aMeet.x - k;
        d.group.position.x = dMeet.x + k;
        a.group.rotation.z = -0.25 * Math.sin(t * Math.PI);
        d.group.rotation.z = 0.25 * Math.sin(t * Math.PI);
      }, ease.linear),
      this.tween.run(500, (t) => { clash.scale.setScalar(0.3 + t * 1.5); cm.opacity = 0.9 * (1 - t); }, ease.out),
    ]);
    this.fx.remove(clash);
    disposeObject(clash);
    await this.tween.wait(120);
    await this.tween.run(450, (t) => {
      a.group.position.lerpVectors(aMeet, aStart, t);
      d.group.position.lerpVectors(dMeet, dStart, t);
      a.group.rotation.z = 0;
      d.group.rotation.z = 0;
    }, ease.inOut);
  }

  private async animRetreat(b: Block): Promise<void> {
    const g = b.group;
    const x0 = g.position.x;
    const o0 = b.opacity;
    await this.tween.run(1000, (t) => {
      g.position.x = x0 - b.dir * 3.5 * t;
      this.setBlockOpacity(b, o0 + (0.5 - o0) * t);
    }, ease.inOut);
    b.baseX = g.position.x;
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

  // -------------------------------------------------------------------------
  // 傷亡
  // -------------------------------------------------------------------------

  private async splash(b: Block, loss: number): Promise<void> {
    const r = THREE.MathUtils.clamp(loss / 1200, 0.6, 3.2);
    const blot = inkBlotMesh(r, this.seed + Math.round(loss) + b.dir * 5, INK, 0.85);
    const rnd = mulberry32(this.seed + Math.round(loss));
    blot.position.set(b.baseX + b.dir * (1.5 + rnd() * 1.5), 0.025, (rnd() - 0.5) * 4);
    this.fx.add(blot);
    const m = blot.material as THREE.MeshBasicMaterial;
    await this.tween.run(650, (t) => { blot.scale.setScalar(0.2 + 0.8 * t); m.opacity = 0.85 * (1 - t * t); }, ease.out);
    this.fx.remove(blot);
    disposeObject(blot);
  }

  private async shrinkTo(b: Block, count: number): Promise<void> {
    if (b.banners.length <= count) return;
    const removed = b.banners.splice(count);
    const start = removed.map((bn) => (bn.mats[0] as THREE.MeshBasicMaterial).opacity ?? 1);
    await this.tween.run(500, (t) => {
      removed.forEach((bn, i) => {
        for (const m of bn.mats) {
          const mm = m as THREE.MeshBasicMaterial;
          mm.transparent = true;
          mm.opacity = start[i] * (1 - t);
        }
        bn.group.rotation.z = -b.dir * 0.6 * t;
        bn.group.position.y = -0.3 * t;
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
    this.tween.update(now);

    if (this.rain) {
      const p = this.rain.pos;
      const fall = 28 * dt;
      for (let i = 0; i < p.length; i += 6) {
        p[i + 1] -= fall;
        p[i + 4] -= fall;
        if (p[i + 1] < 0) {
          p[i + 1] += 24;
          p[i + 4] += 24;
        }
      }
      (this.rain.lines.geometry.getAttribute('position') as THREE.BufferAttribute).needsUpdate = true;
    }

    // 旗幟微微飄動
    const sway = Math.sin(now * 0.003) * 0.06;
    for (const b of [this.atk, this.def]) {
      if (!b) continue;
      for (let i = 0; i < b.banners.length; i++) {
        const flag = b.banners[i].group.children[1];
        if (flag) flag.rotation.y = sway * (i % 2 ? 1 : -1) + Math.sin(now * 0.002 + i) * 0.08;
      }
    }

    this.renderer.render(this.scene, this.camera);
  };
}
