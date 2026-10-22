// ===== 即時戰鬥（20〜40 秒）=====
// 沿用 battle.ts 的數值：戰術剋制、武將修正、兵種、地形、士氣、訓練、城防。
// 差別在於雙方「陣形」是連續狀態，可隨時改陣（有 0.8 秒的改陣空檔），
// 敵方 AI 改陣前會有預告，我方主將智謀越高就越早看見。
// 本模組不依賴 DOM / three.js，可在 Node 無頭執行。

import type { BattleState, BattleSide, Tactic } from '../core/types';
import { MATCHUP, cmdOf, effectiveStrength, officerMod, applyLoss, canUseTactic } from './battle';
import { clamp, totalTroops } from '../core/state';
import type { Rng } from '../core/rng';

export type Stance = 'charge' | 'hold' | 'volley' | 'maneuver';
export const STANCES: Stance[] = ['charge', 'hold', 'volley', 'maneuver'];
export type SideKey = 'attacker' | 'defender';

/** 一「回合」約 4.5 秒：8 回合 ≈ 36 秒 */
const ROUND_SEC = 4.5;
const BASE_PER_SEC = 0.08 / ROUND_SEC;
export const SWITCH_TIME = 0.8;   // 改陣空檔
export const WINDUP_TIME = 1.2;   // AI 預告到開始改陣
export const RALLY_CD = 9;
export const RETREAT_TIME = 2.0;

export type RtEventKind = 'switch' | 'telegraph' | 'fire' | 'duel' | 'rally' | 'retreat' | 'rout' | 'timeout';
export interface RtEvent {
  t: number;
  kind: RtEventKind;
  side: SideKey;
  stance?: Stance;
  ok?: boolean;        // fire / duel 成功與否（以 side 的角度）
  loss?: number;       // fire 造成的敵方損失
  note?: string;       // i18n key
}

export interface RtSideState {
  stance: Stance;
  pending: Stance | null;
  switching: number;            // 剩餘改陣秒數
  telegraph: { stance: Stance; at: number } | null; // AI 預告（at = 開始改陣的時刻）
  fireUsed: boolean;
  duelUsed: boolean;
  rallyCd: number;
  rallyPenalty: number;         // 鼓舞後整隊的秒數（輸出 ×0.6）
  retreating: number;           // >0 撤退中（剩餘秒數）
  nextDecision: number;
  lossAcc: number;              // 尚未結算成整數的損失
  lossSinceEvent: number;       // 給 UI 做墨漬用
  reacted: boolean;             // 本輪是否已對敵方改陣反應
}

export interface RtBattle {
  b: BattleState;
  time: number;
  duration: number;
  sides: Record<SideKey, RtSideState>;
  events: RtEvent[];
  over: boolean;
  /** 戰鬥開始後的統計（給結算） */
  stats: Record<SideKey, { loss: number; switches: number }>;
}

function other(s: SideKey): SideKey { return s === 'attacker' ? 'defender' : 'attacker'; }

function newSide(stance: Stance): RtSideState {
  return { stance, pending: null, switching: 0, telegraph: null, fireUsed: false, duelUsed: false, rallyCd: 0, rallyPenalty: 0, retreating: 0, nextDecision: 1.5, lossAcc: 0, lossSinceEvent: 0, reacted: false };
}

/** 此刻能用哪些陣形 */
export function canStance(b: BattleState, side: BattleSide, s: Stance): { ok: boolean; reason?: string } {
  return canUseTactic(b, side, s as Tactic);
}

export function canFire(rt: RtBattle, who: SideKey): { ok: boolean; reason?: string } {
  if (rt.sides[who].fireUsed) return { ok: false, reason: 'battle.cant.fireUsed' };
  const b = rt.b, side = b[who];
  if (b.weather === 'rain') return { ok: false, reason: 'battle.cant.rain' };
  const c = cmdOf(side);
  if (!(c.intel >= 80 || c.traits.includes('strategist'))) return { ok: false, reason: 'battle.cant.intel' };
  return { ok: true };
}

export function canDuel(rt: RtBattle, who: SideKey): { ok: boolean; reason?: string } {
  if (rt.sides[who].duelUsed || rt.sides[other(who)].duelUsed) return { ok: false, reason: 'battle.cant.duelUsed' };
  if (!rt.b.attacker.commander || !rt.b.defender.commander) return { ok: false, reason: 'battle.cant.noCommander' };
  return { ok: true };
}

