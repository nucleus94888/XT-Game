// 各分頁面板
import type { App } from './App';
import type { RegionId, FactionId, OfficerState } from '../core/types';
import {
  officersIn, officersOf, regionsOf, totalTroops, officerDef, officerAge, roninIn, getDiplo, isSnowed, neighbourRegions, factionTroops, daimyoOf,
} from '../core/state';
import { REGION_MAP } from '../data/regions';
import { FACTIONS, FACTION_MAP } from '../data/factions';
import { TECHS, TECH_MAP } from '../data/techs';
import { kamonDataUrl, type KamonId } from '../data/kamon';
import {
  cmdFarm, cmdCommerce, cmdRecruit, cmdTrain, cmdCastle, cmdGovern, cmdHire, cmdResearch, cmdReward, cmdMove, cmdTransfer, cmdHireNinja,
  hireTargets, availableTechs, troopCap, recruitCost, COSTS,
} from '../systems/commands';
import { cmdMarch, marchTargets, cancelMarch } from '../systems/military';
import { cmdGift, cmdAlliance, cmdTruce, cmdMarriageAlliance, cmdDemandSurrender, cmdBreakAlliance, canDemandSurrender, threatOf, DIPLO_COSTS, cmdMarryRetainer } from '../systems/diplomacy';
import { cmdNinja, ninjaTargets, NINJA_COSTS, type NinjaAction } from '../systems/ninja';
import { regionMods } from '../systems/modifiers';
import { t, officerName } from '../i18n';
import { h, fmt, bar, modal, slider, toast } from './dom';
import { silhouetteDataUrl } from './silhouette';
import { getAdvice, isUnlocked, guideActive, advisorOf, skipGuide } from '../systems/advisor';

export type Tab = 'region' | 'officers' | 'diplomacy' | 'tech' | 'ninja' | 'log' | 'faction';
export const TABS: Tab[] = ['region', 'officers', 'diplomacy', 'tech', 'ninja', 'log', 'faction'];

/** 引導模式下尚未解鎖的分頁不顯示 */
export function visibleTabs(app: App): Tab[] {
  const s = app.state!;
  return TABS.filter(tab => tab === 'diplomacy' ? isUnlocked(s, 'diplomacy') : tab === 'ninja' ? isUnlocked(s, 'ninja') : tab === 'tech' ? isUnlocked(s, 'tech') : true);
}

/** 軍師：教學步驟或每月一句建議 */
export function advisorBox(app: App): HTMLElement | null {
  const s = app.state!;
  const adv = getAdvice(s);
  if (!adv) return null;
  const who = advisorOf(s);
  const go = adv.action ? h('button', { class: 'btn tiny primary', onClick: () => {
    const a = adv.action!;
    if (a.tab) { app.setTab(a.tab); return; }
    if (a.region) { app.selectRegion(a.region); app.map?.focus(a.region, true); }
    if (a.officer) app.ui.officer = a.officer;
    app.ui.hintCmd = a.cmd ?? null;
    app.renderPanel();
    requestAnimationFrame(() => {
      const el = document.querySelector('.cmd.hinted') ?? document.querySelector('.officer.selected');
      el?.scrollIntoView({ block: 'center', behavior: 'smooth' });
    });
    if (a.officer && a.cmd) toast(t('advisor.went', { name: a.officer, cmd: t(`cmd.${a.cmd}`) }));
    else if (a.officer) toast(t('advisor.wentOfficer', { name: a.officer }));
  } }, t('advisor.go')) : null;
  const skip = adv.tutorial ? h('button', { class: 'btn tiny', onClick: async () => {
    const r = await modal(t('advisor.skip'), t('advisor.skipConfirm'), [t('app.confirm'), t('app.cancel')]);
    if (r === 0) { skipGuide(s); app.refresh(); }
  } }, t('advisor.skip')) : null;
  return h('div', { class: 'advisor' },
    who ? h('img', { src: silhouetteDataUrl(who) }) : null,
    h('div', null,
      h('div', { class: 'who' }, `${t('advisor.title')}${who ? ' ・ ' + officerName(who) : ''}`),
      h('div', { class: 'say' }, t(adv.key, adv.params)),
      h('div', { class: 'acts' }, go, skip)));
}

export function renderPanel(app: App): HTMLElement {
  switch (app.tab) {
    case 'region': return regionPanel(app);
    case 'officers': return officersPanel(app);
    case 'diplomacy': return diplomacyPanel(app);
    case 'tech': return techPanel(app);
    case 'ninja': return ninjaPanel(app);
    case 'log': return logPanel(app);
    case 'faction': return factionPanel(app);
  }
}

