// 內政指令：每位武將每月一個。所有指令都回傳 CmdResult，UI 只負責顯示。
import type { GameState, FactionId, RegionId, OfficerState } from '../core/types';
import { OFFICER_MAP, addLog, clamp, officersIn, roninIn, rngOf, saveRng, officerDef, regionDef } from '../core/state';
import { regionMods, canRecruitGuns } from './modifiers';
import { TECH_MAP, TECHS } from '../data/techs';
import { REGION_MAP } from '../data/regions';

export interface CmdResult { ok: boolean; key: string; params?: Record<string, string | number> }

export const COSTS = {
  farm: 300, commerce: 300, recruit: 250, train: 100, castle: 400, govern: 200,
  hire: 100, research: 300, rewardSmall: 300, rewardLarge: 800,
} as const;

function fail(key: string, params?: CmdResult['params']): CmdResult { return { ok: false, key, params }; }

/** 共同檢查：武將屬於該勢力、未行動、人在該區、該區屬於勢力 */
function check(state: GameState, faction: FactionId, officerId: string, region: RegionId, cost: number): CmdResult | OfficerState {
  const o = state.officers[officerId];
  if (!o || o.faction !== faction) return fail('cmd.err.notYours');
  if (o.acted) return fail('cmd.err.acted');
  if (o.injuredMonths > 0) return fail('cmd.err.injured');
  if (o.armyId) return fail('cmd.err.marching');
  if (o.region !== region) return fail('cmd.err.notHere');
  if (state.regions[region].owner !== faction) return fail('cmd.err.notOwned');
  if (state.factions[faction].gold < cost) return fail('cmd.err.gold', { need: cost });
  return o;
}
function isResult(x: CmdResult | OfficerState): x is CmdResult { return (x as CmdResult).key !== undefined; }

function spend(state: GameState, faction: FactionId, gold: number, o: OfficerState) {
  state.factions[faction].gold -= gold;
  o.acted = true;
  o.idleMonths = 0;
}

export function cmdFarm(state: GameState, f: FactionId, oid: string, rid: RegionId): CmdResult {
  const o = check(state, f, oid, rid, COSTS.farm); if (isResult(o)) return o;
  const d = officerDef(oid), r = state.regions[rid];
  const cap = regionDef(rid).init.kokudaka * 2;
  if (r.kokudaka >= cap) return fail('cmd.err.maxed');
  // 報酬遞減：越接近上限越難開發
  let gain = d.politics * 0.025 * (d.traits.includes('farmer') ? 1.5 : 1) * (1.2 - r.kokudaka / cap);
  gain = Math.min(gain, cap - r.kokudaka);
  r.kokudaka = +(r.kokudaka + gain).toFixed(1);
  spend(state, f, COSTS.farm, o);
  return { ok: true, key: 'cmd.ok.farm', params: { gain: gain.toFixed(1) } };
}

export function cmdCommerce(state: GameState, f: FactionId, oid: string, rid: RegionId): CmdResult {
  const o = check(state, f, oid, rid, COSTS.commerce); if (isResult(o)) return o;
  const d = officerDef(oid), r = state.regions[rid];
  const cap = 300;
  if (r.commerce >= cap) return fail('cmd.err.maxed');
  let gain = d.politics * 0.12 * (d.traits.includes('merchant') ? 1.5 : 1) * (1.2 - r.commerce / cap);
  gain = Math.min(gain, cap - r.commerce);
  r.commerce = Math.round(r.commerce + gain);
  spend(state, f, COSTS.commerce, o);
  return { ok: true, key: 'cmd.ok.commerce', params: { gain: Math.round(gain) } };
}

export function troopCap(state: GameState, rid: RegionId): number {
  return Math.round(state.regions[rid].kokudaka * 350);
}

/** 徵兵費用隨現有兵力上升（大軍養不起） */
export function recruitCost(state: GameState, rid: RegionId): number {
  const r = state.regions[rid];
  const cur = r.troops.ashigaru + r.troops.cavalry + r.troops.gun;
  return Math.round((COSTS.recruit + cur / 40) * regionMods(state, rid).recruitCostMul);
}

export function cmdRecruit(state: GameState, f: FactionId, oid: string, rid: RegionId): CmdResult {
  const mods = regionMods(state, rid);
  const r = state.regions[rid];
  const cur = r.troops.ashigaru + r.troops.cavalry + r.troops.gun;
  const cost = recruitCost(state, rid);
  const o = check(state, f, oid, rid, cost); if (isResult(o)) return o;
  const d = officerDef(oid);
  const cap = troopCap(state, rid);
  if (cur >= cap) return fail('cmd.err.troopCap', { cap });
  if (r.loyalty < 20) return fail('cmd.err.loyaltyLow');
  let n = Math.round(d.charm * 7 * (0.5 + r.loyalty / 100));
  if (d.traits.includes('inspiring')) n = Math.round(n * 1.3);
  n = Math.min(n, cap - cur);
  const cavShare = 0.1 + mods.cavalryBonus + (d.traits.includes('cavalry') ? 0.15 : 0);
  const gunShare = canRecruitGuns(state, f, rid) ? 0.1 + mods.gunBonus + (d.traits.includes('gunner') ? 0.15 : 0) : 0;
  const cav = Math.round(n * cavShare), gun = Math.round(n * gunShare);
  r.troops.cavalry += cav; r.troops.gun += gun; r.troops.ashigaru += n - cav - gun;
  // 新兵拉低訓練度
  r.training = Math.round((r.training * cur + 30 * n) / (cur + n));
  const noLoyaltyHit = state.factions[f].techs.includes('mil4');
  if (!noLoyaltyHit) r.loyalty = clamp(r.loyalty - 3, 0, 100);
  spend(state, f, cost, o);
  return { ok: true, key: 'cmd.ok.recruit', params: { n, cav, gun } };
}

