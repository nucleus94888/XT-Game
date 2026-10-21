import type {
  GameState, FactionId, RegionId, RegionState, OfficerState, FactionState, DiplomacyPair, LogEntry, OfficerDef, RegionDef,
} from './types';
import { REGIONS, REGION_MAP } from '../data/regions';
import { FACTIONS, FACTION_MAP } from '../data/factions';
import { OFFICERS } from '../data/officers';
import { Rng } from './rng';

export const OFFICER_MAP: Record<string, OfficerDef> = Object.fromEntries(OFFICERS.map(o => [o.id, o]));

export const START_YEAR = 1560;
export const START_MONTH = 1;

// ===== 建立新局 =====
export function createGame(seed: number, player: FactionId): GameState {
  const rng = new Rng(seed);
  const regions = {} as Record<RegionId, RegionState>;
  for (const r of REGIONS) {
    const t = r.init.troops;
    // 兵種比例：甲斐/越後騎馬多、薩摩/雜賀鐵砲多
    let cav = 0.15, gun = 0;
    if (r.bonuses.includes('gold_mine_cav')) cav = 0.35;
    if (r.id === 'echigo') cav = 0.3;
    if (r.bonuses.includes('early_gun') || r.bonuses.includes('saiga_gunners')) gun = 0.15;
    const cavalry = Math.round(t * cav), gunN = Math.round(t * gun);
    regions[r.id] = {
      id: r.id, owner: r.init.owner, kokudaka: r.init.kokudaka, commerce: r.init.commerce,
      loyalty: r.init.loyalty, defense: r.init.defense,
      troops: { ashigaru: t - cavalry - gunN, cavalry, gun: gunN },
      training: 50,
    };
  }

  const officers: Record<string, OfficerState> = {};
  for (const o of OFFICERS) {
    officers[o.id] = {
      id: o.id, faction: o.faction, region: o.region, rank: o.rank, loyalty: o.loyalty,
      acted: false, idleMonths: 0, injuredMonths: 0, alive: true,
      deathYear: o.death + rng.int(-2, 3),
      clanTie: !!o.clanTie,
    };
  }

  const factions = {} as Record<FactionId, FactionState>;
  for (const f of FACTIONS) {
    factions[f.id] = {
      id: f.id, gold: f.init.gold, princesses: f.init.princesses, credit: f.init.credit,
      rice: REGIONS.filter(r => r.init.owner === f.id).reduce((s, r) => s + r.init.rice, 0),
      techs: [...f.techs], research: { tech: null, progress: 0 },
      ninja: { clan: null, level: 0 }, alive: true, intel: {}, fame: f.major ? 20 : 5,
    };
  }

  const diplomacy: Record<string, DiplomacyPair> = {};
  for (let i = 0; i < FACTIONS.length; i++) {
    for (let j = i + 1; j < FACTIONS.length; j++) {
      const a = FACTIONS[i].id, b = FACTIONS[j].id;
      const neighbours = areNeighbours(regions, a, b);
      diplomacy[diploKey(a, b)] = { relation: neighbours ? rng.int(-30, 10) : rng.int(-5, 20) };
    }
  }
  // 史實關係
  setRel(diplomacy, 'takeda', 'uesugi', -70);
  setRel(diplomacy, 'oda', 'imagawa', -60);
  setRel(diplomacy, 'oda', 'saito', -50);
  setRel(diplomacy, 'mori', 'amago', -70);
  setRel(diplomacy, 'otomo', 'mori', -40);
  setRel(diplomacy, 'azai', 'asakura', 60);
  diplomacy[diploKey('azai', 'asakura')].alliance = 36;
  // 甲相駿三國同盟
  for (const [a, b] of [['takeda', 'hojo'], ['takeda', 'imagawa'], ['hojo', 'imagawa']] as const) {
    setRel(diplomacy, a, b, 60);
    diplomacy[diploKey(a, b)].alliance = 30;
    diplomacy[diploKey(a, b)].marriage = 30;
  }

  const state: GameState = {
    seed, turn: 0, year: START_YEAR, month: START_MONTH, player,
    regions, officers, factions, armies: [], diplomacy, log: [], flags: { rngState: rng.state },
    battleQueue: [], pendingEvents: [],
  };
  addLog(state, 'log.gameStart', { faction: FACTION_MAP[player].name }, player, true);
  return state;
}