export function canRetreat(rt: RtBattle, who: SideKey): { ok: boolean; reason?: string } {
  if (who === 'defender' && rt.b.siege) return { ok: false, reason: 'battle.cant.besieged' };
  if (rt.sides[who].retreating > 0) return { ok: false, reason: 'battle.cant.retreating' };
  return { ok: true };
}

/** 我方對敵方「預告」的可見提前量（秒）：智謀差越大越早看到 */
export function telegraphLead(rt: RtBattle, me: SideKey): number {
  const mine = cmdOf(rt.b[me]), theirs = cmdOf(rt.b[other(me)]);
  return clamp(0.25 + (mine.intel - theirs.intel) / 40, 0, WINDUP_TIME);
}

/** 敵方預告對我方是否已可見 */
export function visibleTelegraph(rt: RtBattle, me: SideKey): Stance | null {
  const tg = rt.sides[other(me)].telegraph;
  if (!tg) return null;
  return rt.time >= tg.at - telegraphLead(rt, me) ? tg.stance : null;
}

export function createRtBattle(b: BattleState, rng: Rng, opts: { playerSide: SideKey | null; playerStance?: Stance }): RtBattle {
  const aiStart = (who: SideKey): Stance => {
    const w = stanceWeights(b, who, null);
    return pick(w, rng);
  };
  const atkStance = opts.playerSide === 'attacker' && opts.playerStance ? opts.playerStance : aiStart('attacker');
  const defStance = opts.playerSide === 'defender' && opts.playerStance ? opts.playerStance : aiStart('defender');
  const rt: RtBattle = {
    b, time: 0, duration: b.siege ? 40 : 36,
    sides: { attacker: newSide(atkStance), defender: newSide(defStance) },
    events: [], over: false,
    stats: { attacker: { loss: 0, switches: 0 }, defender: { loss: 0, switches: 0 } },
  };
  // AI 第一次決策稍晚，給玩家看清楚初始陣形
  rt.sides.attacker.nextDecision = 2.5 + rng.range(0, 1.5);
  rt.sides.defender.nextDecision = 2.5 + rng.range(0, 1.5);
  return rt;
}

// ---------------------------------------------------------------------------
// 玩家 / AI 指令
// ---------------------------------------------------------------------------

export function rtSetStance(rt: RtBattle, who: SideKey, s: Stance): boolean {
  const st = rt.sides[who];
  if (rt.over || st.retreating > 0) return false;
  if (st.stance === s && !st.pending) return false;
  if (st.switching > 0) return false;
  if (!canStance(rt.b, rt.b[who], s).ok) return false;
  st.pending = s;
  st.switching = SWITCH_TIME;
  st.telegraph = null;
  rt.stats[who].switches++;
  rt.events.push({ t: rt.time, kind: 'switch', side: who, stance: s });
  // 對方 AI 可能反應
  rt.sides[other(who)].reacted = false;
  return true;
}

export function rtFire(rt: RtBattle, who: SideKey, rng: Rng): boolean {
  if (rt.over || !canFire(rt, who).ok) return false;
  const st = rt.sides[who];
  st.fireUsed = true;
  const b = rt.b, me = b[who], foe = b[other(who)];
  const c = cmdOf(me);
  const p = clamp(0.35 + (c.intel - 70) / 100 + (b.terrain === 'mountain' ? 0.15 : 0) + (c.traits.includes('strategist') ? 0.15 : 0), 0.15, 0.9);
  const ok = rng.chance(p);
  const foeStance = rt.sides[other(who)].stance;
  // 成功：敵方損失 10%（方陣 16%），士氣 -15；失敗：零星損失
  const ratio = ok ? (foeStance === 'hold' ? 0.16 : 0.10) : 0.02;
  const loss = Math.round(totalTroops(foe) * ratio);
  applyLoss(foe, loss);
  rt.stats[other(who)].loss += loss;
  rt.sides[other(who)].lossSinceEvent += loss;
  if (ok) { foe.morale = clamp(foe.morale - 15, 0, 130); me.morale = clamp(me.morale + 5, 0, 130); }
  rt.events.push({ t: rt.time, kind: 'fire', side: who, ok, loss, note: ok ? (who === 'attacker' ? 'battle.note.fireAtkOk' : 'battle.note.fireDefOk') : (who === 'attacker' ? 'battle.note.fireAtkFail' : 'battle.note.fireDefFail') });
  checkEnd(rt);
  return true;
}

