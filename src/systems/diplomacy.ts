// 外交與婚姻。AI 的回應依威脅評估與關係值決定。
import type { GameState, FactionId } from '../core/types';
import { getDiplo, addLog, clamp, officerDef, regionsOf, factionTroops, rngOf, saveRng, neighbourRegions, officersOf, daimyoOf } from '../core/state';
import type { CmdResult } from './commands';

export const DIPLO_COSTS = { gift: 500, alliance: 300, truce: 200, marriage: 0, surrender: 0 } as const;

function envoy(state: GameState, f: FactionId, oid: string, cost: number): CmdResult | null {
  const o = state.officers[oid];
  if (!o || o.faction !== f) return { ok: false, key: 'cmd.err.notYours' };
  if (o.acted || o.armyId || o.injuredMonths > 0) return { ok: false, key: 'cmd.err.acted' };
  if (state.factions[f].gold < cost) return { ok: false, key: 'cmd.err.gold', params: { need: cost } };
  return null;
}
function useEnvoy(state: GameState, f: FactionId, oid: string, cost: number) {
  state.factions[f].gold -= cost;
  const o = state.officers[oid]; o.acted = true; o.idleMonths = 0;
}

/** 對方眼中「我」的威脅度：越大越不願結盟、越想停戰 */
export function threatOf(state: GameState, me: FactionId, them: FactionId): number {
  const mine = factionTroops(state, me), theirs = Math.max(1, factionTroops(state, them));
  const adjacent = neighbourRegions(state, them).some(r => state.regions[r].owner === me);
  return (mine / theirs) * (adjacent ? 1.5 : 0.7);
}

export function strongestFaction(state: GameState): FactionId {
  let best: FactionId = state.player, bestV = -1;
  for (const f of Object.values(state.factions)) {
    if (!f.alive) continue;
    const v = factionTroops(state, f.id) + regionsOf(state, f.id).length * 3000;
    if (v > bestV) { bestV = v; best = f.id; }
  }
  return best;
}

export function cmdGift(state: GameState, f: FactionId, oid: string, target: FactionId): CmdResult {
  const err = envoy(state, f, oid, DIPLO_COSTS.gift); if (err) return err;
  const d = officerDef(oid);
  const gain = Math.round(6 + d.politics / 12 + (d.traits.includes('diplomat') ? 5 : 0));
  const pair = getDiplo(state, f, target);
  pair.relation = clamp(pair.relation + gain, -100, 100);
  useEnvoy(state, f, oid, DIPLO_COSTS.gift);
  return { ok: true, key: 'cmd.ok.gift', params: { faction: target, gain } };
}

export function cmdAlliance(state: GameState, f: FactionId, oid: string, target: FactionId): CmdResult {
  const err = envoy(state, f, oid, DIPLO_COSTS.alliance); if (err) return err;
  const pair = getDiplo(state, f, target);
  if (pair.alliance && pair.alliance > 0) return { ok: false, key: 'cmd.err.alreadyAllied' };
  const d = officerDef(oid);
  const rng = rngOf(state);
  const threat = threatOf(state, f, target);
  const strongest = strongestFaction(state);
  // 對方越被最強勢力威脅，越願意與你結盟（除非你就是最強）
  let p = (pair.relation - 30) / 100 + d.politics / 300 + state.factions[f].credit / 400;
  if (strongest !== f && strongest !== target) p += 0.15;
  if (strongest === f) p -= 0.25;
  p -= Math.max(0, threat - 1.5) * 0.2;
  if (d.traits.includes('diplomat')) p += 0.1;
  p = clamp(p, 0.02, 0.9);
  useEnvoy(state, f, oid, DIPLO_COSTS.alliance);
  const ok = rng.chance(p); saveRng(state, rng);
  if (!ok) { pair.relation = clamp(pair.relation - 3, -100, 100); return { ok: true, key: 'cmd.ok.allianceRefused', params: { faction: target, p: Math.round(p * 100) } }; }
  pair.alliance = 24; pair.truce = undefined;
  pair.relation = clamp(pair.relation + 10, -100, 100);
  addLog(state, 'log.alliance', { a: f, b: target }, f, true);
  addLog(state, 'log.alliance', { a: f, b: target }, target, true);
  return { ok: true, key: 'cmd.ok.alliance', params: { faction: target } };
}

