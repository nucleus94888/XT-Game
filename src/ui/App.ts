// 應用程式控制器：畫面切換、HUD、回合流程、面板路由
import type { GameState, FactionId, RegionId } from '../core/types';
import { createGame, officersOf, regionsOf, factionTroops, totalTroops as factionTroopsOf } from '../core/state';
import { endTurn, completeTurn } from '../systems/turn';
import { finishBattle } from '../systems/battle';
import { resolveEvent } from '../systems/events';
import { saveGame, loadGame, saveMeta, SLOTS, autosave, loadAutosave } from '../core/save';
import { FACTIONS, FACTION_MAP } from '../data/factions';
import { kamonDataUrl, type KamonId } from '../data/kamon';
import { t, setLang, getLang, LANGS, LANG_NAMES, officerName } from '../i18n';
import { h, clear, fmt, toast, modal } from './dom';
import { MapScene } from '../render/MapScene';
import { renderPanel, type Tab, visibleTabs } from './panels';
import { BattleView } from './BattleView';
import { onPlayerAction, guideActive, advisorOf, guideStep } from '../systems/advisor';
import { createBattle } from '../systems/battle';
import type { Army } from '../core/types';

export class App {
  state: GameState | null = null;
  map: MapScene | null = null;
  selected: RegionId | null = null;
  tab: Tab = 'region';
  /** 面板內暫存（選中的武將等） */
  ui: { officer: string | null; highlight: RegionId[]; hintCmd: string | null; hintOfficer: string | null; lastStats: { id: RegionId; kokudaka: number; commerce: number; troops: number; defense: number; loyalty: number; training: number } | null } = { officer: null, highlight: [], hintCmd: null, hintOfficer: null, lastStats: null };
  /** 結束回合前的快照，給月報用 */
  private report: { gold: number; rice: number; troops: number; regions: number } | null = null;
  private root: HTMLElement;
  private hud!: HTMLElement;
  private mapEl!: HTMLElement;
  private tabsEl!: HTMLElement;
  private panelEl!: HTMLElement;

  constructor(root: HTMLElement) {
    this.root = root;
    this.showTitle();
  }

  // ===== 標題 =====
  showTitle(): void {
    clear(this.root);
    this.map?.dispose(); this.map = null; this.state = null;
    const auto = loadAutosave();
    const item = (label: string, desc: string | null, cls: string, onClick: () => void) =>
      h('button', { class: `btn ${cls}`, onClick }, h('span', null, label), desc ? h('span', { class: 'd' }, desc) : null);
    const title = h('div', { id: 'title' },
      h('h1', null, t('app.title')),
      h('div', { class: 'sub' }, t('app.subtitle')),
      h('div', { class: 'menu' },
        auto ? item(t('app.continue'), `${t(`faction.${auto.player}`)} ${t('app.date', { year: auto.year, month: auto.month })}`, 'primary', () => this.startFrom(auto)) : null,
        item(t('app.scenarioOda'), t('app.scenarioOda.desc'), auto ? '' : 'primary', () => { const st = createGame(Date.now() % 1000000, 'oda'); st.flags.guide = true; st.flags.guideStep = 0; this.startFrom(st); }),
        item(t('app.drill'), t('app.drill.desc'), '', () => this.runDrill()),
        item(t('app.chooseFactionBtn'), null, '', () => this.showFactionSelect()),
        item(t('app.load'), null, '', () => this.showLoad()),
      ),
      h('div', { class: 'lang' }, LANGS.map(l => h('button', { class: `btn tiny ${getLang() === l ? 'primary' : ''}`, onClick: async () => { await setLang(l); this.showTitle(); } }, LANG_NAMES[l]))),
      h('div', { class: 'credits' }, t('app.credits')),
    );
    this.root.appendChild(title);
  }

  async showLoad(): Promise<void> {
    const items = SLOTS.map(s => { const m = saveMeta(s); return { s, m }; });
    const body = h('div', null, items.map(({ s, m }) => h('button', {
      class: 'btn block', disabled: !m,
      onClick: () => { const st = loadGame(s); if (st) { document.querySelector('.modal-overlay')?.remove(); this.startFrom(st); toast(t('app.loaded', { slot: t('app.slot', { n: s }) })); } },
    }, `${t('app.slot', { n: s })}：${m ? `${t(`faction.${m.faction}`)} ${t('app.date', { year: m.year, month: m.month })}` : t('app.empty')}`)));
    await modal(t('app.load'), body, [t('app.close')]);
  }