// ===== 共用 =====
function kamonImg(f: FactionId | null, size = 28): HTMLElement {
  if (!f) return h('span', { class: 'tag' }, t('region.neutral'));
  return h('img', { class: 'kamon-img', style: { width: `${size}px`, height: `${size}px` }, src: kamonDataUrl(FACTION_MAP[f].kamon as KamonId) });
}

export function officerCard(app: App, o: OfficerState, opts: { selectable?: boolean; onClick?: () => void; showRegion?: boolean } = {}): HTMLElement {
  const s = app.state!; const d = officerDef(o.id);
  const busy = o.acted || o.armyId || o.injuredMonths > 0;
  const status = o.armyId ? t('stat.marching') : o.injuredMonths > 0 ? `${t('stat.injured')} ${o.injuredMonths}` : o.acted ? t('stat.acted') : t('stat.idle');
  return h('div', {
    class: `officer ${app.ui.officer === o.id ? 'selected' : ''} ${busy ? 'acted' : ''} ${app.ui.hintCmd && app.ui.officer === o.id ? 'hinted' : ''}`,
    onClick: opts.onClick,
  },
    h('img', { class: 'silhouette', src: silhouetteDataUrl(o.id) }),
    h('div', null,
      h('div', { class: 'name' }, officerName(o.id), ' ',
        h('span', { class: `tag ${o.rank === 'daimyo' ? 'fill' : ''}` }, t(`rank.${o.rank}`)),
        o.clanTie && o.rank !== 'daimyo' ? h('span', { class: 'tag gold' }, t('clanTie')) : null),
      guideActive(s)
        ? h('div', { class: 'stats' }, h('span', null, `${t('advisor.goodAt')} `, h('b', null, (['lead', 'valor', 'intel', 'politics', 'charm'] as const).map(k => [k, d[k]] as const).sort((a, b) => b[1] - a[1]).slice(0, 2).map(([k]) => t(`stat.${k}`)).join('・'))))
        : h('div', { class: 'stats' },
          h('span', null, `${t('stat.lead')} `, h('b', null, d.lead)), h('span', null, `${t('stat.valor')} `, h('b', null, d.valor)),
          h('span', null, `${t('stat.intel')} `, h('b', null, d.intel)), h('span', null, `${t('stat.politics')} `, h('b', null, d.politics)),
          h('span', null, `${t('stat.charm')} `, h('b', null, d.charm))),
      h('div', { class: 'stats' }, d.traits.map(tr => h('span', { class: 'tag' }, t(`trait.${tr}`)))),
    ),
    h('div', { class: 'right' },
      h('div', null, `${t('stat.loyalty')} `, h('b', { style: { color: o.loyalty < 40 ? '#b23a2c' : 'inherit' } }, Math.round(o.loyalty))),
      h('div', null, `${t('stat.age')} ${officerAge(s, o.id)}`),
      h('div', null, status),
      opts.showRegion ? h('div', null, t(`region.${o.region}`)) : null,
    ),
  );
}

async function pickFromList<T>(title: string, items: { label: string; sub?: string; value: T; disabled?: boolean }[]): Promise<T | null> {
  return new Promise(resolve => {
    const overlay = h('div', { class: 'modal-overlay' });
    const list = items.map(it => h('div', { class: `list-item ${it.disabled ? 'disabled' : ''}`, style: it.disabled ? { opacity: 0.4 } : {}, onClick: () => { if (it.disabled) return; overlay.remove(); resolve(it.value); } },
      h('div', { class: 'title' }, it.label), it.sub ? h('div', { class: 'muted' }, it.sub) : null));
    overlay.appendChild(h('div', { class: 'modal' }, h('div', { class: 'modal-title' }, title), h('div', { class: 'modal-body' }, list.length ? list : h('div', { class: 'muted' }, t('cmd.noTarget'))),
      h('div', { class: 'modal-buttons' }, h('button', { class: 'btn', onClick: () => { overlay.remove(); resolve(null); } }, t('app.cancel')))));
    document.body.appendChild(overlay);
  });
}

async function pickOfficer(app: App, title: string, candidates: OfficerState[]): Promise<string | null> {
  return pickFromList(title, candidates.map(o => {
    const d = officerDef(o.id);
    return { label: `${officerName(o.id)}（${t(`region.${o.region}`)}）`, sub: `${t('stat.lead')}${d.lead} ${t('stat.valor')}${d.valor} ${t('stat.intel')}${d.intel} ${t('stat.politics')}${d.politics} ${t('stat.charm')}${d.charm}`, value: o.id };
  }));
}