export function cmdTrain(state: GameState, f: FactionId, oid: string, rid: RegionId): CmdResult {
  const o = check(state, f, oid, rid, COSTS.train); if (isResult(o)) return o;
  const d = officerDef(oid), r = state.regions[rid];
  if (r.training >= 100) return fail('cmd.err.maxed');
  const gain = Math.min(100 - r.training, Math.round((d.lead + d.valor) / 10));
  r.training += gain;
  spend(state, f, COSTS.train, o);
  return { ok: true, key: 'cmd.ok.train', params: { gain } };
}

export function cmdCastle(state: GameState, f: FactionId, oid: string, rid: RegionId): CmdResult {
  const o = check(state, f, oid, rid, COSTS.castle); if (isResult(o)) return o;
  const d = officerDef(oid), r = state.regions[rid];
  const cap = regionMods(state, rid).defenseCap;
  if (r.defense >= cap) return fail('cmd.err.maxed');
  const gain = Math.min(cap - r.defense, Math.round(d.politics * 0.15 * (d.traits.includes('builder') ? 2 : 1)));
  r.defense += gain;
  spend(state, f, COSTS.castle, o);
  return { ok: true, key: 'cmd.ok.castle', params: { gain } };
}

export function cmdGovern(state: GameState, f: FactionId, oid: string, rid: RegionId): CmdResult {
  const o = check(state, f, oid, rid, COSTS.govern); if (isResult(o)) return o;
  const d = officerDef(oid), r = state.regions[rid];
  if (r.loyalty >= 100) return fail('cmd.err.maxed');
  const gain = Math.min(100 - r.loyalty, Math.round(d.charm * 0.15 + (d.traits.includes('inspiring') ? 5 : 0)));
  r.loyalty += gain;
  spend(state, f, COSTS.govern, o);
  return { ok: true, key: 'cmd.ok.govern', params: { gain } };
}

/** 登用：區內浪人，或相鄰敵區忠誠 < 40 的武將（引抜） */
export function hireTargets(state: GameState, f: FactionId, rid: RegionId): OfficerState[] {
  const list = roninIn(state, rid);
  for (const adj of REGION_MAP[rid].adjacent) {
    const owner = state.regions[adj].owner;
    if (!owner || owner === f) continue;
    for (const o of officersIn(state, adj, owner)) {
      if (o.loyalty < 40 && o.rank !== 'daimyo' && o.rank !== 'heir') list.push(o);
    }
  }
  return list;
}

export function cmdHire(state: GameState, f: FactionId, oid: string, rid: RegionId, targetId: string): CmdResult {
  const o = check(state, f, oid, rid, COSTS.hire); if (isResult(o)) return o;
  const target = state.officers[targetId];
  if (!target || !hireTargets(state, f, rid).some(t => t.id === targetId)) return fail('cmd.err.badTarget');
  const d = officerDef(oid), td = officerDef(targetId);
  const rng = rngOf(state);
  const fame = state.factions[f].fame;
  let p = (d.charm + d.politics) / 200 * 0.7 + fame / 300;
  if (td.traits.includes('loyal') && target.faction) p *= 0.2;
  if (td.traits.includes('ambitious')) p += 0.15;
  if (target.faction) p *= (1 - target.loyalty / 50) + 0.1; // 引抜難度
  p = clamp(p, 0.05, 0.9);
  spend(state, f, COSTS.hire, o);
  const ok = rng.chance(p);
  saveRng(state, rng);
  if (!ok) return { ok: true, key: 'cmd.ok.hireFail', params: { name: td.name, p: Math.round(p * 100) } };
  const prevFaction = target.faction;
  target.faction = f; target.region = rid; target.rank = 'retainer';
  target.loyalty = clamp(50 + Math.round(d.charm / 5), 40, 75);
  target.acted = true; target.idleMonths = 0; target.clanTie = false;
  addLog(state, 'log.hired', { name: td.name, faction: f }, f, true);
  if (prevFaction) addLog(state, 'log.defected', { name: td.name, from: prevFaction, to: f }, prevFaction, true);
  return { ok: true, key: 'cmd.ok.hire', params: { name: td.name } };
}

export function availableTechs(state: GameState, f: FactionId): string[] {
  const have = state.factions[f].techs;
  return TECHS.filter(t => !have.includes(t.id) && (!t.requires || have.includes(t.requires))).map(t => t.id);
}

