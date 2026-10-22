// ===== 軍師（新手引導 + 每月一句建議）=====
// 引導模式（flags.guide）：功能分階段解鎖，軍師每一步只要求玩家做一件事。
// 引導結束或關閉時：軍師依現況給一句最重要的建議。
import type { GameState, RegionId } from '../core/types';
import { officersOf, regionsOf, totalTroops, officerDef, officersIn, neighbourRegions, getDiplo } from '../core/state';
import { REGION_MAP } from '../data/regions';
import { troopPower } from './modifiers';

export type Feature = 'diplomacy' | 'ninja' | 'tech' | 'advanced';
export type Tab = 'region' | 'officers' | 'diplomacy' | 'tech' | 'ninja' | 'log' | 'faction';

export interface Advice {
  key: string;
  params?: Record<string, string | number>;
  /** 「帶我去」要做的事 */
  action?: { region?: RegionId; officer?: string; cmd?: string; tab?: Tab };
  /** 是否為教學步驟 */
  tutorial?: boolean;
}

export const GUIDE_DONE = 99;

export function guideActive(state: GameState): boolean {
  return !!state.flags.guide && (state.flags.guideStep as number ?? 0) < GUIDE_DONE;
}

export function guideStep(state: GameState): number {
  return (state.flags.guideStep as number) ?? 0;
}

/** 功能是否已解鎖（非引導模式一律解鎖） */
export function isUnlocked(state: GameState, f: Feature): boolean {
  if (!guideActive(state)) return true;
  const step = guideStep(state);
  switch (f) {
    case 'diplomacy': return step >= 3;
    case 'ninja': return step >= 4;
    case 'tech': return step >= 6;
    case 'advanced': return step >= 2; // 築城 / 登用 / 賞賜 / 調兵
  }
}

export function skipGuide(state: GameState): void {
  state.flags.guideStep = GUIDE_DONE;
}

function advance(state: GameState, to: number): void {
  if (guideStep(state) < to) state.flags.guideStep = to;
}

/** 玩家做了某件事 → 推進教學 */
export function onPlayerAction(state: GameState, kind: 'cmd' | 'endTurn' | 'battleEnd', key?: string): void {
  if (!guideActive(state)) return;
  const step = guideStep(state);
  if (kind === 'cmd') {
    if (step === 0 && key === 'cmd.ok.commerce') advance(state, 1);
    else if (step === 1 && key === 'cmd.ok.recruit') advance(state, 2);
    else if (step === 3 && key && (key.startsWith('cmd.ok.gift') || key.startsWith('cmd.ok.truce') || key.startsWith('cmd.ok.alliance') || key.startsWith('cmd.ok.marriage'))) advance(state, 4);
    else if (step === 4 && key === 'cmd.ok.ninjaHired') advance(state, 5);
    else if (step === 6 && key && (key === 'cmd.ok.research' || key === 'cmd.ok.researchDone')) advance(state, GUIDE_DONE);
  } else if (kind === 'endTurn') {
    // 回合結束時依時間推進（玩家沒照做也不卡關）
    if (step <= 2) advance(state, 3);
    else if (step === 3 && state.turn >= 2) advance(state, 4);
    else if (step === 4 && state.turn >= 4) advance(state, 5);
    else if (step === 6 && (state.flags.guideTechTurn as number ?? 0) + 2 <= state.turn) advance(state, GUIDE_DONE);
  } else if (kind === 'battleEnd') {
    if (step <= 5) { advance(state, 6); state.flags.guideTechTurn = state.turn; }
  }
}

function best(state: GameState, stat: 'politics' | 'charm' | 'intel' | 'lead', region?: RegionId): string | undefined {
  const pool = (region ? officersIn(state, region, state.player) : officersOf(state, state.player)).filter(o => !o.acted && !o.armyId && o.injuredMonths === 0);
  return pool.sort((a, b) => officerDef(b.id)[stat] - officerDef(a.id)[stat])[0]?.id;
}

/** 軍師本人：智謀最高的非大名武將（沒有就大名） */
export function advisorOf(state: GameState): string | undefined {
  const list = officersOf(state, state.player);
  return (list.filter(o => o.rank !== 'daimyo').sort((a, b) => officerDef(b.id).intel - officerDef(a.id).intel)[0] ?? list[0])?.id;
}

