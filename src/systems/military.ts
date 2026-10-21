// 出陣、行軍、到達處理
import type { GameState, FactionId, RegionId, Army } from '../core/types';
import { addLog, canAttack, isSnowed, officerDef, totalTroops, rngOf, saveRng, officersIn, clamp } from '../core/state';
import { REGION_MAP } from '../data/regions';
import { createBattle, autoResolve, finishBattle, captureRegion } from './battle';
import type { CmdResult } from './commands';

let armySeq = 0;

export function marchTargets(state: GameState, f: FactionId, from: RegionId): RegionId[] {
  return REGION_MAP[from].adjacent.filter(t => {
    const owner = state.regions[t].owner;
    return owner !== f && canAttack(state, f, owner) && !isSnowed(state, t) && !isSnowed(state, from);
  });
}

/** 出陣：主將 + 最多 2 副將，帶走部分兵力。到達需 1 回合。 */
export function cmdMarch(state: GameState, f: FactionId, from: RegionId, target: RegionId, officerIds: string[], n: number): CmdResult {
  const r = state.regions[from];
  if (r.owner !== f) return { ok: false, key: 'cmd.err.notOwned' };
  if (!marchTargets(state, f, from).includes(target)) return { ok: false, key: 'cmd.err.badTarget' };
  if (officerIds.length < 1 || officerIds.length > 3) return { ok: false, key: 'cmd.err.officerCount' };
  for (const id of officerIds) {
    const o = state.officers[id];
    if (!o || o.faction !== f || o.region !== from || o.acted || o.armyId || o.injuredMonths > 0) return { ok: false, key: 'cmd.err.acted' };
  }
  const cur = totalTroops(r);
  n = clamp(Math.round(n), 0, cur);
  if (n < 300) return { ok: false, key: 'cmd.err.tooFew' };
  const rice = Math.round(n * 0.3); // 出征攜糧（從勢力糧倉支出）
  if (state.factions[f].rice < rice) return { ok: false, key: 'cmd.err.rice', params: { need: rice } };
  state.factions[f].rice -= rice;
  const ratio = n / cur;
  const troops = { ashigaru: Math.round(r.troops.ashigaru * ratio), cavalry: Math.round(r.troops.cavalry * ratio), gun: Math.round(r.troops.gun * ratio) };
  for (const k of ['ashigaru', 'cavalry', 'gun'] as const) r.troops[k] -= troops[k];
  const commander = officerIds.slice().sort((a, b) => officerDef(b).lead - officerDef(a).lead)[0];
  const army: Army = {
    id: `a${state.turn}_${f}_${armySeq++}`, faction: f, from, target, troops, training: r.training,
    commander, officers: officerIds, eta: 1,
  };
  state.armies.push(army);
  for (const id of officerIds) { state.officers[id].acted = true; state.officers[id].armyId = army.id; state.officers[id].idleMonths = 0; }
  addLog(state, 'log.march', { faction: f, from, target, n }, f);
  return { ok: true, key: 'cmd.ok.march', params: { n, target } };
}

/** 取消尚未出發的軍團（同回合內）：兵與武將回歸 */
export function cancelMarch(state: GameState, armyId: string): void {
  const i = state.armies.findIndex(a => a.id === armyId);
  if (i < 0) return;
  const a = state.armies[i];
  const r = state.regions[a.from];
  for (const k of ['ashigaru', 'cavalry', 'gun'] as const) r.troops[k] += a.troops[k];
  state.factions[a.faction].rice += Math.round(totalTroops(a) * 0.3);
  for (const id of a.officers) { state.officers[id].acted = false; state.officers[id].armyId = undefined; }
  state.armies.splice(i, 1);
}

/**
 * 處理所有軍團到達。玩家參與的戰鬥推進 battleQueue，由 UI 處理；其餘自動結算。
 */
export function processArrivals(state: GameState): void {
  const rng = rngOf(state);
  // 先依攻方戰力排序，避免同一區多軍團時結果依插入順序
  const arriving = state.armies.filter(a => a.eta <= 1);
  for (const a of state.armies) a.eta -= 1;
  for (const army of arriving) {
    if (!state.armies.includes(army)) continue; // 已在稍早的戰鬥中消滅
    if (!state.factions[army.faction].alive) { state.armies.splice(state.armies.indexOf(army), 1); continue; }
    const region = state.regions[army.target];
    const owner = region.owner;
    // 行軍途中目標已變成己方 → 併入駐軍
    if (owner === army.faction) { merge(state, army); continue; }
    // 行軍途中變成同盟 → 撤回
    if (owner && !canAttack(state, army.faction, owner)) { returnHome(state, army); continue; }
    // 無人防守 → 直接佔領
    const defenders = owner ? officersIn(state, army.target, owner) : [];
    if (totalTroops(region) <= 0 && defenders.length === 0) {
      captureRegion(state, army.target, army.faction, army.troops, army.training, army.officers, rng);
      addLog(state, 'log.captured', { region: army.target, faction: army.faction, from: owner ?? '' }, army.faction, true);
      if (owner) addLog(state, 'log.lost', { region: army.target, faction: owner, to: army.faction }, owner, true);
      state.armies.splice(state.armies.indexOf(army), 1);
      continue;
    }
    // 守方若兵力為 0 但有武將：以 200 名親衛隊應戰
    if (totalTroops(region) <= 0) region.troops.ashigaru = 200;
    const battle = createBattle(state, army, rng);
    if (owner) {
      // 背盟檢查（理論上 canAttack 已擋，但保險）
      const playerInvolved = army.faction === state.player || owner === state.player;
      if (playerInvolved) { state.battleQueue.push(battle); continue; }
    }
    autoResolve(battle, rng);
    saveRng(state, rng);
    finishBattle(state, battle);
  }
  saveRng(state, rng);
}

function merge(state: GameState, army: Army) {
  const r = state.regions[army.target];
  const cur = totalTroops(r), n = totalTroops(army);
  r.training = Math.round((r.training * cur + army.training * n) / Math.max(1, cur + n));
  for (const k of ['ashigaru', 'cavalry', 'gun'] as const) r.troops[k] += army.troops[k];
  for (const id of army.officers) { state.officers[id].region = army.target; state.officers[id].armyId = undefined; }
  state.armies.splice(state.armies.indexOf(army), 1);
}

function returnHome(state: GameState, army: Army) {
  const r = state.regions[army.from];
  if (r.owner === army.faction) {
    for (const k of ['ashigaru', 'cavalry', 'gun'] as const) r.troops[k] += army.troops[k];
    for (const id of army.officers) { state.officers[id].region = army.from; state.officers[id].armyId = undefined; }
  } else {
    for (const id of army.officers) state.officers[id].armyId = undefined;
  }
  state.armies.splice(state.armies.indexOf(army), 1);
}