async function askNumber(title: string, min: number, max: number, initial: number): Promise<number | null> {
  let v = initial;
  const body = h('div', null, slider(min, max, initial, x => { v = x; }));
  const r = await modal(title, body, [t('app.confirm'), t('app.cancel')]);
  return r === 0 ? v : null;
}

function freeOfficers(app: App, region?: RegionId): OfficerState[] {
  const s = app.state!;
  return officersOf(s, s.player).filter(o => !o.acted && !o.armyId && o.injuredMonths === 0 && (!region || o.region === region));
}

// ===== 領地 =====
function regionPanel(app: App): HTMLElement {
  const s = app.state!;
  const id = app.selected;
  if (!id) return h('div', null, advisorBox(app), h('div', { class: 'hint' }, t('panel.tutorial')), factionOverview(app));
  const r = s.regions[id]; const def = REGION_MAP[id];
  const mine = r.owner === s.player;
  const known = mine || (s.factions[s.player].intel[id] ?? -1) >= s.turn;
  const mods = regionMods(s, id);
  const wrap = h('div', null, advisorBox(app));

  wrap.appendChild(h('div', { class: 'region-head' }, kamonImg(r.owner, 44),
    h('div', null, h('div', { class: 'rname' }, t(`region.${id}`)),
      h('div', { class: 'rowner' }, `${def.castle} ・ ${r.owner ? t('panel.ownerOf', { faction: r.owner }) : t('region.neutral')} ・ ${t(`terrain.${def.terrain}`)}${isSnowed(s, id) ? ' ・ ' + t('region.snowed') : ''}`),
      h('div', null, def.bonuses.map(b => h('span', { class: 'tag' }, t(`bonus.${b}`)))))));

  // 來襲 / 出征中
  for (const a of s.armies) {
    if (a.target === id && a.faction !== s.player && r.owner === s.player) wrap.appendChild(h('div', { class: 'incoming' }, t('panel.incoming', { faction: a.faction, n: totalTroops(a), target: a.target })));
    if (a.from === id && a.faction === s.player) wrap.appendChild(h('div', { class: 'incoming', style: { color: '#3b5b7a', borderColor: '#3b5b7a', background: 'rgba(59,91,122,0.1)' } },
      t('panel.ownArmy', { n: totalTroops(a), target: a.target }), ' ', h('button', { class: 'btn tiny', onClick: () => { cancelMarch(s, a.id); app.refresh(); } }, t('panel.cancelMarch'))));
  }

  // 數值
  const troops = totalTroops(r);
  const stats = h('div', { class: 'section' },
    h('div', { class: 'grid2' },
      statRow(t('stat.kokudaka'), known ? `${r.kokudaka.toFixed(1)} 萬石` : t('panel.unknown')),
      statRow(t('stat.commerce'), known ? `${r.commerce}` : t('panel.unknown')),
      statRow(t('stat.troops'), known ? `${fmt(troops)}${mine ? ` / ${fmt(troopCap(s, id))}` : ''}` : `約 ${fmt(Math.round(troops / 5000) * 5000)}`),
      statRow(t('stat.defense'), known ? `${r.defense} / ${mods.defenseCap}` : t('panel.unknown')),
      statRow(t('stat.peopleLoyalty'), known ? `${r.loyalty}` : t('panel.unknown')),
      statRow(t('stat.training'), known ? `${r.training}` : t('panel.unknown')),
    ),
    known ? h('div', { class: 'row small muted' }, `${t('stat.ashigaru')} ${fmt(r.troops.ashigaru)} ・ ${t('stat.cavalry')} ${fmt(r.troops.cavalry)} ・ ${t('stat.gun')} ${fmt(r.troops.gun)}`) : h('div', { class: 'muted' }, t('panel.intelHint')),
  );
  wrap.appendChild(stats);

  // 武將（此區）
  const here = r.owner ? officersIn(s, id, r.owner) : [];
  if (mine) {
    const sec = h('div', { class: 'section' }, h('h3', null, `${t('app.officers')}（${t('stat.acting', { n: here.filter(o => !o.acted && o.injuredMonths === 0).length, total: here.length })}）`));
    for (const o of here) {
      sec.appendChild(officerCard(app, o, { onClick: () => { app.ui.officer = app.ui.officer === o.id ? null : o.id; app.ui.hintCmd = null; app.renderPanel(); } }));
      // 指令列直接接在被選中的武將下方，手機上不必往下找
      if (app.ui.officer === o.id) sec.appendChild(commandGrid(app, o.id, id));
    }
    if (!here.length) sec.appendChild(h('div', { class: 'muted' }, t('cmd.noOfficer')));
    wrap.appendChild(sec);
  } else if (known && here.length) {
    const sec = h('div', { class: 'section' }, h('h3', null, t('app.officers')));
    for (const o of here) sec.appendChild(officerCard(app, o));
    wrap.appendChild(sec);
  }

  // 在野
  const ronin = roninIn(s, id);
  if (ronin.length && (mine || known)) {
    const sec = h('div', { class: 'section' }, h('h3', null, t('panel.ronin')));
    for (const o of ronin) sec.appendChild(officerCard(app, o));
    wrap.appendChild(sec);
  }

  // 相鄰
  wrap.appendChild(h('div', { class: 'section' }, h('h3', null, t('panel.adjacent')),
    h('div', { class: 'row' }, def.adjacent.map(a => h('button', { class: 'btn tiny', onClick: () => { app.selectRegion(a); app.map?.focus(a, true); } },
      kamonImg(s.regions[a].owner, 16), ' ', t(`region.${a}`), ` ${fmt(Math.round(totalTroops(s.regions[a]) / 1000))}k`)))));
  return wrap;
}