export function cmdTruce(state: GameState, f: FactionId, oid: string, target: FactionId): CmdResult {
  const err = envoy(state, f, oid, DIPLO_COSTS.truce); if (err) return err;
  const pair = getDiplo(state, f, target);
  if ((pair.truce && pair.truce > 0) || (pair.alliance && pair.alliance > 0)) return { ok: false, key: 'cmd.err.alreadyTruce' };
  const d = officerDef(oid);
  const rng = rngOf(state);
  const threat = threatOf(state, f, target);
  // 對方佔上風時不願停戰
  let p = 0.35 + pair.relation / 200 + d.politics / 400 + (threat > 1.2 ? 0.25 : threat < 0.6 ? -0.3 : 0);
  if (d.traits.includes('diplomat')) p += 0.1;
  p = clamp(p, 0.05, 0.9);
  useEnvoy(state, f, oid, DIPLO_COSTS.truce);
  const ok = rng.chance(p); saveRng(state, rng);
  if (!ok) return { ok: true, key: 'cmd.ok.truceRefused', params: { faction: target, p: Math.round(p * 100) } };
  pair.truce = 12;
  addLog(state, 'log.truce', { a: f, b: target }, f, true);
  addLog(state, 'log.truce', { a: f, b: target }, target, true);
  return { ok: true, key: 'cmd.ok.truce', params: { faction: target } };
}

/** 婚姻同盟：嫁姬給他國大名家，24 個月同盟 */
export function cmdMarriageAlliance(state: GameState, f: FactionId, oid: string, target: FactionId): CmdResult {
  const err = envoy(state, f, oid, 0); if (err) return err;
  const fs = state.factions[f];
  if (fs.princesses <= 0) return { ok: false, key: 'cmd.err.noPrincess' };
  const pair = getDiplo(state, f, target);
  if (pair.marriage && pair.marriage > 0) return { ok: false, key: 'cmd.err.alreadyAllied' };
  const d = officerDef(oid);
  const rng = rngOf(state);
  let p = 0.5 + pair.relation / 150 + d.charm / 400 + (strongestFaction(state) === f ? -0.2 : 0.05);
  p = clamp(p, 0.1, 0.95);
  useEnvoy(state, f, oid, 0);
  const ok = rng.chance(p); saveRng(state, rng);
  if (!ok) return { ok: true, key: 'cmd.ok.marriageRefused', params: { faction: target } };
  fs.princesses -= 1;
  pair.marriage = 24; pair.alliance = Math.max(pair.alliance ?? 0, 24); pair.truce = undefined;
  pair.relation = clamp(pair.relation + 30, -100, 100);
  addLog(state, 'log.marriageAlliance', { a: f, b: target }, f, true);
  addLog(state, 'log.marriageAlliance', { a: f, b: target }, target, true);
  return { ok: true, key: 'cmd.ok.marriageAlliance', params: { faction: target } };
}

/** 嫁姬給家臣：忠誠 +25，成為一門 */
export function cmdMarryRetainer(state: GameState, f: FactionId, targetId: string): CmdResult {
  const fs = state.factions[f];
  if (fs.princesses <= 0) return { ok: false, key: 'cmd.err.noPrincess' };
  const t = state.officers[targetId];
  if (!t || t.faction !== f || t.rank === 'daimyo' || t.clanTie) return { ok: false, key: 'cmd.err.badTarget' };
  fs.princesses -= 1;
  t.clanTie = true;
  t.loyalty = clamp(t.loyalty + 25, 0, 100);
  addLog(state, 'log.marryRetainer', { name: officerDef(targetId).name }, f);
  return { ok: true, key: 'cmd.ok.marryRetainer', params: { name: officerDef(targetId).name } };
}

/** 勸降：對方只剩 1 區且兵力不足我方 1/4 */
export function canDemandSurrender(state: GameState, f: FactionId, target: FactionId): boolean {
  if (!state.factions[target].alive || target === f) return false;
  const theirs = regionsOf(state, target);
  if (theirs.length !== 1) return false;
  if (!neighbourRegions(state, f).includes(theirs[0].id)) return false;
  return factionTroops(state, target) * 4 < factionTroops(state, f);
}

