// AI 勢力：每月評估 → 內政 → 外交 → 軍事 → 忍者。無任何數值作弊。
import type { GameState, FactionId, RegionId } from '../core/types';
import {
  officersIn, regionsOf, totalTroops, officerDef, daimyoOf, canAttack, rngOf, saveRng, getDiplo, officersOf, factionTroops,
} from '../core/state';
import { REGION_MAP } from '../data/regions';
import { regionMods, troopPower } from './modifiers';
import {
  cmdFarm, cmdCommerce, cmdRecruit, cmdTrain, cmdCastle, cmdGovern, cmdHire, cmdResearch, cmdReward, cmdTransfer, cmdHireNinja,
  availableTechs, troopCap, hireTargets,
} from './commands';
import { cmdMarch, marchTargets } from './military';
import { cmdGift, cmdAlliance, cmdTruce, threatOf, strongestFaction, cmdMarriageAlliance, cmdDemandSurrender, canDemandSurrender } from './diplomacy';
import { cmdNinja, ninjaTargets } from './ninja';

type Personality = 'aggressive' | 'balanced' | 'defensive' | 'cunning';

function personality(state: GameState, f: FactionId): Personality {
  const d = daimyoOf(state, f);
  return d ? officerDef(d.id).personality ?? 'balanced' : 'balanced';
}

/** 鄰接敵對兵力（含來襲軍團） */
function threatAt(state: GameState, f: FactionId, rid: RegionId): number {
  let t = 0;
  for (const adj of REGION_MAP[rid].adjacent) {
    const r = state.regions[adj];
    if (r.owner && r.owner !== f && canAttack(state, r.owner, f)) t = Math.max(t, troopPower(r.troops, r.training) * 0.7);
  }
  for (const a of state.armies) if (a.target === rid && a.faction !== f) t += troopPower(a.troops, a.training);
  return t;
}

