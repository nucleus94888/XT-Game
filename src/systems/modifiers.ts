import type { GameState, RegionId, FactionId } from '../core/types';
import { REGION_MAP } from '../data/regions';
import { techTier } from '../data/techs';

/** 區域與勢力的各種倍率，所有系統共用這一份 */
export interface RegionMods {
  goldMul: number;        // 商業收入倍率
  riceMul: number;        // 秋收倍率
  recruitCostMul: number; // 徵兵金錢倍率
  defenseCap: number;     // 城防上限
  loyaltyDrift: number;   // 每月民忠自然變化
  cavalryBonus: number;   // 騎馬徵得比例加成
  gunBonus: number;       // 鐵砲徵得比例加成
}

export function regionMods(state: GameState, id: RegionId): RegionMods {
  const def = REGION_MAP[id];
  const owner = state.regions[id].owner;
  const m: RegionMods = { goldMul: 1, riceMul: 1, recruitCostMul: 1, defenseCap: 80, loyaltyDrift: 1, cavalryBonus: 0, gunBonus: 0 };
  for (const b of def.bonuses) {
    switch (b) {
      case 'nanban_trade': case 'tsushima_port': m.goldMul += 0.2; break;
      case 'port': m.goldMul += 0.1; break;
      case 'lake_trade': m.goldMul += 0.15; break;
      case 'silver_mine': m.goldMul += 0.15; break;
      case 'iwami_silver': m.goldMul += 0.25; break;
      case 'kyoto': m.goldMul += 0.3; break;
      case 'ichiryo_gusoku': m.recruitCostMul -= 0.2; break;
      case 'ikko_ikki': m.loyaltyDrift -= 1.5; break;
      case 'ise_shrine': m.loyaltyDrift += 1; break;
      case 'natural_fort': m.defenseCap = 95; break;
      case 'odawara': m.defenseCap = 100; break;
      case 'gold_mine_cav': m.goldMul += 0.1; m.cavalryBonus += 0.2; break;
      case 'early_gun': case 'saiga_gunners': m.gunBonus += 0.15; break;
      case 'great_province': m.riceMul += 0.1; break;
      case 'vast_land': m.riceMul += 0.1; m.goldMul -= 0.1; break;
    }
  }
  if (id === 'echigo') m.cavalryBonus += 0.1;
  if (owner) {
    const t = state.factions[owner].techs;
    m.riceMul += 0.1 * techTier(t, 'agri');
    m.goldMul += 0.1 * techTier(t, 'commerce');
    m.defenseCap = Math.min(100, m.defenseCap + 5 * techTier(t, 'castle'));
  }
  return m;
}

export function factionHasTech(state: GameState, f: FactionId, tech: string): boolean {
  return state.factions[f].techs.includes(tech);
}

/** 鐵砲兵是否可徵（需「鐵砲傳來」或區域天然優勢） */
export function canRecruitGuns(state: GameState, f: FactionId, region: RegionId): boolean {
  return factionHasTech(state, f, 'mil2') || REGION_MAP[region].bonuses.some(b => b === 'early_gun' || b === 'saiga_gunners');
}

/** 戰力粗估（AI 與 UI 用） */
export function troopPower(troops: { ashigaru: number; cavalry: number; gun: number }, training: number): number {
  return (troops.ashigaru + troops.cavalry * 1.4 + troops.gun * 1.3) * (0.6 + training / 250);
}
