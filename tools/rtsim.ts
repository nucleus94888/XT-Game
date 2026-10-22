// 即時戰鬥校準：AI 對 AI 跑多場，比較回合制 autoResolve 與即時版的勝率 / 時長 / 損失
// 用法：npx tsx tools/rtsim.ts [場數]
import { createGame, rngOf, totalTroops } from '../src/core/state';
import { createBattle, autoResolve } from '../src/systems/battle';
import { rtAutoResolve } from '../src/systems/rtbattle';
import type { Army, BattleState } from '../src/core/types';
import { Rng } from '../src/core/rng';

const N = Number(process.argv[2] ?? 200);
const state = createGame(7, 'oda');

const cases: { name: string; from: Army['from']; target: Army['target']; faction: Army['faction']; n: number; officers: string[] }[] = [
  { name: '織田 6k → 美濃(齋藤 9k, 城防80)', from: 'owari', target: 'mino', faction: 'oda', n: 6000, officers: ['oda_nobunaga', 'shibata_katsuie'] },
  { name: '今川 18k → 尾張(織田 8k)', from: 'mikawa', target: 'owari', faction: 'imagawa', n: 18000, officers: ['imagawa_yoshimoto'] },
  { name: '武田 12k → 越後(上杉 15k)', from: 'kai', target: 'echigo', faction: 'takeda', n: 12000, officers: ['takeda_shingen'] },
  { name: '北條 14k → 甲斐(武田 16k)', from: 'sagami', target: 'kai', faction: 'hojo', n: 14000, officers: ['hojo_ujiyasu'] },
];

function mk(c: typeof cases[number], seed: number): BattleState {
  const r = state.regions[c.from];
  const army: Army = {
    id: `a${seed}`, faction: c.faction, from: c.from, target: c.target,
    troops: { ashigaru: Math.round(c.n * (r.troops.ashigaru / totalTroops(r))), cavalry: Math.round(c.n * (r.troops.cavalry / totalTroops(r))), gun: Math.round(c.n * (r.troops.gun / totalTroops(r))) },
    training: 50, commander: c.officers[0], officers: c.officers, eta: 0,
  };
  const rng = new Rng(seed);
  // createBattle 會讀取 region 守軍與武將（state 不變）
  const b = createBattle(state, army, rng);
  return b;
}

for (const c of cases) {
  let rWin = 0, tWin = 0, tDur = 0, tLossA = 0, tLossD = 0, rLossA = 0, rLossD = 0, tFire = 0, tDuel = 0, tSw = 0;
  for (let i = 0; i < N; i++) {
    const b1 = mk(c, 1000 + i); const rng1 = new Rng(5000 + i);
    autoResolve(b1, rng1);
    if (b1.winner === 'attacker') rWin++;
    rLossA += b1.rounds.reduce((s, r) => s + r.atkLoss, 0); rLossD += b1.rounds.reduce((s, r) => s + r.defLoss, 0);
    const b2 = mk(c, 1000 + i); const rng2 = new Rng(5000 + i);
    const rt = rtAutoResolve(b2, rng2);
    if (b2.winner === 'attacker') tWin++;
    tDur += rt.time; tLossA += rt.stats.attacker.loss; tLossD += rt.stats.defender.loss;
    tFire += rt.events.filter(e => e.kind === 'fire').length; tDuel += rt.events.filter(e => e.kind === 'duel').length;
    tSw += rt.stats.attacker.switches + rt.stats.defender.switches;
  }
  console.log(`\n${c.name}`);
  console.log(`  回合制：攻方勝率 ${(rWin / N * 100).toFixed(0)}%  損失 攻${Math.round(rLossA / N)} 守${Math.round(rLossD / N)}`);
  console.log(`  即時制：攻方勝率 ${(tWin / N * 100).toFixed(0)}%  損失 攻${Math.round(tLossA / N)} 守${Math.round(tLossD / N)}  平均 ${(tDur / N).toFixed(1)} 秒  火計 ${(tFire / N).toFixed(2)} 一騎討 ${(tDuel / N).toFixed(2)} 改陣 ${(tSw / N).toFixed(1)}`);
}
void rngOf;
