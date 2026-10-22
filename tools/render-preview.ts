// Dev preview for MapScene / BattleScene. Served by Vite at /tools/render-preview.html
import { createGame } from '../src/core/state';
import type { BattleState, RegionId } from '../src/core/types';
import { FACTION_MAP } from '../src/data/factions';
import { REGION_MAP } from '../src/data/regions';
import { MapScene } from '../src/render/MapScene';
import { BattleScene } from '../src/render/BattleScene';
import { createRtBattle, rtStep } from '../src/systems/rtbattle';
import { Rng } from '../src/core/rng';

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
let battleRaf = 0;

function fakeBattle(): BattleState {
  return {
    id: 'preview-battle', armyId: 'a1', region: 'mikawa', terrain: 'mountain', weather: 'rain', siege: true, defense: 55,
    attacker: { faction: 'oda', troops: { ashigaru: 6000, cavalry: 2000, gun: 1000 }, initial: 9000, training: 70, morale: 100, commander: 'oda_nobunaga', officers: ['oda_nobunaga'], fireUsed: false },
    defender: { faction: 'imagawa', troops: { ashigaru: 9000, cavalry: 2000, gun: 1000 }, initial: 12000, training: 60, morale: 100, commander: 'imagawa_yoshimoto', officers: ['imagawa_yoshimoto'], fireUsed: false },
    round: 0, maxRounds: 8, rounds: [], over: false,
  };
}

/** AI 對 AI 的即時戰鬥，用場景播放 */
function runFakeBattle(): void {
  const b = fakeBattle();
  const atkF = FACTION_MAP[b.attacker.faction];
  const defF = FACTION_MAP[b.defender.faction];
  const rng = new Rng(3);
  const rt = createRtBattle(b, rng, { playerSide: null });
  battle = new BattleScene(battleEl);
  battle.setup(b, { kamon: atkF.kamon, color: atkF.color, name: atkF.name }, { kamon: defF.kamon, color: defF.color, name: defF.name }, { attacker: rt.sides.attacker.stance, defender: rt.sides.defender.stance });
  let last = performance.now(), evIdx = 0, shownA = 0, shownD = 0;
  const loop = (now: number) => {
    if (!battle) return;
    const dt = Math.min(0.05, (now - last) / 1000); last = now;
    if (!rt.over) {
      rtStep(rt, dt, rng, ['attacker', 'defender']);
      for (const side of ['attacker', 'defender'] as const) {
        const st = rt.sides[side];
        battle.setStance(side, st.pending ?? st.stance, st.switching > 0);
      }
      while (evIdx < rt.events.length) { const ev = rt.events[evIdx++]; battle.showEvent(ev); log(`${ev.t.toFixed(1)}s ${ev.side} ${ev.kind} ${ev.stance ?? ''}`); }
      const lA = rt.stats.attacker.loss - shownA, lD = rt.stats.defender.loss - shownD;
      if (lA > 300 || lD > 300 || rt.over) { battle.syncTroops(b, lA, lD); shownA += lA; shownD += lD; }
      if (rt.over) log(`over: ${b.winner} in ${rt.time.toFixed(1)}s`);
    }
    battleRaf = requestAnimationFrame(loop);
  };
  battleRaf = requestAnimationFrame(loop);
}

btnBattle.onclick = () => {
  battleEl.classList.add('open');
  btnClose.style.display = '';
  btnBattle.style.display = 'none';
  runFakeBattle();
};

btnClose.onclick = () => {
  cancelAnimationFrame(battleRaf);
  battle?.dispose();
  battle = null;
  battleEl.classList.remove('open');
  btnClose.style.display = 'none';
  btnBattle.style.display = '';
};

const qs = new URLSearchParams(location.search);
if (qs.has('battle')) btnBattle.click();
if (qs.has('army')) btnArmy.click();
const sel = qs.get('select') as RegionId | null;
if (sel && REGION_MAP[sel]) map.onSelect?.(sel);

log('ready — tap a region');