function setRel(d: Record<string, DiplomacyPair>, a: FactionId, b: FactionId, v: number) {
  d[diploKey(a, b)].relation = v;
}

function areNeighbours(regions: Record<RegionId, RegionState>, a: FactionId, b: FactionId): boolean {
  for (const r of REGIONS) {
    if (regions[r.id].owner !== a) continue;
    if (r.adjacent.some(x => regions[x].owner === b)) return true;
  }
  return false;
}

// ===== RNG 續用 =====
export function rngOf(state: GameState): Rng {
  const r = new Rng(state.seed);
  r.state = (state.flags.rngState as number) ?? state.seed;
  return r;
}
export function saveRng(state: GameState, rng: Rng) { state.flags.rngState = rng.state; }

// ===== 查詢 =====
export function diploKey(a: FactionId, b: FactionId): string { return a < b ? `${a}|${b}` : `${b}|${a}`; }
export function getDiplo(state: GameState, a: FactionId, b: FactionId): DiplomacyPair {
  return state.diplomacy[diploKey(a, b)];
}
export function regionDef(id: RegionId): RegionDef { return REGION_MAP[id]; }
export function officerDef(id: string): OfficerDef { return OFFICER_MAP[id]; }

export function officerAge(state: GameState, id: string): number { return state.year - OFFICER_MAP[id].birth; }
export function officerActive(state: GameState, o: OfficerState): boolean {
  return o.alive && officerAge(state, o.id) >= 15;
}
export function officersOf(state: GameState, faction: FactionId): OfficerState[] {
  return Object.values(state.officers).filter(o => o.faction === faction && officerActive(state, o));
}
export function officersIn(state: GameState, region: RegionId, faction?: FactionId | null): OfficerState[] {
  return Object.values(state.officers).filter(o =>
    o.region === region && officerActive(state, o) && !o.armyId && (faction === undefined || o.faction === faction));
}
export function roninIn(state: GameState, region: RegionId): OfficerState[] {
  return officersIn(state, region, null);
}
export function regionsOf(state: GameState, faction: FactionId): RegionState[] {
  return REGIONS.map(r => state.regions[r.id]).filter(r => r.owner === faction);
}
export function totalTroops(r: { troops: { ashigaru: number; cavalry: number; gun: number } }): number {
  return r.troops.ashigaru + r.troops.cavalry + r.troops.gun;
}
export function factionTroops(state: GameState, faction: FactionId): number {
  let n = regionsOf(state, faction).reduce((s, r) => s + totalTroops(r), 0);
  for (const a of state.armies) if (a.faction === faction) n += totalTroops(a);
  return n;
}
export function daimyoOf(state: GameState, faction: FactionId): OfficerState | undefined {
  return Object.values(state.officers).find(o => o.faction === faction && o.rank === 'daimyo' && o.alive);
}
export function isAlly(state: GameState, a: FactionId, b: FactionId): boolean {
  if (a === b) return true;
  const d = getDiplo(state, a, b);
  return !!((d.alliance && d.alliance > 0) || (d.marriage && d.marriage > 0));
}
export function hasTruce(state: GameState, a: FactionId, b: FactionId): boolean {
  if (a === b) return true;
  const d = getDiplo(state, a, b);
  return !!(d.truce && d.truce > 0);
}
export function canAttack(state: GameState, a: FactionId, b: FactionId | null): boolean {
  if (b === null) return true;
  return !isAlly(state, a, b) && !hasTruce(state, a, b);
}
export function aliveFactions(state: GameState): FactionId[] {
  return FACTIONS.map(f => f.id).filter(f => state.factions[f].alive);
}
export function neighbourRegions(state: GameState, faction: FactionId): RegionId[] {
  const set = new Set<RegionId>();
  for (const r of regionsOf(state, faction)) for (const adj of REGION_MAP[r.id].adjacent) {
    if (state.regions[adj].owner !== faction) set.add(adj);
  }
  return [...set];
}
export function isSnowed(state: GameState, region: RegionId): boolean {
  return !!REGION_MAP[region].snowMonths?.includes(state.month);
}

export function addLog(state: GameState, key: string, params?: LogEntry['params'], faction?: FactionId, important = false) {
  state.log.push({ turn: state.turn, key, params, faction, important });
  if (state.log.length > 400) state.log.splice(0, state.log.length - 400);
}

export function clamp(v: number, lo: number, hi: number): number { return Math.max(lo, Math.min(hi, v)); }