export function getAdvice(state: GameState): Advice | null {
  const p = state.player;
  const home = regionsOf(state, p)[0];
  if (!home) return null;
  if (guideActive(state)) {
    const step = guideStep(state);
    const oda = p === 'oda';
    switch (step) {
      case 0: { const o = best(state, 'politics', home.id); return { key: oda ? 'guide.0.oda' : 'guide.0', params: { name: o ?? '' }, action: { region: home.id, officer: o, cmd: 'commerce' }, tutorial: true }; }
      case 1: { const o = best(state, 'charm', home.id); return { key: 'guide.1', params: { name: o ?? '' }, action: { region: home.id, officer: o, cmd: 'recruit' }, tutorial: true }; }
      case 2: return { key: 'guide.2', action: { region: home.id }, tutorial: true };
      case 3: { const n = neighbourRegions(state, p).map(r => state.regions[r].owner).filter(Boolean)[0]; return { key: oda ? 'guide.3.oda' : 'guide.3', params: { faction: n ?? '' }, action: { tab: 'diplomacy' }, tutorial: true }; }
      case 4: return { key: oda ? 'guide.4.oda' : 'guide.4', action: { tab: 'ninja' }, tutorial: true };
      case 5: return { key: oda ? 'guide.5.oda' : 'guide.5', action: { region: home.id }, tutorial: true };
      case 6: return { key: 'guide.6', action: { tab: 'tech' }, tutorial: true };
    }
  }
  return dynamicAdvice(state);
}

function dynamicAdvice(state: GameState): Advice {
  const p = state.player; const fs = state.factions[p];
  const mine = regionsOf(state, p);
  // 1. 敵軍來襲
  for (const a of state.armies) {
    if (a.faction !== p && state.regions[a.target].owner === p) return { key: 'advice.incoming', params: { faction: a.faction, n: totalTroops(a), region: a.target }, action: { region: a.target } };
  }
  // 2. 兵糧
  const riceNeed = mine.reduce((s, r) => s + totalTroops(r) * 0.1, 0) + state.armies.filter(a => a.faction === p).reduce((s, a) => s + totalTroops(a) * 0.15, 0);
  const monthsToHarvest = state.month <= 9 ? 9 - state.month : 21 - state.month;
  if (riceNeed > 0 && fs.rice / riceNeed < Math.min(monthsToHarvest, 3)) return { key: 'advice.rice', params: { n: Math.floor(fs.rice / Math.max(1, riceNeed)) }, action: { region: mine[0].id, cmd: 'farm' } };
  // 3. 金
  if (fs.gold < 400) return { key: 'advice.gold', action: { region: mine[0].id, cmd: 'commerce' } };
  // 4. 民忠
  const low = mine.filter(r => r.loyalty < 40).sort((a, b) => a.loyalty - b.loyalty)[0];
  if (low) return { key: 'advice.loyalty', params: { region: low.id }, action: { region: low.id, cmd: 'govern' } };
  // 5. 家臣忠誠
  const unhappy = officersOf(state, p).filter(o => o.rank !== 'daimyo' && o.loyalty < 45).sort((a, b) => a.loyalty - b.loyalty)[0];
  if (unhappy) return { key: 'advice.officer', params: { name: unhappy.id }, action: { region: unhappy.region, cmd: 'reward' } };
  // 6. 待命武將
  const idle = officersOf(state, p).filter(o => !o.acted && !o.armyId && o.injuredMonths === 0);
  if (idle.length) return { key: 'advice.idle', params: { n: idle.length }, action: { region: idle[0].region, officer: idle[0].id } };
  // 7. 弱鄰
  let bestTarget: { from: RegionId; to: RegionId; ratio: number } | null = null;
  for (const r of mine) {
    for (const adj of REGION_MAP[r.id].adjacent) {
      const t = state.regions[adj];
      if (t.owner === p) continue;
      if (t.owner) { const d = getDiplo(state, p, t.owner); if (d.alliance || d.truce || d.marriage) continue; }
      const ratio = troopPower(r.troops, r.training) / Math.max(1, troopPower(t.troops, t.training) * (1 + t.defense / 100));
      if (ratio > 1.4 && (!bestTarget || ratio > bestTarget.ratio)) bestTarget = { from: r.id, to: adj, ratio };
    }
  }
  if (bestTarget) return { key: 'advice.weakNeighbour', params: { region: bestTarget.to, from: bestTarget.from }, action: { region: bestTarget.from, cmd: 'march' } };
  // 8. 預設
  return { key: fs.research.tech ? 'advice.stable' : 'advice.research', action: { tab: 'tech' } };
}