function statRow(label: string, value: string): HTMLElement {
  return h('div', { class: 'stat' }, h('span', { class: 'muted' }, label), h('b', null, value));
}

// ===== 指令 =====
function commandGrid(app: App, oid: string, rid: RegionId): HTMLElement {
  const s = app.state!; const f = s.player; const o = s.officers[oid];
  const busy = o.acted || !!o.armyId || o.injuredMonths > 0;
  const gold = s.factions[f].gold;
  const grid = h('div', { class: 'cmd-grid' });
  const adv = isUnlocked(s, 'advanced');
  const add = (name: string, cost: number, onClick: () => void, extra: { disabled?: boolean; danger?: boolean; hidden?: boolean } = {}) => {
    if (extra.hidden) return;
    grid.appendChild(h('button', { class: `cmd ${extra.danger ? 'danger' : ''} ${app.ui.hintCmd === name ? 'hinted' : ''}`, disabled: busy || extra.disabled || gold < cost, onClick },
      h('div', { class: 'cmd-name' }, t(`cmd.${name}`)),
      h('div', { class: 'cmd-desc' }, t(`cmd.${name}.desc`)),
      h('div', { class: 'cmd-desc' }, cost ? t('cmd.cost', { n: cost }) : t('cmd.free'))));
  };
  add('farm', COSTS.farm, () => app.afterCommand(cmdFarm(s, f, oid, rid)));
  add('commerce', COSTS.commerce, () => app.afterCommand(cmdCommerce(s, f, oid, rid)));
  add('recruit', recruitCost(s, rid), () => app.afterCommand(cmdRecruit(s, f, oid, rid)));
  add('train', COSTS.train, () => app.afterCommand(cmdTrain(s, f, oid, rid)));
  add('castle', COSTS.castle, () => app.afterCommand(cmdCastle(s, f, oid, rid)), { hidden: !adv });
  add('govern', COSTS.govern, () => app.afterCommand(cmdGovern(s, f, oid, rid)));
  add('hire', COSTS.hire, async () => {
    const targets = hireTargets(s, f, rid);
    const pick = await pickFromList(t('cmd.chooseTarget'), targets.map(x => ({ label: `${officerName(x.id)}${x.faction ? `（${t(`faction.${x.faction}`)} ${t('stat.loyalty')} ${Math.round(x.loyalty)}）` : ''}`, sub: traitsText(x.id), value: x.id })));
    if (pick) app.afterCommand(cmdHire(s, f, oid, rid, pick));
  }, { disabled: hireTargets(s, f, rid).length === 0, hidden: !adv });
  add('research', COSTS.research, async () => {
    const list = availableTechs(s, f);
    const pick = await pickFromList(t('cmd.chooseTarget'), list.map(id => ({ label: `${t(`tech.branch.${TECH_MAP[id].branch}`)}：${t(`tech.${id}.name`)}`, sub: `${t(`tech.${id}.desc`)}（${TECH_MAP[id].cost}）`, value: id })));
    if (pick) app.afterCommand(cmdResearch(s, f, oid, rid, pick));
  }, { disabled: availableTechs(s, f).length === 0, hidden: !isUnlocked(s, 'tech') });
  add('reward', COSTS.rewardSmall, async () => {
    const targets = officersOf(s, f).filter(x => x.rank !== 'daimyo');
    const pick = await pickFromList(t('cmd.chooseTarget'), targets.map(x => ({ label: officerName(x.id), sub: `${t('stat.loyalty')} ${Math.round(x.loyalty)}`, value: x.id })));
    if (!pick) return;
    const size = await modal(t('cmd.reward'), '', [t('cmd.rewardSmall'), t('cmd.rewardLarge'), t('app.cancel')]);
    if (size === 2) return;
    app.afterCommand(cmdReward(s, f, oid, rid, pick, size === 1));
  }, { hidden: !adv });
  const ownAdj = REGION_MAP[rid].adjacent.filter(a => s.regions[a].owner === f);
  add('move', 0, async () => {
    const pick = await pickFromList<RegionId>(t('cmd.chooseTarget'), ownAdj.map(a => ({ label: t(`region.${a}`), value: a })));
    if (pick) app.afterCommand(cmdMove(s, f, oid, rid, pick));
  }, { disabled: ownAdj.length === 0 });
  add('transfer', 0, async () => {
    const pick = await pickFromList<RegionId>(t('cmd.chooseTarget'), ownAdj.map(a => ({ label: `${t(`region.${a}`)}（${fmt(totalTroops(s.regions[a]))}）`, value: a })));
    if (!pick) return;
    const n = await askNumber(t('cmd.troopsToTransfer'), 0, totalTroops(s.regions[rid]), Math.round(totalTroops(s.regions[rid]) / 2));
    if (n) app.afterCommand(cmdTransfer(s, f, oid, rid, pick, n));
  }, { disabled: ownAdj.length === 0 || totalTroops(s.regions[rid]) === 0, hidden: !adv });
  const targets = marchTargets(s, f, rid);
  add('march', 0, () => marchFlow(app, oid, rid), { disabled: targets.length === 0 || totalTroops(s.regions[rid]) < 300, danger: true });
  // 外交 / 忍者 捷徑
  add('diplomacy', 0, () => { app.setTab('diplomacy'); }, { hidden: !isUnlocked(s, 'diplomacy') });
  add('ninja', 0, () => { app.setTab('ninja'); }, { disabled: s.factions[f].ninja.level === 0, hidden: !isUnlocked(s, 'ninja') });
  return h('div', { class: 'section' }, h('h3', null, `${t('cmd.title')}：${officerName(oid)}`), grid);
}

