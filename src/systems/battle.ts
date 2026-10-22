// 戰鬥：每回合雙方同時選戰術，戰術剋制 × 武將 × 兵種 × 地形 × 士氣 × 城防
import type { GameState, BattleState, BattleSide, Tactic, Army, FactionId, OfficerDef } from '../core/types';
import { OFFICER_MAP, addLog, clamp, officersIn, totalTroops, rngOf, saveRng, regionsOf, officerDef } from '../core/state';
import { REGION_MAP } from '../data/regions';
import type { Rng } from '../core/rng';

export const TACTICS: Tactic[] = ['charge', 'hold', 'volley', 'maneuver', 'fire', 'duel', 'retreat'];

/** 戰術剋制：矩陣[mine][theirs] = 我方傷害倍率 */
export const MATCHUP: Record<Tactic, Partial<Record<Tactic, number>>> = {
  charge:   { charge: 1.0, hold: 0.6, volley: 1.5, maneuver: 1.3, fire: 1.2, duel: 1.0, retreat: 1.6 },
  hold:     { charge: 1.5, hold: 0.8, volley: 0.6, maneuver: 0.7, fire: 0.4, duel: 0.8, retreat: 0.8 },
  volley:   { charge: 0.7, hold: 1.5, volley: 1.0, maneuver: 1.4, fire: 1.0, duel: 1.0, retreat: 1.3 },
  maneuver: { charge: 0.6, hold: 1.4, volley: 0.8, maneuver: 1.0, fire: 1.1, duel: 1.0, retreat: 1.4 },
  fire:     { charge: 1.0, hold: 2.0, volley: 1.3, maneuver: 1.2, fire: 1.0, duel: 1.0, retreat: 1.2 },
  duel:     { charge: 0.5, hold: 0.5, volley: 0.5, maneuver: 0.5, fire: 0.5, duel: 0.5, retreat: 0.5 },
  retreat:  { charge: 0.2, hold: 0.2, volley: 0.2, maneuver: 0.2, fire: 0.2, duel: 0.2, retreat: 0.2 },
};

const KEY_STAT: Record<Tactic, keyof Pick<OfficerDef, 'lead' | 'valor' | 'intel'>> = {
  charge: 'valor', hold: 'lead', volley: 'lead', maneuver: 'intel', fire: 'intel', duel: 'valor', retreat: 'lead',
};

const DEFAULT_CMD: Pick<OfficerDef, 'lead' | 'valor' | 'intel' | 'politics' | 'charm' | 'traits' | 'name'> =
  { lead: 40, valor: 40, intel: 40, politics: 40, charm: 40, traits: [], name: '?' };

export function cmdOf(side: BattleSide) {
  return side.commander ? OFFICER_MAP[side.commander] : DEFAULT_CMD;
}

/** 戰術是否可用 */
export function canUseTactic(b: BattleState, side: BattleSide, t: Tactic): { ok: boolean; reason?: string } {
  const c = cmdOf(side);
  switch (t) {
    case 'volley':
      if (side.troops.gun <= 0) return { ok: false, reason: 'battle.cant.noGuns' };
      if (b.weather === 'rain') return { ok: false, reason: 'battle.cant.rain' };
      return { ok: true };
    case 'fire':
      if (side.fireUsed) return { ok: false, reason: 'battle.cant.fireUsed' };
      if (b.weather === 'rain') return { ok: false, reason: 'battle.cant.rain' };
      if (!(c.intel >= 80 || c.traits.includes('strategist'))) return { ok: false, reason: 'battle.cant.intel' };
      return { ok: true };
    case 'duel':
      if (!side.commander || !(side === b.attacker ? b.defender : b.attacker).commander) return { ok: false, reason: 'battle.cant.noCommander' };
      return { ok: true };
    case 'retreat':
      if (side === b.defender && b.siege) return { ok: false, reason: 'battle.cant.besieged' };
      return { ok: true };
    default: return { ok: true };
  }
}