export function cmdResearch(state: GameState, f: FactionId, oid: string, rid: RegionId, techId: string): CmdResult {
  const o = check(state, f, oid, rid, COSTS.research); if (isResult(o)) return o;
  const fs = state.factions[f];
  if (!availableTechs(state, f).includes(techId)) return fail('cmd.err.badTarget');
  if (fs.research.tech !== techId) fs.research = { tech: techId, progress: 0 };
  const d = officerDef(oid);
  let pts = Math.round((d.intel + d.politics) / 2 * (d.traits.includes('scholar') ? 1.5 : 1));
  if (techId === 'mil2' && REGION_MAP[rid].bonuses.includes('early_gun')) pts = Math.round(pts * 1.5);
  fs.research.progress += pts;
  spend(state, f, COSTS.research, o);
  const cost = TECH_MAP[techId].cost;
  if (fs.research.progress >= cost) {
    fs.techs.push(techId);
    fs.research = { tech: null, progress: 0 };
    addLog(state, 'log.techDone', { tech: techId }, f, true);
    return { ok: true, key: 'cmd.ok.researchDone', params: { tech: techId } };
  }
  return { ok: true, key: 'cmd.ok.research', params: { pts, progress: fs.research.progress, cost } };
}

/** 賞賜：不消耗目標武將的行動，但消耗執行者（大名親自賞賜 → 用任何武將執行皆可） */
export function cmdReward(state: GameState, f: FactionId, oid: string, rid: RegionId, targetId: string, large: boolean): CmdResult {
  const cost = large ? COSTS.rewardLarge : COSTS.rewardSmall;
  const o = check(state, f, oid, rid, cost); if (isResult(o)) return o;
  const t = state.officers[targetId];
  if (!t || t.faction !== f) return fail('cmd.err.badTarget');
  const td = officerDef(targetId);
  const cap = td.traits.includes('ambitious') ? 80 : 100;
  const gain = large ? 15 : 7;
  const before = t.loyalty;
  t.loyalty = clamp(t.loyalty + gain, 0, cap);
  spend(state, f, cost, o);
  return { ok: true, key: 'cmd.ok.reward', params: { name: td.name, gain: t.loyalty - before } };
}

/** 移動武將到相鄰己方區域（不耗金，耗行動） */
export function cmdMove(state: GameState, f: FactionId, oid: string, rid: RegionId, to: RegionId): CmdResult {
  const o = check(state, f, oid, rid, 0); if (isResult(o)) return o;
  if (!REGION_MAP[rid].adjacent.includes(to) || state.regions[to].owner !== f) return fail('cmd.err.badTarget');
  o.region = to; o.acted = true; o.idleMonths = 0;
  return { ok: true, key: 'cmd.ok.move', params: { name: OFFICER_MAP[oid].name } };
}

/** 調兵：把本區部分兵力送到相鄰己方區（需一名武將押送，武將一併移動） */
export function cmdTransfer(state: GameState, f: FactionId, oid: string, rid: RegionId, to: RegionId, n: number): CmdResult {
  const o = check(state, f, oid, rid, 0); if (isResult(o)) return o;
  if (!REGION_MAP[rid].adjacent.includes(to) || state.regions[to].owner !== f) return fail('cmd.err.badTarget');
  const r = state.regions[rid], t = state.regions[to];
  const cur = r.troops.ashigaru + r.troops.cavalry + r.troops.gun;
  n = clamp(Math.round(n), 0, cur);
  if (n <= 0) return fail('cmd.err.badTarget');
  const ratio = n / cur;
  const mv = { ashigaru: Math.round(r.troops.ashigaru * ratio), cavalry: Math.round(r.troops.cavalry * ratio), gun: Math.round(r.troops.gun * ratio) };
  const tcur = t.troops.ashigaru + t.troops.cavalry + t.troops.gun;
  t.training = Math.round((t.training * tcur + r.training * n) / Math.max(1, tcur + n));
  for (const k of ['ashigaru', 'cavalry', 'gun'] as const) { r.troops[k] -= mv[k]; t.troops[k] += mv[k]; }
  o.region = to; o.acted = true; o.idleMonths = 0;
  return { ok: true, key: 'cmd.ok.transfer', params: { n } };
}

/** 雇用忍者眾（勢力級，不耗武將行動） */
export const NINJA_CLANS = ['iga', 'koga', 'fuma', 'togakure', 'negoro'] as const;
export function cmdHireNinja(state: GameState, f: FactionId): CmdResult {
  const fs = state.factions[f];
  const cost = 800 + fs.ninja.level * 800;
  if (fs.ninja.level >= 3) return fail('cmd.err.maxed');
  if (fs.gold < cost) return fail('cmd.err.gold', { need: cost });
  fs.gold -= cost;
  if (!fs.ninja.clan) {
    const rng = rngOf(state);
    fs.ninja.clan = rng.pick(NINJA_CLANS);
    saveRng(state, rng);
  }
  fs.ninja.level += 1;
  return { ok: true, key: 'cmd.ok.ninjaHired', params: { clan: fs.ninja.clan, level: fs.ninja.level } };
}