function traitsText(id: string): string { return officerDef(id).traits.map(tr => t(`trait.${tr}`)).join(' '); }

async function marchFlow(app: App, oid: string, rid: RegionId): Promise<void> {
  const s = app.state!; const f = s.player;
  const targets = marchTargets(s, f, rid);
  app.map?.highlight(targets);
  const target = await pickFromList<RegionId>(t('cmd.chooseTarget'), targets.map(a => {
    const r = s.regions[a];
    return { label: `${t(`region.${a}`)}（${r.owner ? t(`faction.${r.owner}`) : t('region.neutral')}）`, sub: `${t('stat.troops')} 約 ${fmt(Math.round(totalTroops(r) / 1000) * 1000)} ・ ${t('stat.defense')} ${r.owner === f ? r.defense : '?'}`, value: a };
  }));
  app.map?.highlight([]);
  if (!target) return;
  // 選副將
  const here = freeOfficers(app, rid).filter(o => o.id !== oid);
  const chosen = new Set<string>([oid]);
  const list = h('div', null, here.map(o => {
    const el: HTMLElement = officerCard(app, o, { onClick: () => { if (chosen.has(o.id)) chosen.delete(o.id); else if (chosen.size < 3) chosen.add(o.id); el.classList.toggle('selected', chosen.has(o.id)); } });
    el.classList.remove('selected');
    return el;
  }));
  const ok = await modal(t('cmd.chooseOfficers'), h('div', null, officerCard(app, s.officers[oid]), list), [t('app.confirm'), t('app.cancel')]);
  if (ok !== 0) return;
  const max = totalTroops(s.regions[rid]);
  const n = await askNumber(t('cmd.troopsToSend'), 300, max, Math.round(max * 0.7));
  if (!n) return;
  app.afterCommand(cmdMarch(s, f, rid, target, [...chosen], n));
}

// ===== 武將一覽 =====
function officersPanel(app: App): HTMLElement {
  const s = app.state!; const fs = s.factions[s.player];
  const list = officersOf(s, s.player).sort((a, b) => (a.rank === 'daimyo' ? -1 : b.rank === 'daimyo' ? 1 : b.loyalty - a.loyalty));
  const wrap = h('div', null,
    h('div', { class: 'section' }, h('div', { class: 'row between' },
      h('span', null, `${t('app.officers')} ${list.length}`),
      h('span', null, `${t('stat.princesses')} ${fs.princesses}`))));
  for (const o of list) wrap.appendChild(officerCard(app, o, { showRegion: true, onClick: () => officerDetail(app, o) }));
  return wrap;
}