export function createBattle(state: GameState, army: Army, rng: Rng): BattleState {
  const region = state.regions[army.target];
  const def = REGION_MAP[army.target];
  const defOfficers = region.owner ? officersIn(state, army.target, region.owner) : [];
  const defCommander = pickCommander(defOfficers.map(o => o.id));
  const month = state.month;
  const rainP = month >= 6 && month <= 7 ? 0.45 : month >= 9 && month <= 10 ? 0.3 : 0.15;
  const atk: BattleSide = {
    faction: army.faction, troops: { ...army.troops }, initial: totalTroops(army), training: army.training,
    morale: 100, commander: army.commander, officers: [...army.officers], fireUsed: false,
  };
  const dfd: BattleSide = {
    faction: region.owner as FactionId, troops: { ...region.troops }, initial: totalTroops(region), training: region.training,
    morale: 100 + Math.round(region.loyalty / 10) - 5, commander: defCommander, officers: defOfficers.map(o => o.id), fireUsed: false,
  };
  const b: BattleState = {
    id: `b${state.turn}_${army.id}`, armyId: army.id, region: army.target, terrain: def.terrain,
    weather: rng.chance(rainP) ? 'rain' : 'clear', siege: true, defense: region.defense,
    attacker: atk, defender: dfd, round: 0, maxRounds: 8, rounds: [], over: false,
  };
  return b;
}

export function pickCommander(ids: string[]): string | null {
  if (ids.length === 0) return null;
  return ids.slice().sort((a, b) => OFFICER_MAP[b].lead - OFFICER_MAP[a].lead)[0];
}

/** 若我方主將智謀明顯高於對方，可預測對方戰術傾向 */
export function tacticHint(b: BattleState, mine: 'attacker' | 'defender', rng: Rng): Tactic | null {
  const me = cmdOf(b[mine]), them = cmdOf(mine === 'attacker' ? b.defender : b.attacker);
  if (me.intel < them.intel + 15) return null;
  const tmpRng = rng; // 預測使用同一分佈，但不消耗真正的 rng
  const dist = aiTacticWeights(b, mine === 'attacker' ? 'defender' : 'attacker');
  void tmpRng;
  return dist.sort((a, b2) => b2.w - a.w)[0].t;
}

function aiTacticWeights(b: BattleState, who: 'attacker' | 'defender'): { t: Tactic; w: number }[] {
  const side = b[who], enemy = who === 'attacker' ? b.defender : b.attacker;
  const c = cmdOf(side);
  const myN = totalTroops(side), enN = totalTroops(enemy);
  const w: Record<Tactic, number> = { charge: 1, hold: 1, volley: 0, maneuver: 0.6, fire: 0, duel: 0, retreat: 0 };
  w.charge += c.valor / 60 + (side.troops.cavalry / Math.max(1, myN)) * 2 + (c.traits.includes('berserk') ? 1 : 0);
  w.hold += c.lead / 70 + (who === 'defender' ? 0.8 + b.defense / 100 : 0);
  if (canUseTactic(b, side, 'volley').ok) w.volley = 0.5 + (side.troops.gun / Math.max(1, myN)) * 5 + (c.traits.includes('gunner') ? 1 : 0);
  w.maneuver += c.intel / 80 + (c.traits.includes('strategist') ? 0.8 : 0);
  if (canUseTactic(b, side, 'fire').ok) w.fire = 0.4 + c.intel / 100 + (b.terrain === 'mountain' ? 0.4 : 0);
  if (canUseTactic(b, side, 'duel').ok) {
    const ec = cmdOf(enemy);
    if (c.valor > ec.valor + 10) w.duel = 0.3 + (c.valor - ec.valor) / 40 + (c.traits.includes('duelist') ? 1 : 0);
  }
  // 士氣與兵力劣勢 → 撤退
  if (canUseTactic(b, side, 'retreat').ok) {
    if (side.morale < 35 || myN < enN * 0.35) w.retreat = 1.5 + (35 - Math.min(35, side.morale)) / 10;
  }
  // 上一回合對方戰術的反制（有記憶）
  const last = b.rounds[b.rounds.length - 1];
  if (last) {
    const theirs = who === 'attacker' ? last.defTactic : last.atkTactic;
    for (const t of TACTICS) if (w[t] > 0) w[t] *= 0.7 + (MATCHUP[t][theirs] ?? 1) * 0.5;
  }
  return TACTICS.map(t => ({ t, w: Math.max(0, w[t]) }));
}

export function aiTactic(b: BattleState, who: 'attacker' | 'defender', rng: Rng): Tactic {
  const weights = aiTacticWeights(b, who);
  const total = weights.reduce((s, x) => s + x.w, 0);
  let r = rng.next() * total;
  for (const x of weights) { r -= x.w; if (r <= 0) return x.t; }
  return 'hold';
}