export function rtDuel(rt: RtBattle, who: SideKey, rng: Rng): boolean {
  if (rt.over || !canDuel(rt, who).ok) return false;
  rt.sides.attacker.duelUsed = true; rt.sides.defender.duelUsed = true;
  const A = rt.b.attacker, D = rt.b.defender;
  const ca = cmdOf(A), cd = cmdOf(D);
  const sa = ca.valor + (ca.traits.includes('duelist') ? 15 : 0) + rng.int(0, 30);
  const sd = cd.valor + (cd.traits.includes('duelist') ? 15 : 0) + rng.int(0, 30);
  const atkWin = sa > sd;
  if (atkWin) { A.morale = clamp(A.morale + 25, 0, 130); D.morale = clamp(D.morale - 20, 0, 130); }
  else { D.morale = clamp(D.morale + 25, 0, 130); A.morale = clamp(A.morale - 20, 0, 130); }
  rt.events.push({ t: rt.time, kind: 'duel', side: who, ok: (who === 'attacker') === atkWin, note: atkWin ? 'battle.note.duelAtkWin' : 'battle.note.duelDefWin' });
  checkEnd(rt);
  return true;
}

export function rtRally(rt: RtBattle, who: SideKey): boolean {
  const st = rt.sides[who];
  if (rt.over || st.rallyCd > 0 || st.retreating > 0) return false;
  const c = cmdOf(rt.b[who]);
  const gain = 8 + Math.round(c.charm / 10);
  rt.b[who].morale = clamp(rt.b[who].morale + gain, 0, 130);
  st.rallyCd = RALLY_CD;
  st.rallyPenalty = 1.5;
  rt.events.push({ t: rt.time, kind: 'rally', side: who });
  return true;
}

export function rtRetreat(rt: RtBattle, who: SideKey): boolean {
  if (rt.over || !canRetreat(rt, who).ok) return false;
  rt.sides[who].retreating = RETREAT_TIME;
  rt.sides[who].pending = null; rt.sides[who].switching = 0; rt.sides[who].telegraph = null;
  rt.events.push({ t: rt.time, kind: 'retreat', side: who });
  return true;
}

// ---------------------------------------------------------------------------
// AI
// ---------------------------------------------------------------------------

function stanceWeights(b: BattleState, who: SideKey, enemyStance: Stance | null): { s: Stance; w: number }[] {
  const side = b[who];
  const c = cmdOf(side);
  const n = Math.max(1, totalTroops(side));
  const w: Record<Stance, number> = { charge: 1, hold: 1, volley: 0, maneuver: 0.6 };
  w.charge += c.valor / 60 + (side.troops.cavalry / n) * 2 + (c.traits.includes('berserk') ? 1 : 0) + (b.terrain === 'mountain' ? -0.4 : 0);
  w.hold += c.lead / 70 + (who === 'defender' ? 0.8 + b.defense / 100 : 0);
  if (canUseTactic(b, side, 'volley').ok) w.volley = 0.5 + (side.troops.gun / n) * 5 + (c.traits.includes('gunner') ? 1 : 0);
  w.maneuver += c.intel / 80 + (c.traits.includes('strategist') ? 0.8 : 0);
  if (enemyStance) {
    // 反制：依剋制矩陣調整
    for (const s of STANCES) if (w[s] > 0) w[s] *= 0.6 + (MATCHUP[s][enemyStance] ?? 1) * 0.7;
  }
  return STANCES.map(s => ({ s, w: Math.max(0, canUseTactic(b, side, s).ok ? w[s] : 0) }));
}

function pick(weights: { s: Stance; w: number }[], rng: Rng): Stance {
  const total = weights.reduce((a, x) => a + x.w, 0);
  if (total <= 0) return 'hold';
  let r = rng.next() * total;
  for (const x of weights) { r -= x.w; if (r <= 0) return x.s; }
  return 'hold';
}

