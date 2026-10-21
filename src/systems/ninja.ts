// 忍者行動：由一名武將統籌（智謀決定成功率），需先雇用忍者眾
import type { GameState, FactionId, RegionId } from '../core/types';
import { addLog, clamp, officerDef, officersIn, rngOf, saveRng, getDiplo } from '../core/state';
import { REGION_MAP } from '../data/regions';
import type { CmdResult } from './commands';

export type NinjaAction = 'spy' | 'rumor' | 'sabotage' | 'incite' | 'assassinate';
export const NINJA_COSTS: Record<NinjaAction, number> = { spy: 200, rumor: 400, sabotage: 500, incite: 400, assassinate: 1500 };

/** 可行動的目標區：與我方任一區相鄰的敵區（忍者眾等級 2 以上可達兩格） */
export function ninjaTargets(state: GameState, f: FactionId): RegionId[] {
  const level = state.factions[f].ninja.level;
  const set = new Set<RegionId>();
  const mine = Object.values(state.regions).filter(r => r.owner === f).map(r => r.id);
  for (const id of mine) for (const adj of REGION_MAP[id].adjacent) {
    if (state.regions[adj].owner !== f && state.regions[adj].owner) set.add(adj);
    if (level >= 2) for (const adj2 of REGION_MAP[adj].adjacent) {
      if (state.regions[adj2].owner !== f && state.regions[adj2].owner) set.add(adj2);
    }
  }
  return [...set];
}

export function cmdNinja(state: GameState, f: FactionId, oid: string, action: NinjaAction, target: RegionId, targetOfficer?: string): CmdResult {
  const fs = state.factions[f];
  if (fs.ninja.level <= 0) return { ok: false, key: 'cmd.err.noNinja' };
  const o = state.officers[oid];
  if (!o || o.faction !== f) return { ok: false, key: 'cmd.err.notYours' };
  if (o.acted || o.armyId || o.injuredMonths > 0) return { ok: false, key: 'cmd.err.acted' };
  const cost = NINJA_COSTS[action];
  if (fs.gold < cost) return { ok: false, key: 'cmd.err.gold', params: { need: cost } };
  if (!ninjaTargets(state, f).includes(target)) return { ok: false, key: 'cmd.err.badTarget' };
  const region = state.regions[target];
  const owner = region.owner as FactionId;
  const d = officerDef(oid);
  const rng = rngOf(state);

  // 成功率
  let p = 0.3 + d.intel / 250 + fs.ninja.level * 0.1 + (d.traits.includes('ninja_master') ? 0.2 : 0);
  // 守方有忍者頭目駐守 → 減半
  const guards = officersIn(state, target, owner);
  if (guards.some(g => officerDef(g.id).traits.includes('ninja_master'))) p *= 0.5;
  if (action === 'assassinate') p = clamp(p * 0.15, 0.02, 0.2);
  p = clamp(p, 0.05, 0.9);

  fs.gold -= cost; o.acted = true; o.idleMonths = 0;
  const ok = rng.chance(p);
  let result: CmdResult;
  if (!ok) {
    // 失敗：被識破，關係惡化
    const pair = getDiplo(state, f, owner);
    pair.relation = clamp(pair.relation - (action === 'assassinate' ? 30 : 8), -100, 100);
    if (action === 'assassinate') fs.credit = clamp(fs.credit - 10, 0, 100);
    addLog(state, 'log.ninjaCaught', { faction: f, region: target }, owner, true);
    result = { ok: true, key: 'cmd.ok.ninjaFail', params: { action, p: Math.round(p * 100) } };
  } else {
    switch (action) {
      case 'spy':
        fs.intel[target] = state.turn + 6;
        result = { ok: true, key: 'cmd.ok.spy', params: { region: target } };
        break;
      case 'rumor': {
        const pool = guards.filter(g => g.rank !== 'daimyo');
        const t = targetOfficer && pool.some(g => g.id === targetOfficer) ? state.officers[targetOfficer] : pool.length ? rng.pick(pool) : null;
        if (!t) { result = { ok: true, key: 'cmd.ok.rumorNoTarget' }; break; }
        const td = officerDef(t.id);
        const drop = td.traits.includes('loyal') ? 0 : rng.int(5, 15);
        t.loyalty = clamp(t.loyalty - drop, td.traits.includes('loyal') ? 70 : 0, 100);
        result = { ok: true, key: 'cmd.ok.rumor', params: { name: td.name, drop } };
        break;
      }
      case 'sabotage': {
        const drop = rng.int(10, 20);
        region.defense = clamp(region.defense - drop, 0, 100);
        result = { ok: true, key: 'cmd.ok.sabotage', params: { region: target, drop } };
        break;
      }
      case 'incite': {
        const drop = rng.int(8, 14);
        region.loyalty = clamp(region.loyalty - drop, 0, 100);
        result = { ok: true, key: 'cmd.ok.incite', params: { region: target, drop } };
        break;
      }
      case 'assassinate': {
        const pool = guards;
        const t = targetOfficer && pool.some(g => g.id === targetOfficer) ? state.officers[targetOfficer] : pool.length ? rng.pick(pool) : null;
        if (!t) { result = { ok: true, key: 'cmd.ok.rumorNoTarget' }; break; }
        t.alive = false;
        addLog(state, 'log.assassinated', { name: officerDef(t.id).name }, owner, true);
        addLog(state, 'log.assassinated', { name: officerDef(t.id).name }, f, true);
        result = { ok: true, key: 'cmd.ok.assassinate', params: { name: officerDef(t.id).name } };
        break;
      }
    }
  }
  saveRng(state, rng);
  return result;
}
