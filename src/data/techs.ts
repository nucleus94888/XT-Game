import type { TechDef } from '../core/types';

// 四系 × 四階。名稱與說明在 i18n：tech.<id>.name / tech.<id>.desc
export const TECHS: TechDef[] = [
  // 農業：灌溉 → 新田開發 → 二毛作 → 檢地
  { id: 'agri1', branch: 'agri', tier: 1, cost: 300 },
  { id: 'agri2', branch: 'agri', tier: 2, cost: 600, requires: 'agri1' },
  { id: 'agri3', branch: 'agri', tier: 3, cost: 1000, requires: 'agri2' },
  { id: 'agri4', branch: 'agri', tier: 4, cost: 1600, requires: 'agri3' },
  // 商業：樂市 → 樂座 → 撰錢令 → 南蠻貿易
  { id: 'com1', branch: 'commerce', tier: 1, cost: 300 },
  { id: 'com2', branch: 'commerce', tier: 2, cost: 600, requires: 'com1' },
  { id: 'com3', branch: 'commerce', tier: 3, cost: 1000, requires: 'com2' },
  { id: 'com4', branch: 'commerce', tier: 4, cost: 1600, requires: 'com3' },
  // 軍事：足輕組 → 鐵砲傳來 → 三段擊 → 兵農分離
  { id: 'mil1', branch: 'military', tier: 1, cost: 300 },
  { id: 'mil2', branch: 'military', tier: 2, cost: 700, requires: 'mil1' },
  { id: 'mil3', branch: 'military', tier: 3, cost: 1200, requires: 'mil2' },
  { id: 'mil4', branch: 'military', tier: 4, cost: 1800, requires: 'mil3' },
  // 築城：石垣 → 天守 → 總構 → 水堀
  { id: 'castle1', branch: 'castle', tier: 1, cost: 300 },
  { id: 'castle2', branch: 'castle', tier: 2, cost: 600, requires: 'castle1' },
  { id: 'castle3', branch: 'castle', tier: 3, cost: 1000, requires: 'castle2' },
  { id: 'castle4', branch: 'castle', tier: 4, cost: 1600, requires: 'castle3' },
];

export const TECH_MAP: Record<string, TechDef> = Object.fromEntries(TECHS.map(t => [t.id, t]));

export function techTier(techs: string[], branch: TechDef['branch']): number {
  return TECHS.filter(t => t.branch === branch && techs.includes(t.id)).length;
}