async function officerDetail(app: App, o: OfficerState): Promise<void> {
  const s = app.state!; const fs = s.factions[s.player];
  const canMarry = fs.princesses > 0 && o.rank !== 'daimyo' && !o.clanTie;
  const body = h('div', null, officerCard(app, o, { showRegion: true }),
    h('div', { class: 'muted' }, officerDef(o.id).personality ? t(`personality.${officerDef(o.id).personality}`) : ''),
    h('button', { class: 'btn block', onClick: () => { document.querySelector('.modal-overlay')?.remove(); app.selectRegion(o.region); app.map?.focus(o.region, true); } }, t(`region.${o.region}`)),
    canMarry ? h('button', { class: 'btn block', onClick: () => { document.querySelector('.modal-overlay')?.remove(); app.afterCommand(cmdMarryRetainer(s, s.player, o.id)); } }, t('marriage.toRetainer')) : null,
  );
  await modal(officerName(o.id), body, [t('app.close')]);
}

// ===== 外交 =====
function diplomacyPanel(app: App): HTMLElement {
  const s = app.state!; const me = s.player; const fs = s.factions[me];
  const wrap = h('div', null, h('div', { class: 'section' }, h('div', { class: 'row between' }, h('span', null, `${t('stat.credit')} ${Math.round(fs.credit)}`), h('span', null, `${t('stat.fame')} ${fs.fame}`), h('span', null, `${t('stat.princesses')} ${fs.princesses}`))));
  const neighbours = new Set<FactionId>();
  for (const r of neighbourRegions(s, me)) { const o = s.regions[r].owner; if (o) neighbours.add(o); }
  const others = FACTIONS.filter(f => f.id !== me && s.factions[f.id].alive).sort((a, b) => (neighbours.has(b.id) ? 1 : 0) - (neighbours.has(a.id) ? 1 : 0));
  for (const f of others) {
    const d = getDiplo(s, me, f.id);
    const status = d.marriage ? t('diplo.status.marriage', { n: d.marriage }) : d.alliance ? t('diplo.status.alliance', { n: d.alliance }) : d.truce ? t('diplo.status.truce', { n: d.truce }) : d.relation < -20 ? t('diplo.status.war') : t('diplo.status.neutral');
    wrap.appendChild(h('div', { class: 'list-item', onClick: () => diplomacyActions(app, f.id) },
      h('div', { class: 'row between' },
        h('span', { class: 'title' }, kamonImg(f.id, 22), ' ', t(`faction.${f.id}`), neighbours.has(f.id) ? h('span', { class: 'tag' }, t('panel.adjacent')) : null),
        h('span', { class: 'small' }, status)),
      h('div', { class: 'row small muted' }, `${t('stat.relation')} ${Math.round(d.relation)} ・ ${t('app.regions')} ${regionsOf(s, f.id).length} ・ ${t('app.troops')} ${fmt(Math.round(factionTroops(s, f.id) / 1000))}k ・ ${t('app.daimyo')} ${(() => { const dm = daimyoOf(s, f.id); return dm ? officerName(dm.id) : '-'; })()}`),
      bar(d.relation + 100, 200, d.relation >= 0 ? 'green' : 'red'),
    ));
  }
  return wrap;
}

async function diplomacyActions(app: App, target: FactionId): Promise<void> {
  const s = app.state!; const me = s.player;
  const d = getDiplo(s, me, target);
  const allied = !!(d.alliance || d.marriage);
  const actions: { key: string; cost: number; run: (oid: string) => unknown; disabled?: boolean; noEnvoy?: boolean }[] = [
    { key: 'gift', cost: DIPLO_COSTS.gift, run: oid => cmdGift(s, me, oid, target) },
    { key: 'alliance', cost: DIPLO_COSTS.alliance, run: oid => cmdAlliance(s, me, oid, target), disabled: allied || d.relation < 40 },
    { key: 'truce', cost: DIPLO_COSTS.truce, run: oid => cmdTruce(s, me, oid, target), disabled: allied || !!d.truce },
    { key: 'marriage', cost: 0, run: oid => cmdMarriageAlliance(s, me, oid, target), disabled: !!d.marriage || s.factions[me].princesses === 0 },
    { key: 'surrender', cost: 0, run: oid => cmdDemandSurrender(s, me, oid, target), disabled: !canDemandSurrender(s, me, target) },
    { key: 'break', cost: 0, run: () => cmdBreakAlliance(s, me, target), disabled: !allied, noEnvoy: true },
  ];
  const body = h('div', null,
    h('div', { class: 'muted' }, t('diplo.threat', { v: threatOf(s, me, target).toFixed(2) })),
    actions.map(a => h('button', { class: `btn block ${a.key === 'break' ? 'danger' : ''}`, disabled: a.disabled, onClick: async () => {
      document.querySelector('.modal-overlay')?.remove();
      if (a.noEnvoy) { app.afterCommand(a.run('') as never); return; }
      const envoy = await pickOfficer(app, t('cmd.selectOfficer'), freeOfficers(app));
      if (envoy) app.afterCommand(a.run(envoy) as never);
    } }, `${t(`diplo.${a.key}`)} `, h('span', { class: 'muted' }, `${t(`diplo.${a.key}.desc`)}${a.cost ? `（${a.cost}）` : ''}`))),
  );
  await modal(t(`faction.${target}`), body, [t('app.close')]);
}

