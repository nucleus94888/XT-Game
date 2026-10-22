// 戰鬥畫面（即時版）：布陣 → 30〜40 秒即時指揮 → 結果
import type { App } from './App';
import type { BattleState } from '../core/types';
import {
  STANCES, type Stance, type SideKey, type RtBattle, type RtEvent,
  createRtBattle, rtStep, rtSetStance, rtFire, rtDuel, rtRally, rtRetreat, rtAutoResolve,
  canStance, canFire, canDuel, canRetreat, visibleTelegraph, matchup, SWITCH_TIME,
} from '../systems/rtbattle';
import { attemptOkehazama } from '../systems/events';
import { rngOf, saveRng, totalTroops, officerDef } from '../core/state';
import { FACTION_MAP } from '../data/factions';
import { kamonDataUrl, type KamonId } from '../data/kamon';
import { t, officerName } from '../i18n';
import { h, clear, fmt, bar, modal } from './dom';
import { BattleScene } from '../render/BattleScene';
import type { Rng } from '../core/rng';

export interface BattleViewOptions {
  /** 教學：只開放這些陣形 */
  allowedStances?: Stance[];
  /** 教學：隱藏技能列 */
  noSkills?: boolean;
  /** 布陣畫面額外說明（i18n key） */
  introKey?: string;
  /** 不允許委任 */
  noDelegate?: boolean;
}

export class BattleView {
  private root: HTMLElement;
  private sceneEl: HTMLElement;
  private panel: HTMLElement;
  private hud: HTMLElement;
  private scene: BattleScene;
  private mySide: SideKey;
  private rt: RtBattle | null = null;
  private auto = false;
  private raf = 0;
  private lastFrame = 0;
  private lastDom = 0;
  private eventIdx = 0;
  private notes: string[] = [];
  private lossShown: Record<SideKey, number> = { attacker: 0, defender: 0 };
  private sceneStance: Record<SideKey, { stance: Stance; switching: boolean } | null> = { attacker: null, defender: null };
  private opts: BattleViewOptions;
  private rng: Rng | null = null;
  private overlayMatchup: HTMLElement;
  private overlayAnn: HTMLElement;
  private matchupKey = '';

  private announce(text: string, cls = ''): void {
    const el = h('div', { class: `announce ${cls}` }, text);
    this.overlayAnn.appendChild(el);
    setTimeout(() => el.remove(), 1900);
  }

  constructor(private app: App, private b: BattleState, opts: BattleViewOptions = {}) {
    this.opts = opts;
    const s = app.state!;
    this.mySide = b.attacker.faction === s.player ? 'attacker' : 'defender';
    this.hud = h('div', { class: 'bhud' });
    this.sceneEl = h('div', { class: 'scene' });
    this.overlayMatchup = h('div', { class: 'matchup' });
    this.overlayAnn = h('div', { class: 'announce-layer' });
    this.sceneEl.append(this.overlayMatchup, this.overlayAnn);
    this.panel = h('div', { class: 'bpanel' });
    this.root = h('div', { id: 'battle' }, this.hud, this.sceneEl, this.panel);
    document.body.appendChild(this.root);
    this.scene = new BattleScene(this.sceneEl);
  }

  private get foeSide(): SideKey { return this.mySide === 'attacker' ? 'defender' : 'attacker'; }

  private info(side: SideKey) {
    const f = FACTION_MAP[this.b[side].faction];
    return { kamon: f.kamon, color: f.color, name: t(`faction.${f.id}`) };
  }