  showFactionSelect(): void {
    clear(this.root);
    let chosen: FactionId = 'oda';
    const desc = h('div', { class: 'faction-desc' });
    const grid = h('div', { class: 'faction-grid' });
    const render = () => {
      clear(grid);
      for (const f of FACTIONS.filter(x => x.major)) {
        grid.appendChild(h('div', { class: `faction-card ${f.id === chosen ? 'selected' : ''}`, onClick: () => { chosen = f.id; render(); } },
          h('img', { src: kamonDataUrl(f.kamon as KamonId, f.id === chosen ? '#f3ead8' : '#1f1a17') }),
          h('div', { class: 'fname' }, t(`faction.${f.id}`)),
          h('div', { class: 'small' }, officerName(f.daimyo)),
          h('div', { class: 'stars' }, '★'.repeat(f.difficulty) + '☆'.repeat(4 - f.difficulty)),
        ));
      }
      desc.textContent = t(`factionDesc.${chosen}`);
    };
    render();
    let guide = localStorage.getItem('xt.guide') !== '0';
    const check = h('input', { type: 'checkbox', checked: guide });
    check.addEventListener('change', () => { guide = check.checked; localStorage.setItem('xt.guide', guide ? '1' : '0'); });
    this.root.appendChild(h('div', { id: 'title' },
      h('div', { class: 'sub' }, t('app.chooseFaction')),
      grid, desc,
      h('label', { class: 'check' }, check, t('app.guideToggle')),
      h('div', { class: 'row' },
        h('button', { class: 'btn', onClick: () => this.showTitle() }, t('app.back')),
        h('button', { class: 'btn primary', onClick: () => { const st = createGame(Date.now() % 1000000, chosen); if (guide) { st.flags.guide = true; st.flags.guideStep = 0; } this.startFrom(st); } }, t('app.start')),
      ),
    ));
  }

  // ===== 遊戲畫面 =====
  startFrom(state: GameState): void {
    this.state = state;
    this.selected = null; this.tab = 'region'; this.ui = { officer: null, highlight: [], hintCmd: null, hintOfficer: null, lastStats: null };
    clear(this.root);
    this.hud = h('div', { id: 'hud' });
    this.mapEl = h('div', { id: 'map' });
    this.tabsEl = h('div', { id: 'tabs' });
    this.panelEl = h('div', { id: 'panel' });
    const side = h('div', { id: 'side' }, this.tabsEl, this.panelEl);
    this.root.append(this.hud, this.mapEl, side);
    this.map = new MapScene(this.mapEl);
    this.map.onSelect = (id) => { this.selectRegion(id); };
    this.refresh();
    // 初次提示
    const home = regionsOf(state, state.player)[0];
    if (home) {
      // 引導模式第一回合不自動選取：第一步就是請玩家自己在地圖上點領地
      if (!(guideActive(state) && state.turn === 0)) this.selectRegion(home.id);
      this.map.focus(home.id, false, innerWidth < 700 ? 42 : 70);
    }
    if (state.turn === 0 && !state.flags.devSkipIntro) {
      if (guideActive(state)) {
        const who = advisorOf(state);
        modal(t('advisor.title'), h('div', null, h('p', null, t('guide.intro', { name: who ?? '' })), h('p', { class: 'muted' }, t('panel.tutorial'))), [t('app.confirm')]);
      } else {
        const body = h('div', null, h('p', null, t('panel.tutorial')), state.player === 'oda' ? h('p', { class: 'hint' }, t('panel.hint.oda')) : null);
        modal(t('app.title'), body, [t('app.confirm')]);
      }
    }
    if (state.battleQueue.length) this.runBattles();
  }

  selectRegion(id: RegionId | null): void {
    this.selected = id;
    this.ui.officer = null;
    this.ui.highlight = [];
    this.ui.hintCmd = null;
    this.map?.select(id);
    this.map?.highlight([]);
    if (id) this.tab = 'region';
    this.renderTabs(); this.renderPanel();
  }

  setTab(tab: Tab): void { this.tab = tab; this.ui.officer = null; this.ui.hintCmd = null; this.renderTabs(); this.renderPanel(); }

  refresh(): void {
    if (!this.state) return;
    this.map?.update(this.state);
    this.renderHud(); this.renderTabs(); this.renderPanel();
  }