export function effectiveStrength(side: BattleSide, t: Tactic, terrain: 'plain' | 'mountain'): number {
  const cavMul = (t === 'charge' ? 1.8 : t === 'maneuver' ? 1.4 : 1.0) * (terrain === 'mountain' ? 0.6 : 1);
  const gunMul = t === 'volley' ? 2.5 : t === 'hold' ? 1.3 : 0.8;
  return side.troops.ashigaru + side.troops.cavalry * cavMul + side.troops.gun * gunMul;
}

export function officerMod(side: BattleSide, t: Tactic): number {
  const c = cmdOf(side);
  let m = 0.7 + c[KEY_STAT[t]] / 200;
  if (t === 'charge' && c.traits.includes('cavalry') && side.troops.cavalry > 0) m *= 1.2;
  if (t === 'charge' && c.traits.includes('berserk')) m *= 1.2;
  if (t === 'volley' && c.traits.includes('gunner')) m *= 1.25;
  if ((t === 'maneuver' || t === 'fire') && c.traits.includes('strategist')) m *= 1.2;
  // 副將加成：每位 +3%，最多 +6%
  m *= 1 + Math.min(2, side.officers.length - 1) * 0.03;
  return m;
}

export function applyLoss(side: BattleSide, loss: number) {
  const n = totalTroops(side);
  if (n <= 0) return;
  loss = Math.min(loss, n);
  const ratio = loss / n;
  const a = Math.round(side.troops.ashigaru * ratio), c = Math.round(side.troops.cavalry * ratio);
  const g = Math.min(side.troops.gun, loss - a - c);
  side.troops.ashigaru -= a; side.troops.cavalry -= c; side.troops.gun -= Math.max(0, g);
  if (totalTroops(side) < 0) side.troops = { ashigaru: 0, cavalry: 0, gun: 0 };
}

/** 結算一回合。兩邊 tactic 需已填入。 */
export function resolveRound(b: BattleState, rng: Rng): void {
  if (b.over) return;
  const A = b.attacker, D = b.defender;
  const ta = A.tactic ?? 'hold', td = D.tactic ?? 'hold';
  b.round += 1;
  const notes: string[] = [];
  let atkLoss = 0, defLoss = 0;

  // 一騎討
  const duelSides = [ta === 'duel' ? 'attacker' : null, td === 'duel' ? 'defender' : null].filter(Boolean) as ('attacker' | 'defender')[];
  if (duelSides.length) {
    const ca = cmdOf(A), cd = cmdOf(D);
    const sa = ca.valor + (ca.traits.includes('duelist') ? 15 : 0) + rng.int(0, 30);
    const sd = cd.valor + (cd.traits.includes('duelist') ? 15 : 0) + rng.int(0, 30);
    if (sa > sd) { A.morale += 30; D.morale -= 20; notes.push('battle.note.duelAtkWin'); }
    else { D.morale += 30; A.morale -= 20; notes.push('battle.note.duelDefWin'); }
  }

  // 火計判定
  const fireOK = (side: BattleSide, t: Tactic) => {
    if (t !== 'fire') return 1;
    side.fireUsed = true;
    const c = cmdOf(side);
    const p = clamp(0.35 + (c.intel - 70) / 100 + (b.terrain === 'mountain' ? 0.15 : 0) + (c.traits.includes('strategist') ? 0.15 : 0), 0.15, 0.9);
    if (rng.chance(p)) { notes.push(side === A ? 'battle.note.fireAtkOk' : 'battle.note.fireDefOk'); return 1; }
    notes.push(side === A ? 'battle.note.fireAtkFail' : 'battle.note.fireDefFail');
    return 0.3; // 失敗：只造成零星傷害
  };
  const fa = fireOK(A, ta), fd = fireOK(D, td);

  const base = 0.08;
  const moraleMul = (s: BattleSide) => 0.5 + clamp(s.morale, 0, 130) / 130 * 0.7;
  const trainMul = (s: BattleSide) => 0.7 + s.training / 250;
  const rand = () => rng.range(0.85, 1.15);

  // 攻方對守方造成的傷害
  let dmgToD = effectiveStrength(A, ta, b.terrain) * base * (MATCHUP[ta][td] ?? 1) * officerMod(A, ta) * moraleMul(A) * trainMul(A) * fa * rand();
  // 守方對攻方造成的傷害（含城防）
  let castleMul = 1;
  if (b.siege) {
    castleMul = 1 + b.defense / 100 * (td === 'hold' ? 0.4 : 0.15);
    if (cmdOf(A).traits.includes('siege')) castleMul = 1 + (castleMul - 1) * 0.5;
  }
  let dmgToA = effectiveStrength(D, td, b.terrain) * base * (MATCHUP[td][ta] ?? 1) * officerMod(D, td) * moraleMul(D) * trainMul(D) * fd * castleMul * rand();
  // 攻城時攻方傷害被城牆削減
  if (b.siege) dmgToD *= 1 - b.defense / 100 * 0.25 * (cmdOf(A).traits.includes('siege') ? 0.5 : 1);

  // 撤退：只受一回合半傷然後脫離
  if (ta === 'retreat') dmgToA *= 0.5;
  if (td === 'retreat') dmgToD *= 0.5;

  atkLoss = Math.round(Math.min(dmgToA, totalTroops(A)));
  defLoss = Math.round(Math.min(dmgToD, totalTroops(D)));
  applyLoss(A, atkLoss); applyLoss(D, defLoss);

  // 士氣
  A.morale -= Math.round(atkLoss / Math.max(1, A.initial) * 100 * 0.8);
  D.morale -= Math.round(defLoss / Math.max(1, D.initial) * 100 * 0.8);
  if ((MATCHUP[ta][td] ?? 1) > 1.2) { D.morale -= 5; A.morale += 2; }
  if ((MATCHUP[td][ta] ?? 1) > 1.2) { A.morale -= 5; D.morale += 2; }
  if (ta === 'maneuver' && (MATCHUP[ta][td] ?? 1) > 1.2) { D.morale -= 10; notes.push('battle.note.maneuverAtk'); }
  if (td === 'maneuver' && (MATCHUP[td][ta] ?? 1) > 1.2) { A.morale -= 10; notes.push('battle.note.maneuverDef'); }
  // 攻城方每回合士氣自然流失
  if (b.siege) A.morale -= 2;
  A.morale = clamp(A.morale, 0, 130); D.morale = clamp(D.morale, 0, 130);

  b.rounds.push({ round: b.round, atkTactic: ta, defTactic: td, atkLoss, defLoss, atkMorale: A.morale, defMorale: D.morale, notes });

  // 勝負
  if (ta === 'retreat') { b.over = true; b.winner = 'defender'; notes.push('battle.note.atkRetreat'); }
  else if (td === 'retreat') { b.over = true; b.winner = 'attacker'; notes.push('battle.note.defRetreat'); }
  else if (totalTroops(D) <= 0 || D.morale <= 0) { b.over = true; b.winner = 'attacker'; notes.push('battle.note.defRout'); }
  else if (totalTroops(A) <= 0 || A.morale <= 0) { b.over = true; b.winner = 'defender'; notes.push('battle.note.atkRout'); }
  else if (b.round >= b.maxRounds) { b.over = true; b.winner = 'defender'; notes.push('battle.note.timeout'); }
  A.tactic = undefined; D.tactic = undefined;
}

