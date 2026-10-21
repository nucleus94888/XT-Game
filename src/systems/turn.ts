// 回合流程：endTurn → (AI、行軍到達) → 玩家戰鬥 → completeTurn（月結算、推進月份）
import type { GameState, FactionId, OfficerState } from '../core/types';
import { addLog, clamp, officerDef, officersOf, regionsOf, rngOf, saveRng, totalTroops, daimyoOf, aliveFactions, OFFICER_MAP } from '../core/state';
import { REGIONS, REGION_MAP } from '../data/regions';
import { FACTIONS } from '../data/factions';
import { regionMods } from './modifiers';
import { processArrivals } from './military';
import { diplomacyMonthly } from './diplomacy';
import { aiTurn } from './ai';
import { monthlyEvents } from './events';
import { tagSpecialBattle } from './events';

export const SALARY = 50;
export const RICE_PER_TROOP = 0.1;

/** 玩家按下「結束回合」 */
export function endTurn(state: GameState): void {
  if (state.gameOver) return;
  // 1. 軍團到達（含玩家本回合下令的出陣）
  processArrivals(state);
  for (const b of state.battleQueue) tagSpecialBattle(state, b);
  // 2. AI 行動（所有非玩家勢力）
  for (const f of aliveFactions(state)) if (f !== state.player) aiTurn(state, f);
  // 3. AI 出陣的軍團也可能立即到達（eta=1 → 下回合到達，故此處不處理）
  if (state.battleQueue.length === 0) completeTurn(state);
}

/** 所有玩家戰鬥處理完後 */
export function completeTurn(state: GameState): void {
  if (state.gameOver) return;
  monthlySettlement(state);
  advanceMonth(state);
  checkVictory(state);
}

function advanceMonth(state: GameState) {
  state.turn += 1;
  state.month += 1;
  if (state.month > 12) { state.month = 1; state.year += 1; }
  for (const o of Object.values(state.officers)) {
    if (!o.acted) o.idleMonths += 1; else o.idleMonths = 0;
    o.acted = false;
    if (o.injuredMonths > 0) o.injuredMonths -= 1;
  }
}