// ===== 技術 =====
function techPanel(app: App): HTMLElement {
  const s = app.state!; const fs = s.factions[s.player];
  const wrap = h('div', null);
  const cur = fs.research.tech;
  wrap.appendChild(h('div', { class: 'section' }, cur ? h('div', null, h('b', null, t(`tech.${cur}.name`)), ' ', t('tech.progress', { progress: fs.research.progress, cost: TECH_MAP[cur].cost }), bar(fs.research.progress, TECH_MAP[cur].cost, 'blue')) : h('div', { class: 'muted' }, t('tech.none'))));
  const avail = availableTechs(s, s.player);
  for (const branch of ['agri', 'commerce', 'military', 'castle'] as const) {
    const sec = h('div', { class: 'section' }, h('h3', null, t(`tech.branch.${branch}`)));
    for (const tech of TECHS.filter(x => x.branch === branch)) {
      const have = fs.techs.includes(tech.id), can = avail.includes(tech.id);
      sec.appendChild(h('div', { class: 'row between', style: { padding: '4px 0', opacity: have || can ? 1 : 0.45 } },
        h('span', null, h('b', null, t(`tech.${tech.id}.name`)), ' ', h('span', { class: 'muted small' }, t(`tech.${tech.id}.desc`))),
        have ? h('span', { class: 'tag fill' }, t('tech.done')) : can ? h('button', { class: 'btn tiny', onClick: async () => {
          const oid = await pickOfficer(app, t('cmd.selectOfficer'), freeOfficers(app));
          if (oid) app.afterCommand(cmdResearch(s, s.player, oid, s.officers[oid].region, tech.id));
        } }, `${t('cmd.research')} ${tech.cost}`) : h('span', { class: 'muted small' }, tech.cost)));
    }
    wrap.appendChild(sec);
  }
  return wrap;
}

// ===== 忍者 =====
function ninjaPanel(app: App): HTMLElement {
  const s = app.state!; const fs = s.factions[s.player];
  const wrap = h('div', null);
  const cost = 800 + fs.ninja.level * 800;
  wrap.appendChild(h('div', { class: 'section' },
    h('div', null, fs.ninja.clan ? `${t(`ninjaClan.${fs.ninja.clan}`)} ・ ${t('ninja.level', { level: fs.ninja.level })}` : t('ninja.none')),
    fs.ninja.level < 3 ? h('button', { class: 'btn block', disabled: fs.gold < cost, onClick: () => app.afterCommand(cmdHireNinja(s, s.player)) }, t('cmd.hireNinja.desc', { level: fs.ninja.level, cost })) : null));
  if (fs.ninja.level === 0) return wrap;
  const targets = ninjaTargets(s, s.player);
  const sec = h('div', { class: 'section' }, h('h3', null, t('cmd.ninja')));
  for (const action of ['spy', 'rumor', 'sabotage', 'incite', 'assassinate'] as NinjaAction[]) {
    sec.appendChild(h('button', { class: 'btn block', disabled: fs.gold < NINJA_COSTS[action] || !targets.length, onClick: async () => {
      const region = await pickFromList<RegionId>(t('cmd.chooseTarget'), targets.map(r => ({ label: `${t(`region.${r}`)}（${t(`faction.${s.regions[r].owner!}`)}）`, value: r })));
      if (!region) return;
      let targetOfficer: string | undefined;
      if (action === 'rumor' || action === 'assassinate') {
        const known = (fs.intel[region] ?? -1) >= s.turn;
        const pool = officersIn(s, region, s.regions[region].owner);
        if (known && pool.length) {
          const pick = await pickFromList<string>(t('cmd.chooseTarget'), pool.map(o => ({ label: officerName(o.id), sub: `${t('stat.loyalty')} ${Math.round(o.loyalty)}`, value: o.id })));
          if (pick) targetOfficer = pick;
        }
      }
      const oid = await pickOfficer(app, t('cmd.selectOfficer'), freeOfficers(app).sort((a, b) => officerDef(b.id).intel - officerDef(a.id).intel));
      if (oid) app.afterCommand(cmdNinja(s, s.player, oid, action, region, targetOfficer));
    } }, h('b', null, t(`ninja.${action}`)), ' ', h('span', { class: 'muted small' }, `${t(`ninja.${action}.desc`)}（${NINJA_COSTS[action]}）`)));
  }
  wrap.appendChild(sec);
  return wrap;
}