export function cmdDemandSurrender(state: GameState, f: FactionId, oid: string, target: FactionId): CmdResult {
  const err = envoy(state, f, oid, 0); if (err) return err;
  if (!canDemandSurrender(state, f, target)) return { ok: false, key: 'cmd.err.badTarget' };
  const d = officerDef(oid);
  const pair = getDiplo(state, f, target);
  const td = daimyoOf(state, target);
  const tdDef = td ? officerDef(td.id) : null;
  const rng = rngOf(state);
  let p = 0.3 + pair.relation / 200 + d.charm / 400 + state.factions[f].fame / 400;
  if (tdDef?.personality === 'aggressive') p -= 0.2;
  if (tdDef?.personality === 'defensive') p += 0.1;
  p = clamp(p, 0.05, 0.85);
  useEnvoy(state, f, oid, 0);
  const ok = rng.chance(p);
  if (!ok) { saveRng(state, rng); pair.relation = clamp(pair.relation - 10, -100, 100); return { ok: true, key: 'cmd.ok.surrenderRefused', params: { faction: target } }; }
  // 吸收：領地、武將（忠誠 50）、金
  for (const r of regionsOf(state, target)) r.owner = f;
  for (const o of officersOf(state, target)) {
    o.faction = f; o.rank = 'retainer'; o.loyalty = 50 + rng.int(0, 15); o.clanTie = false; o.armyId = undefined;
  }
  state.factions[f].gold += state.factions[target].gold;
  state.factions[target].alive = false;
  state.armies = state.armies.filter(a => a.faction !== target);
  state.factions[f].fame += 8;
  saveRng(state, rng);
  addLog(state, 'log.absorbed', { faction: target, by: f }, undefined, true);
  return { ok: true, key: 'cmd.ok.surrender', params: { faction: target } };
}

/** 解除同盟：信用 -15（背盟攻擊則 -30，由 military 判定） */
export function cmdBreakAlliance(state: GameState, f: FactionId, target: FactionId): CmdResult {
  const pair = getDiplo(state, f, target);
  if (!(pair.alliance && pair.alliance > 0) && !(pair.marriage && pair.marriage > 0)) return { ok: false, key: 'cmd.err.badTarget' };
  pair.alliance = undefined; pair.marriage = undefined;
  pair.relation = clamp(pair.relation - 40, -100, 100);
  const fs = state.factions[f];
  fs.credit = clamp(fs.credit - 15, 0, 100);
  for (const k of Object.keys(state.diplomacy)) {
    if (k.includes(f)) state.diplomacy[k].relation = clamp(state.diplomacy[k].relation - 5, -100, 100);
  }
  addLog(state, 'log.breakAlliance', { a: f, b: target }, undefined, true);
  return { ok: true, key: 'cmd.ok.breakAlliance', params: { faction: target } };
}

/** 每月：同盟/停戰倒數、關係自然回歸、信用緩慢恢復 */
export function diplomacyMonthly(state: GameState): void {
  for (const [key, pair] of Object.entries(state.diplomacy)) {
    const [a, b] = key.split('|') as [FactionId, FactionId];
    if (pair.alliance !== undefined) { pair.alliance -= 1; if (pair.alliance <= 0) { pair.alliance = undefined; addLog(state, 'log.allianceExpired', { a, b }, a); addLog(state, 'log.allianceExpired', { a, b }, b); } }
    if (pair.marriage !== undefined) { pair.marriage -= 1; if (pair.marriage <= 0) pair.marriage = undefined; }
    if (pair.truce !== undefined) { pair.truce -= 1; if (pair.truce <= 0) pair.truce = undefined; }
    // 關係緩慢回歸 0
    if (pair.relation > 0) pair.relation -= 0.5; else if (pair.relation < 0) pair.relation += 0.5;
  }
  for (const fs of Object.values(state.factions)) fs.credit = clamp(fs.credit + 0.5, 0, 100);
}