  async run(): Promise<void> {
    const b = this.b;
    this.renderHud();
    this.scene.setup(b, this.info('attacker'), this.info('defender'), { attacker: 'hold', defender: 'hold' });
    // 桶狹間：開戰前的奇襲選擇
    if (b.special === 'okehazama' && this.mySide === 'defender') {
      const r = await modal(t('battle.okehazama.title'), t('battle.okehazama.desc', { rain: b.weather === 'rain' ? t('battle.okehazama.rain') : '' }), [t('battle.okehazama.go'), t('battle.okehazama.no')]);
      if (r === 0) {
        const rng = rngOf(this.app.state!);
        const ok = attemptOkehazama(this.app.state!, b, rng);
        saveRng(this.app.state!, rng);
        this.notes.push(ok ? 'battle.note.okehazamaWin' : 'battle.note.okehazamaFail');
        this.renderHud();
      } else b.special = undefined;
    }
    const start = await this.prepare();
    if (start === 'delegate') {
      const rng = rngOf(this.app.state!);
      rtAutoResolve(b, rng);
      saveRng(this.app.state!, rng);
      this.scene.setup(b, this.info('attacker'), this.info('defender'), { attacker: 'hold', defender: 'hold' });
      this.renderHud();
    } else {
      await this.fight(start);
    }
    await this.showResult();
    this.scene.dispose();
    this.root.remove();
  }

  // ===== 布陣 =====
  private prepare(): Promise<Stance | 'delegate'> {
    return new Promise(resolve => {
      const b = this.b; const me = b[this.mySide];
      const defaultStance: Stance = this.mySide === 'attacker' ? 'charge' : 'hold';
      let chosen: Stance = this.opts.allowedStances?.[0] ?? defaultStance;
      this.scene.setup(b, this.info('attacker'), this.info('defender'), {
        attacker: this.mySide === 'attacker' ? chosen : 'hold', defender: this.mySide === 'defender' ? chosen : 'hold',
      });
      clear(this.panel);
      const grid = h('div', { class: 'stance-grid' });
      const render = () => {
        clear(grid);
        for (const st of STANCES) {
          const can = canStance(b, me, st);
          const allowed = !this.opts.allowedStances || this.opts.allowedStances.includes(st);
          grid.appendChild(h('button', {
            class: `stance ${st === chosen ? 'active' : ''}`, disabled: !can.ok || !allowed,
            onClick: () => { chosen = st; this.scene.setStance(this.mySide, st, false); render(); },
          }, h('div', { class: 't-name' }, t(`tactic.${st}`)), h('div', { class: 't-desc' }, can.ok ? t(`tactic.${st}.desc`) : t(can.reason!))));
        }
      };
      render();
      const cmd = me.commander ? officerDef(me.commander) : null;
      this.panel.append(
        h('div', { class: 'modal-title' }, t('battle.rt.prepTitle')),
        h('div', { class: 'sides' }, this.sideBox(b.attacker), this.sideBox(b.defender)),
        h('div', { class: 'small muted' }, `${t('battle.commander')}：${me.commander ? officerName(me.commander) : '-'}${cmd ? `（${t('stat.lead')}${cmd.lead} ${t('stat.valor')}${cmd.valor} ${t('stat.intel')}${cmd.intel}）` : ''}`),
        h('div', { class: 'hint' }, t(this.opts.introKey ?? 'battle.rt.howto'), h('br'), t('battle.rt.counter')),
        h('div', { class: 'row between' }, h('b', null, t('battle.rt.chooseStart'))),
        grid,
        h('div', { class: 'row', style: { marginTop: '8px' } },
          h('button', { class: 'btn primary', style: { flex: '2' }, onClick: () => resolve(chosen) }, t('battle.rt.start')),
          this.opts.noDelegate ? null : h('button', { class: 'btn', style: { flex: '1' }, onClick: () => resolve('delegate') }, t('battle.rt.delegate')),
        ),
      );
    });
  }