export function monthlySettlement(state: GameState): void {
  const rng = rngOf(state);
  const harvestMonth = 9;
  const yearFactor = (state.flags[`harvest${state.year}`] as number | undefined) ?? (() => {
    const v = +rng.range(0.75, 1.25).toFixed(2); state.flags[`harvest${state.year}`] = v; return v;
  })();

  for (const fid of aliveFactions(state)) {
    const fs = state.factions[fid];
    const regions = regionsOf(state, fid);
    const officers = officersOf(state, fid);
    let income = 0;
    let riceNeed = 0, harvest = 0;
    for (const r of regions) {
      const mods = regionMods(state, r.id);
      income += r.commerce * 7 * mods.goldMul;
      // 檢地：石高亦產金
      if (fs.techs.includes('agri4')) income += r.kokudaka * 4;
      // 兵的軍餉（金）
      income -= totalTroops(r) * 0.025;
      riceNeed += totalTroops(r) * RICE_PER_TROOP;
      if (state.month === harvestMonth) harvest += r.kokudaka * 400 * mods.riceMul * yearFactor;
    }
    for (const a of state.armies) if (a.faction === fid) riceNeed += totalTroops(a) * RICE_PER_TROOP * 1.5;
    // 糧：全勢力共用；不足 → 各區逃兵、民忠下降
    riceNeed = Math.round(riceNeed);
    if (fs.rice >= riceNeed) fs.rice -= riceNeed;
    else {
      fs.rice = 0;
      let deserted = 0;
      for (const r of regions) { const d = Math.round(totalTroops(r) * 0.1); shrink(r.troops, d); deserted += d; r.loyalty = clamp(r.loyalty - 4, 0, 100); }
      addLog(state, 'log.starving', { n: deserted }, fid, fid === state.player);
    }
    if (state.month === harvestMonth) {
      harvest = Math.round(harvest);
      const cap = regions.reduce((s, r) => s + r.kokudaka * 2500, 0);
      fs.rice = Math.min(fs.rice + harvest, Math.round(cap));
      addLog(state, 'log.harvest', { gain: harvest, factor: yearFactor }, fid, fid === state.player);
    }
    for (const r of regions) {
      const mods = regionMods(state, r.id);
      // 民忠
      r.loyalty = clamp(r.loyalty + mods.loyaltyDrift, 0, 100);
      if (r.loyalty < 30 && rng.chance(0.2)) {
        const lost = Math.round(totalTroops(r) * 0.1);
        shrink(r.troops, lost);
        r.commerce = Math.max(10, r.commerce - 5);
        r.loyalty = clamp(r.loyalty + 10, 0, 100);
        addLog(state, 'log.ikki', { region: r.id, n: lost }, fid, true);
      }
      // 訓練度衰退
      r.training = Math.max(30, r.training - 1);
    }
    fs.gold += Math.round(income);
    // 俸祿
    const salary = officers.length * SALARY;
    fs.gold -= salary;
    if (fs.gold < 0) {
      fs.gold = 0;
      for (const o of officers) if (o.rank !== 'daimyo') o.loyalty = clamp(o.loyalty - 2, 0, 100);
      addLog(state, 'log.unpaid', {}, fid, fid === state.player);
    }
    // 忍者維持費
    if (fs.ninja.level > 0) fs.gold = Math.max(0, fs.gold - fs.ninja.level * 100);
    // 家臣忠誠
    for (const o of officers) officerLoyaltyMonthly(state, o, fid);
    // 叛離
    for (const o of officers) {
      const d = officerDef(o.id);
      if (o.rank === 'daimyo' || o.rank === 'heir' || d.traits.includes('loyal')) continue;
      if (o.loyalty < 30 && rng.chance(0.12)) {
        // 投奔相鄰最強敵對勢力，否則出奔為浪人
        const adjFactions = new Set<FactionId>();
        for (const adj of REGION_MAP[o.region].adjacent) { const ow = state.regions[adj].owner; if (ow && ow !== fid) adjFactions.add(ow); }
        const to = [...adjFactions][0];
        if (to) {
          const dest = REGION_MAP[o.region].adjacent.find(a => state.regions[a].owner === to)!;
          // 帶走部分駐軍
          const r = state.regions[o.region];
          const taken = d.traits.includes('ambitious') ? Math.round(totalTroops(r) * 0.15) : 0;
          shrink(r.troops, taken);
          const dr = state.regions[dest]; dr.troops.ashigaru += taken;
          o.faction = to; o.region = dest; o.rank = 'retainer'; o.loyalty = 55; o.clanTie = false; o.armyId = undefined;
          addLog(state, 'log.betrayed', { name: d.name, to, n: taken }, fid, true);
          addLog(state, 'log.joined', { name: d.name, from: fid }, to, true);
        } else {
          o.faction = null; o.rank = 'ronin'; o.loyalty = 40; o.armyId = undefined;
          addLog(state, 'log.leftService', { name: d.name }, fid, true);
        }
      }
    }
    // 姬
    if (state.month === 1 && state.year % 3 === 1 && daimyoOf(state, fid)) fs.princesses += 1;
  }

  // 死亡（所有武將，含在野）
  for (const o of Object.values(state.officers)) {
    if (!o.alive) continue;
    if (state.year >= o.deathYear && rng.chance(1 / 6)) {
      o.alive = false;
      const d = OFFICER_MAP[o.id];
      if (o.faction) addLog(state, 'log.died', { name: d.name, age: state.year - d.birth }, o.faction, o.rank === 'daimyo' || o.faction === state.player);
      if (o.armyId) {
        const army = state.armies.find(a => a.id === o.armyId);
        if (army) { army.officers = army.officers.filter(x => x !== o.id); army.commander = army.officers[0] ?? army.commander; }
      }
      if (o.rank === 'daimyo' && o.faction) succession(state, o.faction);
    }
  }

  diplomacyMonthly(state);
  monthlyEvents(state, rng);
  saveRng(state, rng);
}

