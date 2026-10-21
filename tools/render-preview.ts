// Dev preview for MapScene / BattleScene. Served by Vite at /tools/render-preview.html
import { createGame } from '../src/core/state';
import type { BattleRoundLog, BattleState, RegionId } from '../src/core/types';
import { FACTION_MAP } from '../src/data/factions';
import { REGION_MAP } from '../src/data/regions';
import { MapScene } from '../src/render/MapScene';
import { BattleScene } from '../src/render/BattleScene';

const logEl = document.getElementById('log') as HTMLDivElement;
function log(msg: string): void {
  console.log(msg);
  logEl.textContent = `${msg}\n${logEl.textContent ?? ''}`.split('\n').slice(0, 12).join('\n');
}

const state = createGame(1, 'oda');
const mapEl = document.getElementById('map') as HTMLDivElement;
const map = new MapScene(mapEl);
map.update(state);

let selected: RegionId | null = null;
map.onSelect = (id) => {
  selected = id;
  map.select(id);
  map.highlight(id ? REGION_MAP[id].adjacent : []);
  log(`select: ${id ?? 'null'}`);
};

// ---- buttons ----
const btnBattle = document.getElementById('btn-battle') as HTMLButtonElement;
const btnArmy = document.getElementById('btn-army') as HTMLButtonElement;
const btnFocus = document.getElementById('btn-focus') as HTMLButtonElement;
const btnClose = document.getElementById('btn-close') as HTMLButtonElement;
const battleEl = document.getElementById('battle') as HTMLDivElement;

btnArmy.onclick = () => {
  if (state.armies.length) state.armies = [];
  else {
    state.armies = [
      { id: 'a1', faction: 'oda', from: 'owari', target: 'mino', troops: { ashigaru: 3000, cavalry: 800, gun: 200 }, training: 60, commander: 'oda_nobunaga', officers: ['oda_nobunaga'], eta: 1 },
      { id: 'a2', faction: 'takeda', from: 'kai', target: 'mikawa', troops: { ashigaru: 5000, cavalry: 3000, gun: 0 }, training: 80, commander: 'takeda_shingen', officers: ['takeda_shingen'], eta: 1 },
    ];
  }
  map.update(state);
  log(`armies: ${state.armies.length}`);
};

btnFocus.onclick = () => map.focus(selected ?? 'owari', true);

let battle: BattleScene | null = null;

function fakeBattle(): BattleState {
  return {
    id: 'preview-battle',
    armyId: 'a1',
    region: 'mikawa',
    terrain: 'mountain',
    weather: 'rain',
    siege: true,
    defense: 55,
    attacker: { faction: 'oda', troops: { ashigaru: 6000, cavalry: 2000, gun: 1000 }, initial: 9000, training: 70, morale: 100, commander: 'oda_nobunaga', officers: ['oda_nobunaga'], fireUsed: false },
    defender: { faction: 'imagawa', troops: { ashigaru: 9000, cavalry: 2000, gun: 1000 }, initial: 12000, training: 60, morale: 100, commander: 'imagawa_yoshimoto', officers: ['imagawa_yoshimoto'], fireUsed: false },
    round: 0,
    maxRounds: 8,
    rounds: [],
    over: false,
  };
}

function applyLoss(side: BattleState['attacker'], loss: number): void {
  let left = loss;
  for (const k of ['ashigaru', 'cavalry', 'gun'] as const) {
    const take = Math.min(side.troops[k], left);
    side.troops[k] -= take;
    left -= take;
  }
}

async function runFakeBattle(): Promise<void> {
  const b = fakeBattle();
  const atkF = FACTION_MAP[b.attacker.faction];
  const defF = FACTION_MAP[b.defender.faction];
  battle = new BattleScene(battleEl);
  battle.setup(b, { kamon: atkF.kamon, color: atkF.color, name: atkF.name }, { kamon: defF.kamon, color: defF.color, name: defF.name });

  const script: [BattleRoundLog['atkTactic'], BattleRoundLog['defTactic'], number, number][] = [
    ['charge', 'hold', 1400, 500],
    ['volley', 'charge', 600, 1600],
    ['fire', 'hold', 300, 2400],
    ['duel', 'duel', 800, 900],
    ['maneuver', 'retreat', 200, 1200],
  ];
  for (let i = 0; i < script.length; i++) {
    if (!battle) return;
    const [atkTactic, defTactic, atkLoss, defLoss] = script[i];
    applyLoss(b.attacker, atkLoss);
    applyLoss(b.defender, defLoss);
    b.round = i + 1;
    const round: BattleRoundLog = { round: i + 1, atkTactic, defTactic, atkLoss, defLoss, atkMorale: 90 - i * 5, defMorale: 85 - i * 8, notes: [] };
    b.rounds.push(round);
    log(`round ${i + 1}: ${atkTactic} vs ${defTactic} (-${atkLoss} / -${defLoss})`);
    const t0 = performance.now();
    await battle.playRound(round, b);
    log(`  round ${i + 1} done in ${Math.round(performance.now() - t0)}ms`);
    await new Promise((r) => setTimeout(r, 2000));
  }
  log('battle script finished');
}

btnBattle.onclick = () => {
  battleEl.classList.add('open');
  btnClose.style.display = '';
  btnBattle.style.display = 'none';
  void runFakeBattle();
};

btnClose.onclick = () => {
  battle?.dispose();
  battle = null;
  battleEl.classList.remove('open');
  btnClose.style.display = 'none';
  btnBattle.style.display = '';
};

// 讓 headless 截圖能用 query string 直接開戰鬥 / 選區 / 放軍隊
const qs = new URLSearchParams(location.search);
if (qs.has('battle')) btnBattle.click();
if (qs.has('army')) btnArmy.click();
const sel = qs.get('select') as RegionId | null;
if (sel && REGION_MAP[sel]) map.onSelect?.(sel);

log('ready — tap a region');