  // ===== 即時戰鬥 =====
  private fight(startStance: Stance): Promise<void> {
    return new Promise(resolve => {
      const b = this.b;
      const rng = rngOf(this.app.state!);
      this.rng = rng;
      this.rt = createRtBattle(b, rng, { playerSide: this.mySide, playerStance: startStance });
      this.scene.setup(b, this.info('attacker'), this.info('defender'), { attacker: this.rt.sides.attacker.stance, defender: this.rt.sides.defender.stance });
      this.sceneStance = { attacker: { stance: this.rt.sides.attacker.stance, switching: false }, defender: { stance: this.rt.sides.defender.stance, switching: false } };
      this.renderControls();
      this.scene.begin();
      this.announce(t('battle.rt.begin'), 'red');
      this.lastFrame = performance.now();
      let endAt = 0;
      const loop = (now: number) => {
        const rt = this.rt!;
        const dt = Math.min(0.05, (now - this.lastFrame) / 1000);
        this.lastFrame = now;
        if (!rt.over) {
          rtStep(rt, dt, rng, this.auto ? ['attacker', 'defender'] : [this.foeSide]);
          this.syncScene();
          if (now - this.lastDom > 100) { this.lastDom = now; this.renderHud(); this.renderControls(); }
          if (rt.over) { endAt = now + 1500; this.renderHud(); this.renderControls(); saveRng(this.app.state!, rng); }
        } else if (now >= endAt) { resolve(); return; }
        this.raf = requestAnimationFrame(loop);
      };
      this.raf = requestAnimationFrame(loop);
    });
  }

  private syncScene(): void {
    const rt = this.rt!;
    for (const side of ['attacker', 'defender'] as SideKey[]) {
      const st = rt.sides[side];
      const stance = st.pending ?? st.stance;
      const switching = st.switching > 0;
      const prev = this.sceneStance[side];
      if (!prev || prev.stance !== stance || prev.switching !== switching) {
        this.scene.setStance(side, stance, switching);
        this.sceneStance[side] = { stance, switching };
      }
    }
    // 敵方預告（依智謀可見）
    this.scene.setTelegraph(this.foeSide, this.auto ? null : visibleTelegraph(rt, this.mySide));
    this.scene.setTelegraph(this.mySide, null);
    // 畫面上方的優劣指示
    const m = matchup(rt.sides[this.mySide].stance, rt.sides[this.foeSide].stance);
    const sw = rt.sides[this.mySide].switching > 0;
    const key = rt.over ? '' : sw ? 'sw' : m > 1.2 ? 'adv' : m < 0.8 ? 'dis' : 'even';
    if (key !== this.matchupKey) {
      this.matchupKey = key;
      this.overlayMatchup.className = `matchup ${key}`;
      this.overlayMatchup.textContent = key === '' ? '' : key === 'sw' ? t('battle.rt.stanceLabel.switching') : t(`battle.rt.matchup.${key}`);
    }
    // 事件
    while (this.eventIdx < rt.events.length) {
      const ev = rt.events[this.eventIdx++];
      this.scene.showEvent(ev);
      if (ev.note) { this.notes.push(ev.note); if (ev.kind !== 'switch') this.announce(t(ev.note), ev.ok === false || ev.kind === 'rout' ? 'red' : ''); }
      else if (ev.kind === 'rally') { this.notes.push(`@rally:${ev.side}`); this.announce(t('battle.rt.rally'), 'gold'); }
    }
    // 傷亡：每累積一定損失濺一次墨
    const lossA = rt.stats.attacker.loss - this.lossShown.attacker, lossD = rt.stats.defender.loss - this.lossShown.defender;
    const thA = Math.max(150, totalTroops(rt.b.attacker) * 0.04), thD = Math.max(150, totalTroops(rt.b.defender) * 0.04);
    const showA = lossA >= thA || rt.over ? lossA : 0, showD = lossD >= thD || rt.over ? lossD : 0;
    if (showA) this.lossShown.attacker += showA;
    if (showD) this.lossShown.defender += showD;
    this.scene.syncTroops(rt.b, showA, showD);
  }

  private renderHud(): void {
    const b = this.b;
    clear(this.hud);
    const side = (x: typeof b.attacker, label: string) => h('div', { class: 'side' },
      h('img', { src: kamonDataUrl(FACTION_MAP[x.faction].kamon as KamonId) }),
      h('div', null, h('div', null, `${label} ${t(`faction.${x.faction}`)}`), h('div', { class: 'small' }, `${fmt(totalTroops(x))} ・ ${t('stat.morale')} ${Math.round(x.morale)}`)));
    const rt = this.rt;
    const mid = rt && !rt.over
      ? h('div', { class: 'small' }, t('battle.rt.timeLeft', { s: Math.max(0, Math.ceil(rt.duration - rt.time)) }))
      : h('div', { class: 'small' }, `${t(`battle.weather.${b.weather}`)} ・ ${t(`terrain.${b.terrain}`)} ・ ${b.siege ? t('battle.siege') : t('battle.field')}`);
    this.hud.append(side(b.attacker, t('battle.attacker')),
      h('div', { style: { textAlign: 'center' } }, h('div', null, t('battle.title', { region: b.region })), mid),
      side(b.defender, t('battle.defender')));
  }