function shrink(t: { ashigaru: number; cavalry: number; gun: number }, n: number) {
  const total = t.ashigaru + t.cavalry + t.gun;
  if (total <= 0 || n <= 0) return;
  const ratio = Math.min(1, n / total);
  t.ashigaru -= Math.round(t.ashigaru * ratio); t.cavalry -= Math.round(t.cavalry * ratio); t.gun -= Math.round(t.gun * ratio);
}

function officerLoyaltyMonthly(state: GameState, o: OfficerState, fid: FactionId) {
  if (o.rank === 'daimyo') { o.loyalty = 100; return; }
  const d = officerDef(o.id);
  let delta = 0;
  if (o.idleMonths >= 6) delta -= 1;
  // 與大名相性：性格相同 +，相反 -
  const dm = daimyoOf(state, fid);
  if (dm) {
    const dp = officerDef(dm.id).personality, op = d.personality;
    if (dp && op) delta += dp === op ? 0.3 : (dp === 'aggressive' && op === 'defensive') || (dp === 'defensive' && op === 'aggressive') ? -0.5 : 0;
    // 大名魅力高 → 微幅回升
    if (officerDef(dm.id).charm >= 85 && o.loyalty < 70) delta += 0.5;
  }
  if (o.clanTie && o.loyalty < 80) delta += 0.5;
  let v = o.loyalty + delta;
  if (d.traits.includes('loyal')) v = Math.max(v, 70);
  if (d.traits.includes('ambitious')) v = Math.min(v, 80);
  o.loyalty = clamp(+v.toFixed(1), 0, 100);
}

export function succession(state: GameState, fid: FactionId): void {
  const officers = officersOf(state, fid).filter(o => o.alive);
  let heir = officers.find(o => o.rank === 'heir');
  if (!heir) heir = officers.filter(o => o.clanTie).sort((a, b) => b.loyalty - a.loyalty)[0];
  let penalty = 0;
  if (!heir) { heir = officers.sort((a, b) => b.loyalty - a.loyalty)[0]; penalty = 15; }
  if (!heir) {
    // 無人繼承：勢力消滅，領地無主
    state.factions[fid].alive = false;
    for (const r of regionsOf(state, fid)) r.owner = null;
    state.armies = state.armies.filter(a => a.faction !== fid);
    addLog(state, 'log.factionExtinct', { faction: fid }, undefined, true);
    if (fid === state.player) state.gameOver = { winner: null, reason: 'noHeir' };
    return;
  }
  heir.rank = 'daimyo'; heir.loyalty = 100; heir.clanTie = true;
  for (const o of officers) if (o !== heir && o.rank !== 'daimyo') o.loyalty = clamp(o.loyalty - 5 - penalty, 0, 100);
  // 指定新繼承人：一門中最年輕且 ≥15 歲者（簡化）
  const next = officers.filter(o => o !== heir && o.clanTie).sort((a, b) => officerDef(b.id).birth - officerDef(a.id).birth)[0];
  if (next) next.rank = 'heir';
  addLog(state, 'log.succession', { faction: fid, name: officerDef(heir.id).name }, fid, true);
}

export function checkVictory(state: GameState): void {
  const p = state.player;
  const mine = regionsOf(state, p);
  if (mine.length === 0 || !state.factions[p].alive) { state.gameOver = { winner: null, reason: 'defeated' }; return; }
  if (mine.length === REGIONS.length) { state.gameOver = { winner: p, reason: 'unify' }; return; }
  const prev = (state.flags.playerRegions as number | undefined) ?? mine.length;
  if (mine.length < prev) state.flags.lastLossTurn = state.turn;
  state.flags.playerRegions = mine.length;
  const lastLoss = (state.flags.lastLossTurn as number | undefined) ?? -99;
  if (state.regions.kinai.owner === p && mine.length >= 11 && state.turn - lastLoss >= 12) {
    state.gameOver = { winner: p, reason: 'shogun' };
  }
  if (state.year >= 1600) state.gameOver = { winner: null, reason: 'timeout' };
}

export function factionName(id: FactionId): string { return FACTIONS.find(f => f.id === id)?.name ?? id; }
