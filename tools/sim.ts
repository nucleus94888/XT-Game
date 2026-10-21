// 無頭模擬：玩家也交給 AI，跑 N 年，檢查引擎不崩潰並印出勢力消長
// 用法：npx tsx tools/sim.ts [seed] [years]
import { createGame, regionsOf, factionTroops, aliveFactions, officersOf } from '../src/core/state';
import { endTurn, completeTurn } from '../src/systems/turn';
import { aiTurn } from '../src/systems/ai';
import { autoResolve, finishBattle } from '../src/systems/battle';
import { rngOf, saveRng } from '../src/core/state';
import { FACTION_MAP } from '../src/data/factions';

const seed = Number(process.argv[2] ?? 42);
const years = Number(process.argv[3] ?? 10);
const player = (process.argv[4] ?? 'hojo') as import('../src/core/types').FactionId;
const state = createGame(seed, player);
const t0 = Date.now();
for (let i = 0; i < years * 12; i++) {
  if (state.gameOver) break;
  aiTurn(state, state.player);
  endTurn(state);
  const hadBattles = state.battleQueue.length > 0;
  while (state.battleQueue.length) {
    const b = state.battleQueue.shift()!;
    const rng = rngOf(state);
    autoResolve(b, rng); saveRng(state, rng);
    finishBattle(state, b);
  }
  if (hadBattles && !state.gameOver) completeTurn(state);
  state.pendingEvents.length = 0;
  if (state.month === 1) {
    const rows = aliveFactions(state).map(f => `${FACTION_MAP[f].name}:${regionsOf(state, f).length}區/${Math.round(factionTroops(state, f) / 1000)}k/${state.factions[f].gold}金/${officersOf(state, f).length}將`);
    console.log(`${state.year}年  ${rows.join('  ')}`);
  }
}
console.log(`結束：${state.year}/${state.month}  gameOver=${JSON.stringify(state.gameOver)}  ${Date.now() - t0}ms`);
const important = state.log.filter(l => l.important).slice(-25);
for (const l of important) console.log(`  [${l.turn}] ${l.key} ${JSON.stringify(l.params)}`);