  private renderHud(): void {
    const s = this.state!; const fs = s.factions[s.player]; const f = FACTION_MAP[s.player];
    const unacted = officersOf(s, s.player).filter(o => !o.acted && !o.armyId && o.injuredMonths === 0).length;
    clear(this.hud);
    this.hud.append(
      h('img', { class: 'kamon', src: kamonDataUrl(f.kamon as KamonId, '#f3ead8') }),
      h('span', { class: 'date' }, t('app.date', { year: s.year, month: s.month })),
      h('span', { class: 'res' },
        h('span', null, `${t('app.gold')} `, h('b', null, fmt(fs.gold))),
        h('span', null, `${t('app.rice')} `, h('b', null, fmt(fs.rice))),
        h('span', null, `${t('app.troops')} `, h('b', null, fmt(factionTroops(s, s.player)))),
        h('span', null, `${t('app.officers')} `, h('b', null, `${unacted}`)),
      ),
      h('span', { class: 'spacer' }),
      h('button', { class: 'btn tiny', onClick: () => this.showMenu() }, t('app.menu')),
      h('button', { class: `btn end-turn ${unacted === 0 && !s.gameOver ? 'hinted' : ''}`, onClick: () => this.endTurn() }, t('app.endTurn')),
    );
  }

  private renderTabs(): void {
    clear(this.tabsEl);
    const s = this.state!;
    const important = s.log.filter(l => l.important && l.turn === s.turn - 1 && (!l.faction || l.faction === s.player)).length;
    const tabs = visibleTabs(this);
    if (!tabs.includes(this.tab)) this.tab = 'region';
    for (const tab of tabs) {
      this.tabsEl.appendChild(h('button', { class: tab === this.tab ? 'active' : '', onClick: () => this.setTab(tab) },
        t(`panel.${tab}`), tab === 'log' && important ? h('span', { class: 'badge' }, important) : null));
    }
  }

  renderPanel(): void {
    clear(this.panelEl);
    this.panelEl.appendChild(renderPanel(this));
    this.panelEl.scrollTop = 0;
  }

  /** 指令執行後統一刷新 */
  afterCommand(result: { ok: boolean; key: string; params?: Record<string, string | number> }): void {
    const s = this.state!;
    const msg = t(result.key, result.params);
    toast(msg, result.ok);
    if (result.ok) {
      // 記住這位武將做了什麼（武將卡顯示「已行動：振興商業」）
      const oid = this.ui.officer;
      const cmdName = result.key.replace('cmd.ok.', '').replace(/(Fail|Done|Refused|Hired|NoTarget)$/, '');
      if (oid && s.officers[oid]?.acted) s.officers[oid].lastCmd = cmdName === 'ninjaFail' ? 'ninja' : cmdName;
      // 地圖飄字
      if (this.selected) this.map?.floatText(this.selected, msg.length > 14 ? msg.slice(0, 14) + '…' : msg);
      const before = guideStep(s);
      onPlayerAction(s, 'cmd', result.key);
      if (guideActive(s) && guideStep(s) > before) setTimeout(() => toast(t('guide.stepDone')), 2300);
      this.ui.officer = null; this.ui.hintCmd = null;
    }
    this.refresh();
  }

  // ===== 回合 =====
  async endTurn(): Promise<void> {
    const s = this.state!;
    if (s.gameOver) return;
    const unacted = officersOf(s, s.player).filter(o => !o.acted && !o.armyId && o.injuredMonths === 0).length;
    if (unacted > 0) {
      const r = await modal(t('app.endTurn'), t('app.endTurnConfirm', { n: unacted }), [t('app.confirm'), t('app.cancel')]);
      if (r !== 0) return;
    }
    this.ui.officer = null; this.ui.highlight = []; this.ui.hintCmd = null;
    const wasGuide = guideActive(s);
    const fs0 = s.factions[s.player];
    this.report = { gold: fs0.gold, rice: fs0.rice, troops: factionTroops(s, s.player), regions: regionsOf(s, s.player).length };
    endTurn(s);
    onPlayerAction(s, 'endTurn');
    if (wasGuide && !guideActive(s)) toast(t('guide.done'));
    if (s.battleQueue.length) await this.runBattles();
    else await this.afterTurn();
  }

  private async runBattles(): Promise<void> {
    const s = this.state!;
    while (s.battleQueue.length) {
      const b = s.battleQueue.shift()!;
      const view = new BattleView(this, b);
      await view.run();
      finishBattle(s, b);
      onPlayerAction(s, 'battleEnd');
    }
    completeTurn(s);
    await this.afterTurn();
  }

