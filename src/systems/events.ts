// 歷史事件：條件觸發。可在設定關閉（flags.noHistory）。
import type { GameState, BattleState } from '../core/types';
import { addLog, clamp, officerDef, totalTroops } from '../core/state';
import type { Rng } from '../core/rng';

/** 桶狹間：今川大軍攻尾張、織田為玩家且兵力不到對方一半 → 戰鬥前可選奇襲 */
export function tagSpecialBattle(state: GameState, b: BattleState): void {
  if (state.flags.noHistory) return;
  if (b.attacker.faction === 'imagawa' && b.defender.faction === 'oda' && b.region === 'owari' && !state.flags.okehazamaDone) {
    if (totalTroops(b.attacker) >= totalTroops(b.defender) * 1.8 && b.attacker.officers.includes('imagawa_yoshimoto')) {
      b.special = 'okehazama';
    }
  }
}

/** 執行奇襲。回傳是否成功。成功：今川軍潰散、義元討死；失敗：織田士氣大減。 */
export function attemptOkehazama(state: GameState, b: BattleState, rng: Rng): boolean {
  state.flags.okehazamaDone = true;
  b.special = undefined;
  const cmd = b.defender.commander ? officerDef(b.defender.commander) : null;
  const valor = cmd?.valor ?? 50;
  const p = clamp(0.5 + (valor - 60) / 200 + (b.weather === 'rain' ? 0.25 : 0), 0.25, 0.92);
  if (rng.chance(p)) {
    const A = b.attacker;
    const loss = Math.round(totalTroops(A) * 0.5);
    const ratio = loss / Math.max(1, totalTroops(A));
    A.troops.ashigaru -= Math.round(A.troops.ashigaru * ratio);
    A.troops.cavalry -= Math.round(A.troops.cavalry * ratio);
    A.troops.gun -= Math.round(A.troops.gun * ratio);
    A.morale = 15;
    const y = state.officers['imagawa_yoshimoto'];
    if (y) { y.alive = false; y.armyId = undefined; A.officers = A.officers.filter(x => x !== 'imagawa_yoshimoto'); }
    A.commander = A.officers.length ? A.officers[0] : null;
    b.defender.morale = 130;
    b.rounds.push({ round: 0, atkTactic: 'hold', defTactic: 'charge', atkLoss: loss, defLoss: 0, atkMorale: A.morale, defMorale: 130, notes: ['battle.note.okehazamaWin'] });
    addLog(state, 'log.okehazamaWin', {}, 'oda', true);
    addLog(state, 'log.okehazamaWin', {}, 'imagawa', true);
    state.factions.oda.fame += 25;
    return true;
  }
  b.defender.morale = clamp(b.defender.morale - 15, 10, 130);
  b.rounds.push({ round: 0, atkTactic: 'hold', defTactic: 'charge', atkLoss: 0, defLoss: Math.round(totalTroops(b.defender) * 0.1), atkMorale: b.attacker.morale, defMorale: b.defender.morale, notes: ['battle.note.okehazamaFail'] });
  const D = b.defender; const l = Math.round(totalTroops(D) * 0.1);
  D.troops.ashigaru = Math.max(0, D.troops.ashigaru - l);
  addLog(state, 'log.okehazamaFail', {}, 'oda', true);
  return false;
}

/** 每月隨機事件（回傳需要玩家回應的事件會進 pendingEvents） */
export function monthlyEvents(state: GameState, rng: Rng): void {
  const p = state.player;
  const fs = state.factions[p];
  if (!fs.alive) return;
  // 商人來訪：以糧換金或以金換糧
  if (rng.chance(0.08) && state.pendingEvents.length === 0) {
    state.pendingEvents.push({ id: 'merchant', choices: ['buyRice', 'sellRice', 'decline'] });
  }
  // 浪人求仕：隨機在野武將來投（需要金）
  // 流行病 / 豐作在結算中處理
}

export function resolveEvent(state: GameState, eventId: string, choice: string): void {
  const fs = state.factions[state.player];
  if (eventId === 'merchant') {
    if (choice === 'buyRice' && fs.gold >= 800) { fs.gold -= 800; fs.rice += 4000; addLog(state, 'log.boughtRice', {}, state.player); }
    if (choice === 'sellRice' && fs.rice >= 4000) { fs.rice -= 4000; fs.gold += 600; addLog(state, 'log.soldRice', {}, state.player); }
  }
}