  private sideBox(x: typeof this.b.attacker): HTMLElement {
    return h('div', { class: 's' },
      h('div', null, t(`faction.${x.faction}`), ' ', h('span', { class: 'n' }, fmt(totalTroops(x)))),
      h('div', { class: 'muted' }, `${t('stat.ashigaru')} ${fmt(x.troops.ashigaru)} ${t('stat.cavalry')} ${fmt(x.troops.cavalry)} ${t('stat.gun')} ${fmt(x.troops.gun)}`),
      h('div', null, `${t('stat.morale')} ${Math.round(x.morale)}`), bar(x.morale, 130, x.morale < 40 ? 'red' : 'green'),
    );
  }

  private renderControls(): void {
    const rt = this.rt!; const b = this.b;
    const me = b[this.mySide]; const myRt = rt.sides[this.mySide]; const foeRt = rt.sides[this.foeSide];
    const rng = this.rng ?? rngOf(this.app.state!);
    clear(this.panel);

    // 時間條 + 敵情
    const remain = Math.max(0, rt.duration - rt.time);
    const tg = this.auto ? null : visibleTelegraph(rt, this.mySide);
    const foeStance = foeRt.pending ?? foeRt.stance;
    this.panel.append(
      h('div', { class: 'timer' }, h('div', { class: 'timer-fill', style: { width: `${remain / rt.duration * 100}%` } })),
      h('div', { class: 'row between small' },
        h('span', null, t('battle.rt.enemyStance', { stance: `tactic:${foeStance}` }), foeRt.switching > 0 ? ` (${t('battle.rt.stanceLabel.switching')})` : ''),
        tg ? h('span', { class: 'telegraph' }, t('battle.rt.enemyPrep', { stance: `tactic:${tg}` })) : (remain < 8 && this.mySide === 'attacker' && !rt.over ? h('span', { class: 'telegraph' }, t('battle.rt.timeoutWarn')) : null)),
      h('div', { class: 'sides' }, this.sideBox(b.attacker), this.sideBox(b.defender)),
    );

    // 陣形
    const grid = h('div', { class: 'stance-grid' });
    const cur = myRt.pending ?? myRt.stance;
    for (const st of STANCES) {
      const can = canStance(b, me, st);
      const allowed = !this.opts.allowedStances || this.opts.allowedStances.includes(st);
      const m = matchup(st, foeStance);
      const rel = m > 1.2 ? h('span', { class: 'tag adv' }, `▲ ${t('battle.rt.adv')}`) : m < 0.8 ? h('span', { class: 'tag dis' }, `▼ ${t('battle.rt.dis')}`) : null;
      const active = st === cur;
      grid.appendChild(h('button', {
        class: `stance ${active ? 'active' : ''} ${myRt.switching > 0 && active ? 'switching' : ''}`,
        disabled: !can.ok || !allowed || rt.over || this.auto || myRt.retreating > 0,
        onClick: () => { if (rtSetStance(rt, this.mySide, st)) this.renderControls(); },
      }, h('div', { class: 't-name' }, t(`tactic.${st}`)), rel, h('div', { class: 't-desc' }, can.ok ? (active && myRt.switching > 0 ? t('battle.rt.switching') : t(`tactic.${st}.desc`)) : t(can.reason!))));
    }
    this.panel.append(h('div', { class: 'row between' }, h('b', null, t('battle.rt.myStance')), h('span', { class: 'small muted' }, t('battle.rt.switchCost', { s: SWITCH_TIME }))), grid);

    // 技能
    if (!this.opts.noSkills) {
      const row = h('div', { class: 'skill-row' });
      const fire = canFire(rt, this.mySide), duel = canDuel(rt, this.mySide), ret = canRetreat(rt, this.mySide);
      const busy = rt.over || this.auto || myRt.retreating > 0;
      row.append(
        h('button', { class: 'btn skill', disabled: busy || !fire.ok, title: fire.ok ? '' : t(fire.reason!), onClick: () => { rtFire(rt, this.mySide, rng); saveRng(this.app.state!, rng); this.renderControls(); } },
          h('b', null, t('battle.rt.fire')), h('span', { class: 'small' }, fire.ok ? t('battle.rt.fire.desc') : t(fire.reason!))),
        h('button', { class: 'btn skill', disabled: busy || !duel.ok, onClick: () => { rtDuel(rt, this.mySide, rng); saveRng(this.app.state!, rng); this.renderControls(); } },
          h('b', null, t('battle.rt.duel')), h('span', { class: 'small' }, duel.ok ? t('battle.rt.duel.desc') : t(duel.reason!))),
        h('button', { class: 'btn skill', disabled: busy || myRt.rallyCd > 0, onClick: () => { rtRally(rt, this.mySide); this.renderControls(); } },
          h('b', null, myRt.rallyCd > 0 ? t('battle.rt.rallyCd', { s: Math.ceil(myRt.rallyCd) }) : t('battle.rt.rally')), h('span', { class: 'small' }, t('battle.rt.rally.desc'))),
        h('button', { class: 'btn skill danger', disabled: busy || !ret.ok, onClick: async () => {
          const r = await modal(t('battle.rt.retreat'), t('battle.rt.retreatConfirm'), [t('battle.rt.retreat'), t('app.cancel')], { danger: 0 });
          if (r === 0) { rtRetreat(rt, this.mySide); this.renderControls(); }
        } }, h('b', null, t('battle.rt.retreat')), h('span', { class: 'small' }, ret.ok ? t('battle.rt.retreat.desc') : t(ret.reason!))),
      );
      this.panel.append(row);
    }
    if (!this.opts.noDelegate) {
      this.panel.append(h('div', { class: 'row', style: { justifyContent: 'flex-end', marginTop: '4px' } },
        h('button', { class: `btn tiny ${this.auto ? 'primary' : ''}`, disabled: rt.over, onClick: () => { this.auto = !this.auto; this.renderControls(); } }, this.auto ? t('battle.rt.manual') : t('battle.rt.auto'))));
    }
    // 最近事件
    const recent = this.notes.slice(-2);
    if (recent.length) this.panel.append(h('div', { class: 'round-log' }, recent.map(n => h('div', { class: 'note' }, this.noteText(n)))));
  }