/** 純 AI 對 AI 的戰鬥，直接跑完 */
export function autoResolve(b: BattleState, rng: Rng): void {
  while (!b.over) {
    b.attacker.tactic = aiTactic(b, 'attacker', rng);
    b.defender.tactic = aiTactic(b, 'defender', rng);
    resolveRound(b, rng);
  }
}

/** 把戰鬥結果寫回世界狀態 */
export function finishBattle(state: GameState, b: BattleState): void {
  const rng = rngOf(state);
  const armyIdx = state.armies.findIndex(a => a.id === b.armyId);
  const army = state.armies[armyIdx];
  const region = state.regions[b.region];
  const atkF = b.attacker.faction, defF = b.defender.faction;
  const A = b.attacker, D = b.defender;
  region.troops = { ...D.troops };
  // 傷亡後民忠
  region.loyalty = clamp(region.loyalty - 3, 0, 100);
  // 主將受傷判定（敗方）
  const loserSide = b.winner === 'attacker' ? D : A;
  for (const oid of loserSide.officers) {
    if (rng.chance(0.08)) { state.officers[oid].injuredMonths = rng.int(2, 5); addLog(state, 'log.injured', { name: OFFICER_MAP[oid].name }, state.officers[oid].faction ?? undefined); }
  }
  // 名聲
  state.factions[atkF].fame += b.winner === 'attacker' ? 3 : -1;
  if (defF) state.factions[defF].fame += b.winner === 'defender' ? 2 : -2;

  if (b.winner === 'attacker') {
    captureRegion(state, b.region, atkF, A.troops, A.training, A.officers, rng);
    addLog(state, 'log.captured', { region: b.region, faction: atkF, from: defF }, atkF, true);
    if (defF) addLog(state, 'log.lost', { region: b.region, faction: defF, to: atkF }, defF, true);
    if (army) state.armies.splice(armyIdx, 1);
    for (const oid of A.officers) state.officers[oid].armyId = undefined;
  } else {
    // 攻方撤回出發地
    if (army) {
      const home = state.regions[army.from];
      if (home.owner === atkF) {
        for (const k of ['ashigaru', 'cavalry', 'gun'] as const) home.troops[k] += A.troops[k];
      }
      for (const oid of A.officers) { state.officers[oid].armyId = undefined; state.officers[oid].region = home.owner === atkF ? army.from : state.officers[oid].region; }
      state.armies.splice(armyIdx, 1);
    }
    addLog(state, 'log.repelled', { region: b.region, faction: atkF, def: defF }, defF, true);
    region.defense = clamp(region.defense - 3, 0, 100);
  }
  saveRng(state, rng);
}