// ===== 情報 =====
function logPanel(app: App): HTMLElement {
  const s = app.state!;
  const wrap = h('div', null);
  const entries = s.log.filter(l => !l.faction || l.faction === s.player).slice().reverse().slice(0, 120);
  for (const l of entries) {
    const y = 1560 + Math.floor(l.turn / 12), m = (l.turn % 12) + 1;
    wrap.appendChild(h('div', { class: `log-item ${l.important ? 'important' : ''}` }, h('span', { class: 'when' }, `${y}/${m}`), t(l.key, l.params)));
  }
  return wrap;
}

// ===== 勢力 =====
function factionPanel(app: App): HTMLElement {
  return h('div', null, advisorBox(app), factionOverview(app));
}

function factionOverview(app: App): HTMLElement {
  const s = app.state!; const me = s.player; const fs = s.factions[me];
  const regions = regionsOf(s, me);
  let income = 0, upkeep = officersOf(s, me).length * 50 + fs.ninja.level * 100, riceNeed = 0;
  for (const r of regions) { const m = regionMods(s, r.id); income += r.commerce * 7 * m.goldMul; upkeep += totalTroops(r) * 0.025; riceNeed += totalTroops(r) * 0.1; }
  const wrap = h('div', null,
    h('div', { class: 'region-head' }, kamonImg(me, 44), h('div', null, h('div', { class: 'rname' }, t(`faction.${me}`)), h('div', { class: 'rowner' }, `${t('app.daimyo')}：${(() => { const d = daimyoOf(s, me); return d ? officerName(d.id) : '-'; })()}`))),
    h('div', { class: 'section' }, h('div', { class: 'grid2' },
      statRow(t('stat.income'), `+${fmt(income)}`), statRow(t('stat.upkeep'), `-${fmt(upkeep)}`),
      statRow(t('app.rice'), `${fmt(fs.rice)}（-${fmt(riceNeed)}/月）`), statRow(t('stat.fame'), `${fs.fame}`),
      statRow(t('stat.credit'), `${Math.round(fs.credit)}`), statRow(t('stat.princesses'), `${fs.princesses}`))),
  );
  const sec = h('div', { class: 'section' }, h('h3', null, `${t('app.regions')} ${regions.length}`));
  for (const r of regions) {
    const free = officersIn(s, r.id, me).filter(o => !o.acted && o.injuredMonths === 0).length;
    sec.appendChild(h('div', { class: 'list-item', onClick: () => { app.selectRegion(r.id); app.map?.focus(r.id, true); } },
      h('div', { class: 'row between' }, h('span', { class: 'title' }, t(`region.${r.id}`)), h('span', { class: 'small' }, `${t('app.troops')} ${fmt(totalTroops(r))}`)),
      h('div', { class: 'row small muted' }, `${t('stat.kokudaka')} ${r.kokudaka.toFixed(0)} ・ ${t('stat.commerce')} ${r.commerce} ・ ${t('stat.peopleLoyalty')} ${r.loyalty} ・ ${t('stat.defense')} ${r.defense} ・ ${t('app.officers')} ${free}`)));
  }
  wrap.appendChild(sec);
  const armies = s.armies.filter(a => a.faction === me);
  if (armies.length) {
    const asec = h('div', { class: 'section' }, h('h3', null, t('panel.armies')));
    for (const a of armies) asec.appendChild(h('div', { class: 'row between small' }, h('span', null, `${t(`region.${a.from}`)} → ${t(`region.${a.target}`)} ${fmt(totalTroops(a))}`), h('span', null, a.officers.map(officerName).join('、'))));
    wrap.appendChild(asec);
  }
  // 全勢力概況
  const all = h('div', { class: 'section' }, h('h3', null, t('panel.all')));
  for (const f of FACTIONS.filter(x => s.factions[x.id].alive).sort((a, b) => regionsOf(s, b.id).length - regionsOf(s, a.id).length)) {
    all.appendChild(h('div', { class: 'row between small', style: { padding: '2px 0' } }, h('span', null, kamonImg(f.id, 18), ' ', t(`faction.${f.id}`)), h('span', { class: 'muted' }, `${regionsOf(s, f.id).length} ${t('app.regions')} ・ ${fmt(Math.round(factionTroops(s, f.id) / 1000))}k`)));
  }
  wrap.appendChild(all);
  return wrap;
}