function aiDecide(rt: RtBattle, who: SideKey, rng: Rng): void {
  const st = rt.sides[who];
  const b = rt.b, me = b[who], foe = b[other(who)];
  const c = cmdOf(me);
  const foeSt = rt.sides[other(who)];
  const myN = totalTroops(me), foeN = totalTroops(foe);

  // 撤退判斷
  if (canRetreat(rt, who).ok && (me.morale < 22 || myN < foeN * 0.3) && rng.chance(0.5)) { rtRetreat(rt, who); return; }
  // 鼓舞
  if (st.rallyCd <= 0 && me.morale < 55 && rng.chance(0.6)) { rtRally(rt, who); }
  // 火計：敵方方陣時最划算
  if (canFire(rt, who).ok && (foeSt.stance === 'hold' ? rng.chance(0.7) : rng.chance(0.15))) { rtFire(rt, who, rng); return; }
  // 一騎討：武勇明顯佔優
  if (canDuel(rt, who).ok) {
    const ec = cmdOf(foe);
    if (c.valor > ec.valor + 12 && rng.chance(0.35 + (c.traits.includes('duelist') ? 0.3 : 0))) { rtDuel(rt, who, rng); return; }
  }
  // 改陣：看得見敵方目前陣形；智謀高則幾乎必反制
  const seeEnemy = rng.chance(clamp(0.35 + c.intel / 120, 0.35, 0.95));
  const target = pick(stanceWeights(b, who, seeEnemy ? (foeSt.pending ?? foeSt.stance) : null), rng);
  if (target !== st.stance && st.switching <= 0) {
    st.telegraph = { stance: target, at: rt.time + WINDUP_TIME };
    rt.events.push({ t: rt.time, kind: 'telegraph', side: who, stance: target });
  }
}

// ---------------------------------------------------------------------------
// 每步結算
// ---------------------------------------------------------------------------

function outputMul(st: RtSideState): number {
  let m = 1;
  if (st.switching > 0) m *= 0.5;
  if (st.rallyPenalty > 0) m *= 0.6;
  if (st.retreating > 0) m = 0;
  return m;
}

/** 推進 dt 秒。aiSides：由 AI 控制的陣營。 */
export function rtStep(rt: RtBattle, dt: number, rng: Rng, aiSides: SideKey[]): void {
  if (rt.over) return;
  const b = rt.b;
  rt.time += dt;

  for (const who of ['attacker', 'defender'] as SideKey[]) {
    const st = rt.sides[who];
    // 計時器
    if (st.switching > 0) {
      st.switching -= dt;
      if (st.switching <= 0 && st.pending) { st.stance = st.pending; st.pending = null; st.switching = 0; }
    }
    if (st.rallyCd > 0) st.rallyCd = Math.max(0, st.rallyCd - dt);
    if (st.rallyPenalty > 0) st.rallyPenalty = Math.max(0, st.rallyPenalty - dt);
    if (st.retreating > 0) {
      st.retreating -= dt;
      if (st.retreating <= 0) {
        rt.over = true; b.over = true; b.winner = other(who);
        rt.events.push({ t: rt.time, kind: 'rout', side: who, note: who === 'attacker' ? 'battle.note.atkRetreat' : 'battle.note.defRetreat' });
        finalize(rt);
        return;
      }
    }
    // AI
    if (aiSides.includes(who)) {
      if (st.telegraph && rt.time >= st.telegraph.at) {
        const s = st.telegraph.stance; st.telegraph = null;
        rtSetStance(rt, who, s);
      }
      const foeSt = rt.sides[other(who)];
      // 對敵方剛改陣的快速反應（智謀高者）
      if (!st.reacted && foeSt.switching > 0 && !st.telegraph && st.switching <= 0) {
        st.reacted = true;
        const c = cmdOf(b[who]);
        if (c.intel >= 65 && rng.chance((c.intel - 50) / 60)) st.nextDecision = Math.min(st.nextDecision, rt.time + 0.5 + (100 - c.intel) / 60);
      }
      if (rt.time >= st.nextDecision) {
        const c = cmdOf(b[who]);
        st.nextDecision = rt.time + clamp(5.5 - c.intel / 35, 2.2, 5) + rng.range(0, 1.2);
        aiDecide(rt, who, rng);
        if (rt.over) return;
      }
    }
  }

  // 傷害
  const A = b.attacker, D = b.defender, sA = rt.sides.attacker, sD = rt.sides.defender;
  const ta = sA.stance, td = sD.stance;
  const moraleMul = (s: BattleSide) => 0.5 + clamp(s.morale, 0, 130) / 130 * 0.7;
  const trainMul = (s: BattleSide) => 0.7 + s.training / 250;
  const rand = () => rng.range(0.9, 1.1);

  let dmgToD = effectiveStrength(A, ta, b.terrain) * BASE_PER_SEC * (MATCHUP[ta][td] ?? 1) * officerMod(A, ta) * moraleMul(A) * trainMul(A) * outputMul(sA) * rand() * dt;
  let castleMul = 1;
  if (b.siege) {
    castleMul = 1 + b.defense / 100 * (td === 'hold' ? 0.4 : 0.15);
    if (cmdOf(A).traits.includes('siege')) castleMul = 1 + (castleMul - 1) * 0.5;
  }
  let dmgToA = effectiveStrength(D, td, b.terrain) * BASE_PER_SEC * (MATCHUP[td][ta] ?? 1) * officerMod(D, td) * moraleMul(D) * trainMul(D) * outputMul(sD) * castleMul * rand() * dt;
  if (b.siege) dmgToD *= 1 - b.defense / 100 * 0.25 * (cmdOf(A).traits.includes('siege') ? 0.5 : 1);
  // 撤退中受半傷
  if (sA.retreating > 0) dmgToA *= 0.5;
  if (sD.retreating > 0) dmgToD *= 0.5;

  const lossA = takeLoss(A, sA, dmgToA), lossD = takeLoss(D, sD, dmgToD);
  rt.stats.attacker.loss += lossA; rt.stats.defender.loss += lossD;

  // 士氣（連續版）
  const perRound = dt / ROUND_SEC;
  A.morale -= dmgToA / Math.max(1, A.initial) * 100 * 0.8;
  D.morale -= dmgToD / Math.max(1, D.initial) * 100 * 0.8;
  if ((MATCHUP[ta][td] ?? 1) > 1.2 && outputMul(sA) > 0) { D.morale -= 5 * perRound; A.morale += 2 * perRound; if (ta === 'maneuver') D.morale -= 10 * perRound; }
  if ((MATCHUP[td][ta] ?? 1) > 1.2 && outputMul(sD) > 0) { A.morale -= 5 * perRound; D.morale += 2 * perRound; if (td === 'maneuver') A.morale -= 10 * perRound; }
  if (b.siege) A.morale -= 2 * perRound;
  A.morale = clamp(A.morale, 0, 130); D.morale = clamp(D.morale, 0, 130);

  checkEnd(rt);
}