  private async afterTurn(): Promise<void> {
    const s = this.state!;
    this.refresh();
    while (s.pendingEvents.length) {
      const ev = s.pendingEvents.shift()!;
      const idx = await modal(t(`event.${ev.id}.title`), t(`event.${ev.id}.desc`, ev.params), ev.choices.map(c => t(`event.${ev.id}.choice.${c}`)));
      resolveEvent(s, ev.id, ev.choices[idx]);
      this.refresh();
    }
    // 月報：金 / 糧 / 兵的增減 + 重要事件 + 敵軍動向
    const news = s.log.filter(l => l.important && l.turn === s.turn - 1 && (!l.faction || l.faction === s.player));
    if (!s.gameOver && !s.flags.noReport && this.report) {
      const fs = s.factions[s.player]; const r0 = this.report;
      const delta = (a: number, b: number) => { const d = Math.round(b - a); return h('b', { class: d > 0 ? 'up' : d < 0 ? 'down' : '' }, d > 0 ? `+${fmt(d)}` : fmt(d)); };
      const row = (label: string, a: number, b: number) => h('div', { class: 'report-row' }, h('span', null, label), h('span', null, `${fmt(a)} → ${fmt(b)}`), delta(a, b));
      const incoming = s.armies.filter(a => a.faction !== s.player && s.regions[a.target].owner === s.player);
      const noMore = h('input', { type: 'checkbox' });
      const body = h('div', { class: 'report' },
        row(t('app.gold'), r0.gold, fs.gold), row(t('app.rice'), r0.rice, fs.rice), row(t('app.troops'), r0.troops, factionTroops(s, s.player)),
        h('div', { class: 'report-events' },
          incoming.map(a => h('div', { class: 'note' }, t('panel.incoming', { faction: a.faction, n: factionTroopsOf(a), target: a.target }))),
          news.length ? news.slice(-6).map(l => h('div', null, t(l.key, l.params))) : (incoming.length ? null : h('div', { class: 'muted' }, t('report.none')))),
        h('label', { class: 'check small' }, noMore, t('report.noMore')),
      );
      await modal(t('report.title', { year: s.year, month: s.month }), body, [t('app.confirm')]);
      if (noMore.checked) s.flags.noReport = true;
    } else if (news.length) toast(t(news[news.length - 1].key, news[news.length - 1].params));
    this.report = null;
    if (s.gameOver) {
      const key = s.gameOver.winner ? `app.victory.${s.gameOver.reason}` : `app.defeat.${s.gameOver.reason}`;
      await modal(t('app.gameOver'), t(key, { faction: s.player }), [t('app.toTitle')]);
      this.showTitle();
      return;
    }
    autosave(s);
  }

  /** 合戰演習：不影響任何存檔的單場即時戰鬥 */
  async runDrill(): Promise<void> {
    const st = createGame(7, 'oda');
    st.flags.devSkipIntro = true;
    this.state = st;
    const army: Army = { id: 'drill', faction: 'oda', from: 'owari', target: 'mino', troops: { ashigaru: 5200, cavalry: 800, gun: 0 }, training: 60, commander: 'oda_nobunaga', officers: ['oda_nobunaga', 'shibata_katsuie'], eta: 0 };
    // 以美濃守軍為對手，但改成野戰、晴天、兵力相當
    const rng = { chance: () => false } as unknown as import('../core/rng').Rng;
    const b = createBattle(st, army, rng);
    b.siege = false; b.weather = 'clear'; b.terrain = 'plain';
    b.defender.troops = { ashigaru: 5000, cavalry: 600, gun: 0 }; b.defender.initial = 5600; b.defender.morale = 100;
    b.attacker.initial = 6000;
    const view = new BattleView(this, b, { introKey: 'battle.rt.drillIntro', noDelegate: true });
    clear(this.root);
    await view.run();
    this.state = null;
    this.showTitle();
  }

  async showMenu(): Promise<void> {
    const s = this.state!;
    const body = h('div', null,
      h('div', { class: 'muted' }, t('app.save')),
      SLOTS.map(slot => h('button', { class: 'btn block', onClick: () => { saveGame(s, slot); toast(t('app.saved', { slot: t('app.slot', { n: slot }) })); document.querySelector('.modal-overlay')?.remove(); } },
        `${t('app.slot', { n: slot })}：${(() => { const m = saveMeta(slot); return m ? `${t(`faction.${m.faction}`)} ${t('app.date', { year: m.year, month: m.month })}` : t('app.empty'); })()}`)),
      h('div', { class: 'muted', style: { marginTop: '10px' } }, t('app.language')),
      h('div', { class: 'row' }, LANGS.map(l => h('button', { class: `btn tiny ${getLang() === l ? 'primary' : ''}`, onClick: async () => { await setLang(l); document.querySelector('.modal-overlay')?.remove(); this.refresh(); } }, LANG_NAMES[l]))),
      h('div', { class: 'row', style: { marginTop: '10px' } },
        h('button', { class: 'btn', onClick: () => { document.querySelector('.modal-overlay')?.remove(); this.showLoad(); } }, t('app.load')),
        h('button', { class: 'btn danger', onClick: () => { document.querySelector('.modal-overlay')?.remove(); this.showTitle(); } }, t('app.toTitle')),
      ),
    );
    await modal(t('app.menu'), body, [t('app.close')]);
  }
}