export function aiTurn(state: GameState, f: FactionId): void {
  const fs = state.factions[f];
  if (!fs.alive) return;
  const rng = rngOf(state);
  const pers = personality(state, f);
  const regions = regionsOf(state, f);
  const strongest = strongestFaction(state);

  // ===== 0. 桶狹間劇本：今川 1560 年 5 月必攻尾張 =====
  const okehazamaPending = f === 'imagawa' && !state.flags.noHistory && !state.flags.okehazamaDone && state.year === 1560 && state.regions.owari.owner === 'oda' && state.regions.mikawa.owner === 'imagawa';
  if (okehazamaPending && state.month === 5) {
    const off = officersIn(state, 'mikawa', f).filter(o => !o.acted && o.injuredMonths === 0);
    const ids = ['imagawa_yoshimoto', ...off.filter(o => o.id !== 'imagawa_yoshimoto' && o.id !== 'imagawa_ujizane').sort((a, b) => officerDef(b.id).lead - officerDef(a.id).lead).map(o => o.id)].filter(id => off.some(o => o.id === id)).slice(0, 3);
    if (ids.length) cmdMarch(state, f, 'mikawa', 'owari', ids, Math.round(totalTroops(state.regions.mikawa) * 0.85));
  }
  // 開局準備期：前 3 個月所有 AI 不主動出兵；今川在桶狹間前只盯著尾張、不另行出兵
  const militaryAllowed = state.turn >= 3 && !(okehazamaPending && state.month < 5);

  // ===== 1. 防守：來襲軍團 → 從鄰區調兵 =====
  for (const r of regions) {
    const inbound = state.armies.filter(a => a.target === r.id && a.faction !== f);
    if (!inbound.length) continue;
    const need = inbound.reduce((s, a) => s + totalTroops(a), 0) * 1.2 - totalTroops(r);
    if (need <= 0) continue;
    for (const adj of REGION_MAP[r.id].adjacent) {
      const src = state.regions[adj];
      if (src.owner !== f) continue;
      const spare = totalTroops(src) - Math.max(1500, threatAt(state, f, adj) * 0.8);
      const o = officersIn(state, adj, f).find(x => !x.acted && x.injuredMonths === 0);
      if (spare > 500 && o) cmdTransfer(state, f, o.id, adj, r.id, Math.min(spare, need));
    }
  }

  // ===== 2. 軍事：出陣 =====
  // 過度擴張懲罰：領地越多越謹慎（需要時間消化），最強者尤其
  let threshold = pers === 'aggressive' ? 1.15 : pers === 'defensive' ? 1.6 : pers === 'cunning' ? 1.3 : 1.35;
  threshold += Math.min(0.25, Math.max(0, regions.length - 3) * 0.06);
  if (f === strongest) threshold += 0.1;
  const myTotalTroops = regions.reduce((s, r) => s + totalTroops(r), 0);
  const rich = fs.gold > 3000;

  // ===== 1b. 後方 → 前線：不受威脅的內地把多餘兵力往有威脅的鄰區送 =====
  if (regions.length > 1) {
    for (const r of regions) {
      const myThreat = threatAt(state, f, r.id);
      if (myThreat > 0) continue;
      const spare = totalTroops(r) - 2500;
      if (spare < 1500) continue;
      const front = REGION_MAP[r.id].adjacent.filter(a => state.regions[a].owner === f).sort((a, b) => threatAt(state, f, b) - threatAt(state, f, a))[0];
      if (!front || threatAt(state, f, front) <= 0) continue;
      const o = officersIn(state, r.id, f).filter(x => !x.acted && x.injuredMonths === 0);
      if (o.length >= 2) cmdTransfer(state, f, o[o.length - 1].id, r.id, front, spare);
    }
  }
  let attacksThisTurn = 0;
  /** 評估從 r 攻打各目標的比率 */
  const evaluate = (r: typeof regions[number], sendable: number, cmdLead: number) => {
    const out: { target: RegionId; ratio: number }[] = [];
    const total = Math.max(1, totalTroops(r));
    for (const t of marchTargets(state, f, r.id)) {
      const tr = state.regions[t];
      const owner = tr.owner;
      if (owner && getDiplo(state, f, owner).relation > 50 && pers !== 'aggressive') continue;
      const inbound = state.armies.filter(a => a.target === t && a.faction === owner).reduce((s, a) => s + troopPower(a.troops, a.training), 0);
      const defPower = troopPower(tr.troops, tr.training) * (1 + tr.defense / 100 * 0.4) + inbound + 300;
      const myPower = troopPower({ ashigaru: Math.round(r.troops.ashigaru * sendable / total), cavalry: Math.round(r.troops.cavalry * sendable / total), gun: Math.round(r.troops.gun * sendable / total) }, r.training) * (0.7 + cmdLead / 200);
      let ratio = myPower / defPower;
      if (owner === strongest && f !== strongest) ratio *= 1.3;         // 群起圍攻最強者
      // 整體兵力壓倒性優勢 → 敢於進攻
      if (owner && myTotalTroops > factionTroops(state, owner) * 2.5) ratio *= 1.25;
      if (!owner) ratio *= 2;                                            // 無主之地
      if (owner && getDiplo(state, f, owner).relation < -40) ratio *= 1.1;
      out.push({ target: t, ratio });
    }
    return out.sort((a, b) => b.ratio - a.ratio);
  };
  for (const r of militaryAllowed ? regions : []) {
    if (attacksThisTurn >= 2) break;
    const avail = officersIn(state, r.id, f).filter(o => !o.acted && o.injuredMonths === 0);
    if (avail.length < 2 || totalTroops(r) < 3000) continue; // 至少留一人守城
    const myThreat = threatAt(state, f, r.id);
    const sendable = Math.round(totalTroops(r) - Math.max(1000, myThreat * 0.6));
    if (sendable < 2000 || fs.rice < sendable * 0.3 + 2000) continue;
    const cmd = avail.slice().sort((a, b) => officerDef(b.id).lead - officerDef(a.id).lead)[0];
    const best = evaluate(r, sendable, officerDef(cmd.id).lead)[0];
    if (!best) continue;
    if (best.ratio > threshold) {
      const ids = avail.slice().sort((a, b) => officerDef(b.id).lead - officerDef(a.id).lead).slice(0, Math.min(3, avail.length - 1)).map(o => o.id);
      // 大名不輕易親征（aggressive 例外）
      const safeIds = ids.filter(id => state.officers[id].rank !== 'daimyo' || pers === 'aggressive' || ids.length === 1);
      const res = cmdMarch(state, f, r.id, best.target, safeIds.length ? safeIds : ids, sendable);
      if (res.ok) attacksThisTurn++;
    } else if (best.ratio > threshold * 0.6 && regions.length > 1) {
      // 集結：從不受威脅的後方調兵到前線，下個月再攻
      for (const adj of REGION_MAP[r.id].adjacent) {
        const src = state.regions[adj];
        if (src.owner !== f) continue;
        const srcThreat = threatAt(state, f, adj);
        const spare = totalTroops(src) - Math.max(2000, srcThreat * 1.1);
        const o = officersIn(state, adj, f).filter(x => !x.acted && x.injuredMonths === 0);
        if (spare > 1500 && o.length >= 2) cmdTransfer(state, f, o[o.length - 1].id, adj, r.id, spare);
      }
    }
  }

  // ===== 3. 內政：每位未行動武將 =====
  for (const r of regions) {
    const mods = regionMods(state, r.id);
    for (const o of officersIn(state, r.id, f)) {
      if (o.acted || o.injuredMonths > 0) continue;
      if (fs.gold < 150) break;
      const d = officerDef(o.id);
      const troops = totalTroops(r);
      const cap = troopCap(state, r.id);
      const riceMonths = fs.rice / Math.max(1, regions.reduce((s, x) => s + totalTroops(x), 0) * 0.1);
      const threatened = threatAt(state, f, r.id) > troopPower(r.troops, r.training) * 0.8;
      // 候選（權重）
      const opts: { w: number; run: () => unknown }[] = [];
      if (riceMonths < 6 && r.kokudaka < REGION_MAP[r.id].init.kokudaka * 1.8) opts.push({ w: 3 + d.politics / 50, run: () => cmdFarm(state, f, o.id, r.id) });
      if (fs.gold < 1500 && r.commerce < 200) opts.push({ w: 3 + d.politics / 50, run: () => cmdCommerce(state, f, o.id, r.id) });
      if (r.loyalty < 50) opts.push({ w: 3 + (50 - r.loyalty) / 10, run: () => cmdGovern(state, f, o.id, r.id) });
      if (troops < cap * (pers === 'aggressive' ? 0.75 : 0.6) && r.loyalty >= 35 && fs.gold > 600 && riceMonths > 4) opts.push({ w: 2.5 + d.charm / 50 + (threatened ? 2 : 0) + (rich ? 1 : 0), run: () => cmdRecruit(state, f, o.id, r.id) });
      if (r.training < 75) opts.push({ w: 1.5 + (d.lead + d.valor) / 100, run: () => cmdTrain(state, f, o.id, r.id) });
      if (r.defense < mods.defenseCap * 0.75 && (threatened || pers === 'defensive' || rich)) opts.push({ w: 2 + (d.traits.includes('builder') ? 2 : 0) + (rich ? 1 : 0), run: () => cmdCastle(state, f, o.id, r.id) });
      const techs = availableTechs(state, f);
      if (techs.length && fs.gold > 1500) {
        const pick = fs.research.tech && techs.includes(fs.research.tech) ? fs.research.tech : rng.pick(techs);
        opts.push({ w: 1 + d.intel / 60 + (rich ? 2 : 0), run: () => cmdResearch(state, f, o.id, r.id, pick) });
      }
      const hires = hireTargets(state, f, r.id);
      // 武將已多時少登用（俸祿負擔）
      if (hires.length && fs.gold > 400 && officersOf(state, f).length < regions.length * 5 + 4) opts.push({ w: 2 + d.charm / 40, run: () => cmdHire(state, f, o.id, r.id, hires.sort((a, b) => officerDef(b.id).lead + officerDef(b.id).politics - officerDef(a.id).lead - officerDef(a.id).politics)[0].id) });
      const unhappy = officersOf(state, f).filter(x => x.loyalty < (rich ? 60 : 45) && x.rank !== 'daimyo');
      if (unhappy.length && fs.gold > 1200) opts.push({ w: 2.5 + (rich ? 1.5 : 0), run: () => cmdReward(state, f, o.id, r.id, unhappy[0].id, fs.gold > 2500) });
      if (rich && r.commerce < 200) opts.push({ w: 2, run: () => cmdCommerce(state, f, o.id, r.id) });
      if (rich && r.kokudaka < REGION_MAP[r.id].init.kokudaka * 1.8) opts.push({ w: 2, run: () => cmdFarm(state, f, o.id, r.id) });
      if (!opts.length) {
        if (r.commerce < 200) opts.push({ w: 1, run: () => cmdCommerce(state, f, o.id, r.id) });
        if (r.kokudaka < REGION_MAP[r.id].init.kokudaka * 1.8) opts.push({ w: 1, run: () => cmdFarm(state, f, o.id, r.id) });
        opts.push({ w: 0.5, run: () => cmdTrain(state, f, o.id, r.id) });
      }
      // 加權隨機
      const total = opts.reduce((s, x) => s + x.w, 0);
      let v = rng.next() * total;
      for (const x of opts) { v -= x.w; if (v <= 0) { x.run(); break; } }
    }
  }

  // ===== 4. 外交（每月最多一次） =====
  const envoy = officersOf(state, f).find(o => !o.acted && !o.armyId && o.injuredMonths === 0 && o.rank !== 'daimyo');
  if (envoy && fs.gold > 600) {
    const neighbours = new Set<FactionId>();
    for (const r of regions) for (const adj of REGION_MAP[r.id].adjacent) { const ow = state.regions[adj].owner; if (ow && ow !== f) neighbours.add(ow); }
    let done = false;
    for (const n of neighbours) {
      if (done) break;
      if (canDemandSurrender(state, f, n)) { cmdDemandSurrender(state, f, envoy.id, n); done = true; break; }
      const pair = getDiplo(state, f, n);
      const theirThreat = threatOf(state, n, f);
      if (theirThreat > 1.6 && !(pair.truce && pair.truce > 0) && !(pair.alliance && pair.alliance > 0) && rng.chance(0.5)) { cmdTruce(state, f, envoy.id, n); done = true; }
      else if (pair.relation >= 40 && !(pair.alliance && pair.alliance > 0) && n !== strongest && rng.chance(0.4)) {
        if (fs.princesses > 0 && rng.chance(0.4)) cmdMarriageAlliance(state, f, envoy.id, n); else cmdAlliance(state, f, envoy.id, n);
        done = true;
      }
      else if (theirThreat > 1.2 && pair.relation < 30 && fs.gold > 1500 && rng.chance(0.35)) { cmdGift(state, f, envoy.id, n); done = true; }
    }
  }

  // ===== 5. 忍者 =====
  if (fs.gold > 3500 && fs.ninja.level < (pers === 'cunning' ? 3 : 1) && rng.chance(0.3)) cmdHireNinja(state, f);
  if (fs.ninja.level > 0 && fs.gold > 1200) {
    const spy = officersOf(state, f).filter(o => !o.acted && !o.armyId && o.injuredMonths === 0).sort((a, b) => officerDef(b.id).intel - officerDef(a.id).intel)[0];
    const targets = ninjaTargets(state, f);
    if (spy && targets.length && rng.chance(pers === 'cunning' ? 0.6 : 0.3)) {
      const t = targets.sort((a, b) => troopPower(state.regions[a].troops, 50) - troopPower(state.regions[b].troops, 50))[0];
      const action = rng.pick(['rumor', 'sabotage', 'incite'] as const);
      cmdNinja(state, f, spy.id, action, t);
    }
  }

  saveRng(state, rng);
}