  private noteText(n: string): string {
    if (n.startsWith('@rally:')) return t('battle.rt.eventRally', { side: n.endsWith('attacker') ? t('battle.attacker') : t('battle.defender') });
    return t(n);
  }

  private showResult(): Promise<void> {
    return new Promise(resolve => {
      clear(this.panel);
      const b = this.b;
      const won = b.winner === this.mySide;
      const rt = this.rt;
      const last = b.rounds[b.rounds.length - 1];
      this.panel.append(
        h('div', { class: 'modal-title', style: { color: won ? '#4f7a52' : '#b23a2c' } }, t(`battle.result.${b.winner}`)),
        h('div', { class: 'sides' }, this.sideBox(b.attacker), this.sideBox(b.defender)),
        h('div', { class: 'round-log' },
          rt ? h('div', null, t('battle.rt.result.time', { s: Math.round(rt.time) })) : null,
          last ? h('div', null, `${t('battle.rt.result.loss', { faction: b.attacker.faction, n: last.atkLoss })} ・ ${t('battle.rt.result.loss', { faction: b.defender.faction, n: last.defLoss })}`) : null,
          this.notes.slice(-3).map(n => h('div', { class: 'note' }, this.noteText(n)))),
        h('button', { class: 'btn primary block', onClick: () => resolve() }, t('battle.finish')),
      );
    });
  }
}