/** 佔領：守方武將處置、駐軍替換 */
export function captureRegion(state: GameState, rid: string, newOwner: FactionId, troops: { ashigaru: number; cavalry: number; gun: number }, training: number, officers: string[], rng: Rng) {
  const region = state.regions[rid as keyof typeof state.regions];
  const oldOwner = region.owner;
  region.owner = newOwner;
  region.troops = { ...troops };
  region.training = training;
  region.defense = clamp(Math.round(region.defense * 0.6), 10, 100);
  region.loyalty = clamp(region.loyalty - 15, 10, 100);
  // 奪取部分糧倉
  if (oldOwner) {
    const loot = Math.round(state.factions[oldOwner].rice * 0.15);
    state.factions[oldOwner].rice -= loot;
    state.factions[newOwner].rice += loot;
  }
  for (const oid of officers) { state.officers[oid].region = region.id; state.officers[oid].armyId = undefined; }

  if (oldOwner) {
    const remaining = regionsOf(state, oldOwner).filter(r => r.id !== region.id);
    const defenders = Object.values(state.officers).filter(o => o.faction === oldOwner && o.region === region.id && !o.armyId && o.alive);
    const daimyoCharm = (() => {
      const d = Object.values(state.officers).find(o => o.faction === newOwner && o.rank === 'daimyo');
      return d ? OFFICER_MAP[d.id].charm : 50;
    })();
    for (const o of defenders) {
      const od = OFFICER_MAP[o.id];
      const isLord = o.rank === 'daimyo' || o.rank === 'heir';
      if (remaining.length > 0) {
        // 逃往鄰近己方領地；低忠誠者可能投降
        const p = isLord || od.traits.includes('loyal') ? 0 : clamp((60 - o.loyalty) / 100 + daimyoCharm / 400, 0, 0.6);
        if (rng.chance(p)) { surrender(state, o, newOwner, region.id); }
        else {
          const dest = remaining.find(r => REGION_MAP[region.id].adjacent.includes(r.id)) ?? remaining[0];
          o.region = dest.id;
        }
      } else {
        // 勢力滅亡：大名可能戰死 / 隱居，其餘武將依忠誠與魅力決定投降或流浪
        if (isLord) {
          if (rng.chance(0.5)) { o.alive = false; addLog(state, 'log.lordDied', { name: od.name }, oldOwner, true); }
          else { o.faction = null; o.rank = 'ronin'; o.loyalty = 30; }
        } else if (rng.chance(0.5 + daimyoCharm / 300 - o.loyalty / 300)) surrender(state, o, newOwner, region.id);
        else { o.faction = null; o.rank = 'ronin'; o.loyalty = 40; }
      }
    }
    if (remaining.length === 0) {
      state.factions[oldOwner].alive = false;
      // 出征中的軍團解散
      state.armies = state.armies.filter(a => a.faction !== oldOwner);
      addLog(state, 'log.factionFell', { faction: oldOwner, by: newOwner }, undefined, true);
      state.factions[newOwner].fame += 10;
    }
  }
}

function surrender(state: GameState, o: { id: string; faction: FactionId | null; rank: string; loyalty: number; region: string; clanTie: boolean }, to: FactionId, rid: string) {
  const prev = o.faction;
  o.faction = to; (o as { rank: string }).rank = 'retainer'; o.loyalty = 45; o.clanTie = false; o.region = rid;
  addLog(state, 'log.surrendered', { name: officerDef(o.id).name, to }, to, true);
  if (prev) addLog(state, 'log.defected', { name: officerDef(o.id).name, from: prev, to }, prev, true);
}
