// 戰鬥畫面：3D 場景 + 戰術選擇
import type { App } from './App';
import type { BattleState, Tactic } from '../core/types';
import { TACTICS, canUseTactic, aiTactic, resolveRound, tacticHint } from '../systems/battle';
import { attemptOkehazama } from '../systems/events';
import { rngOf, saveRng, totalTroops, officerDef } from '../core/state';
import { FACTION_MAP } from '../data/factions';
import { kamonDataUrl, type KamonId } from '../data/kamon';
import { t, officerName } from '../i18n';
import { h, clear, fmt, bar, modal } from './dom';
import { BattleScene } from '../render/BattleScene';

export class BattleView {
  private root: HTMLElement;
  private sceneEl: HTMLElement;
  private panel: HTMLElement;
  private hud: HTMLElement;
  private scene: BattleScene;
  private mySide: 'attacker' | 'defender';
  private auto = false;

  constructor(private app: App, private b: BattleState) {
    const s = app.state!;
    this.mySide = b.attacker.faction === s.player ? 'attacker' : 'defender';
    this.hud = h('div', { class: 'bhud' });
    this.sceneEl = h('div', { class: 'scene' });
    this.panel = h('div', { class: 'bpanel' });
    this.root = h('div', { id: 'battle' }, this.hud, this.sceneEl, this.panel);
    document.body.appendChild(this.root);
    this.scene = new BattleScene(this.sceneEl);
    const fa = FACTION_MAP[b.attacker.faction], fd = FACTION_MAP[b.defender.faction];
    this.scene.setup(b, { kamon: fa.kamon, color: fa.color, name: t(`faction.${fa.id}`) }, { kamon: fd.kamon, color: fd.color, name: t(`faction.${fd.id}`) });
  }

  async run(): Promise<void> {
    const b = this.b;
    this.renderHud();
    if (b.special === 'okehazama' && this.mySide === 'defender') {
      const r = await modal(t('battle.okehazama.title'), t('battle.okehazama.desc', { rain: b.weather === 'rain' ? t('battle.okehazama.rain') : '' }), [t('battle.okehazama.go'), t('battle.okehazama.no')]);
      if (r === 0) {
        const rng = rngOf(this.app.state!);
        attemptOkehazama(this.app.state!, b, rng);
        saveRng(this.app.state!, rng);
        const log = b.rounds[b.rounds.length - 1];
        this.renderPanel(log);
        await this.scene.playRound(log, b);
        this.renderHud();
      } else b.special = undefined;
    }
    while (!b.over) {
      const tactic = this.auto ? null : await this.chooseTactic();
      const rng = rngOf(this.app.state!);
      const me = b[this.mySide], them = this.mySide === 'attacker' ? b.defender : b.attacker;
      me.tactic = tactic ?? aiTactic(b, this.mySide, rng);
      them.tactic = aiTactic(b, this.mySide === 'attacker' ? 'defender' : 'attacker', rng);
      resolveRound(b, rng);
      saveRng(this.app.state!, rng);
      const log = b.rounds[b.rounds.length - 1];
      this.renderPanel(log);
      this.renderHud();
      await this.scene.playRound(log, b);
    }
    await this.showResult();
    this.scene.dispose();
    this.root.remove();
  }

  private renderHud(): void {
    const b = this.b;
    clear(this.hud);
    const side = (x: typeof b.attacker, label: string) => h('div', { class: 'side' },
      h('img', { src: kamonDataUrl(FACTION_MAP[x.faction].kamon as KamonId) }),
      h('div', null, h('div', null, `${label} ${t(`faction.${x.faction}`)}`), h('div', { class: 'small' }, `${fmt(totalTroops(x))} ・ ${t('stat.morale')} ${Math.round(x.morale)}`)));
    this.hud.append(side(b.attacker, t('battle.attacker')),
      h('div', { style: { textAlign: 'center' } }, h('div', null, t('battle.title', { region: b.region })), h('div', { class: 'small' }, `${t('battle.round', { n: b.round, max: b.maxRounds })} ・ ${t(`battle.weather.${b.weather}`)} ・ ${t(`terrain.${b.terrain}`)} ・ ${b.siege ? t('battle.siege') : t('battle.field')}`)),
      side(b.defender, t('battle.defender')));
  }