function takeLoss(side: BattleSide, st: RtSideState, dmg: number): number {
  st.lossAcc += dmg;
  const whole = Math.floor(st.lossAcc);
  if (whole <= 0) return 0;
  st.lossAcc -= whole;
  const n = totalTroops(side);
  const loss = Math.min(whole, n);
  applyLoss(side, loss);
  st.lossSinceEvent += loss;
  return loss;
}

function checkEnd(rt: RtBattle): void {
  if (rt.over) return;
  const b = rt.b, A = b.attacker, D = b.defender;
  if (totalTroops(D) <= 0 || D.morale <= 0) { b.winner = 'attacker'; rt.events.push({ t: rt.time, kind: 'rout', side: 'defender', note: 'battle.note.defRout' }); }
  else if (totalTroops(A) <= 0 || A.morale <= 0) { b.winner = 'defender'; rt.events.push({ t: rt.time, kind: 'rout', side: 'attacker', note: 'battle.note.atkRout' }); }
  else if (rt.time >= rt.duration) { b.winner = 'defender'; rt.events.push({ t: rt.time, kind: 'timeout', side: 'attacker', note: 'battle.note.timeout' }); }
  else return;
  rt.over = true; b.over = true;
  finalize(rt);
}

/** 寫回 BattleState：留一筆摘要在 rounds 供結算 / 日誌使用 */
function finalize(rt: RtBattle): void {
  const b = rt.b;
  b.round = Math.min(b.maxRounds, Math.max(1, Math.ceil(rt.time / ROUND_SEC)));
  b.attacker.fireUsed = rt.sides.attacker.fireUsed; b.defender.fireUsed = rt.sides.defender.fireUsed;
  const last = rt.events[rt.events.length - 1];
  b.rounds.push({
    round: b.round, atkTactic: rt.sides.attacker.stance, defTactic: rt.sides.defender.stance,
    atkLoss: rt.stats.attacker.loss, defLoss: rt.stats.defender.loss,
    atkMorale: Math.round(b.attacker.morale), defMorale: Math.round(b.defender.morale),
    notes: last?.note ? [last.note] : [],
  });
  b.attacker.tactic = undefined; b.defender.tactic = undefined;
}

/** 整場交給 AI（兩邊都是 AI），瞬間跑完 */
export function rtAutoResolve(b: BattleState, rng: Rng): RtBattle {
  const rt = createRtBattle(b, rng, { playerSide: null });
  while (!rt.over) rtStep(rt, 0.1, rng, ['attacker', 'defender']);
  return rt;
}

/** 目前陣形對敵方陣形的優勢：>1 有利、<1 不利 */
export function matchup(mine: Stance, theirs: Stance): number {
  return MATCHUP[mine][theirs] ?? 1;
}