  private chooseTactic(): Promise<Tactic> {
    return new Promise(resolve => {
      const b = this.b; const me = b[this.mySide];
      const rng = rngOf(this.app.state!);
      const hint = tacticHint(b, this.mySide, rng);
      clear(this.panel);
      const grid = h('div', { class: 'tactic-grid' });
      // 預測對方戰術時，標示哪些戰術能剋制
      const counters: Record<Tactic, Tactic[]> = { charge: ['hold'], hold: ['volley', 'maneuver', 'fire'], volley: ['charge'], maneuver: ['charge'], fire: [], duel: [], retreat: [] };
      for (const tt of TACTICS) {
        const can = canUseTactic(b, me, tt);
        const hinted = hint ? counters[hint].includes(tt) : false;
        grid.appendChild(h('button', { class: `tactic ${hinted ? 'hinted' : ''}`, disabled: !can.ok, onClick: () => resolve(tt) },
          h('div', { class: 't-name' }, t(`tactic.${tt}`)), h('div', { class: 't-desc' }, can.ok ? t(`tactic.${tt}.desc`) : t(can.reason!))));
      }
      const cmd = me.commander ? officerDef(me.commander) : null;
      this.panel.append(
        h('div', { class: 'sides' }, this.sideBox(b.attacker), this.sideBox(b.defender)),
        h('div', { class: 'small muted' }, `${t('battle.commander')}：${me.commander ? officerName(me.commander) : '-'}${cmd ? `（${t('stat.lead')}${cmd.lead} ${t('stat.valor')}${cmd.valor} ${t('stat.intel')}${cmd.intel}）` : ''}`),
        h('div', { class: 'hint' }, hint ? t('battle.hint', { tactic: `tactic:${hint}` }) : t('battle.noHint')),
        h('div', { class: 'row between' }, h('b', null, t('battle.chooseTactic')), h('button', { class: 'btn tiny', onClick: () => { this.auto = true; resolve(aiTactic(b, this.mySide, rngOf(this.app.state!))); } }, t('battle.auto'))),
        grid,
        this.lastRound() ?? '',
      );
    });
  }

  private sideBox(x: typeof this.b.attacker): HTMLElement {
    return h('div', { class: 's' },
      h('div', null, t(`faction.${x.faction}`), ' ', h('span', { class: 'n' }, fmt(totalTroops(x)))),
      h('div', { class: 'muted' }, `${t('stat.ashigaru')} ${fmt(x.troops.ashigaru)} ${t('stat.cavalry')} ${fmt(x.troops.cavalry)} ${t('stat.gun')} ${fmt(x.troops.gun)}`),
      h('div', null, `${t('stat.morale')} ${Math.round(x.morale)}`), bar(x.morale, 130, x.morale < 40 ? 'red' : 'green'),
    );
  }

  private lastRound(): HTMLElement | null {
    const log = this.b.rounds[this.b.rounds.length - 1];
    if (!log) return null;
    return h('div', { class: 'round-log' },
      `${t('battle.round', { n: log.round, max: this.b.maxRounds })}：${t('battle.attacker')} ${t(`tactic.${log.atkTactic}`)}（${t('battle.loss', { n: log.atkLoss })}） vs ${t('battle.defender')} ${t(`tactic.${log.defTactic}`)}（${t('battle.loss', { n: log.defLoss })}）`,
      log.notes.map(n => h('div', { class: 'note' }, t(n))));
  }

  private renderPanel(log: BattleState['rounds'][number]): void {
    clear(this.panel);
    this.panel.append(h('div', { class: 'sides' }, this.sideBox(this.b.attacker), this.sideBox(this.b.defender)), this.lastRound() ?? '', h('div', { class: 'spinner' }, `… ${t('battle.round', { n: log.round, max: this.b.maxRounds })} …`));
  }

  private showResult(): Promise<void> {
    return new Promise(resolve => {
      clear(this.panel);
      const b = this.b;
      const won = b.winner === this.mySide;
      this.panel.append(
        h('div', { class: 'modal-title', style: { color: won ? '#4f7a52' : '#b23a2c' } }, t(`battle.result.${b.winner}`)),
        h('div', { class: 'sides' }, this.sideBox(b.attacker), this.sideBox(b.defender)),
        this.lastRound() ?? '',
        h('button', { class: 'btn primary block', onClick: () => resolve() }, t('battle.finish')),
      );
    });
  }
}
