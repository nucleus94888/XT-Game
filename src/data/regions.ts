import type { RegionDef } from '../core/types';

// 地圖形狀與座標見 data/geo.ts（由真實地理資料產生）；此處只定義遊戲屬性與相鄰關係
export const REGIONS: RegionDef[] = [
  {
    id: 'satsuma', castle: '內城', terrain: 'mountain', bonuses: ['early_gun'],
    adjacent: ['bungo', 'hizen'],
    init: { owner: 'shimazu', kokudaka: 36, commerce: 50, loyalty: 70, defense: 55, troops: 9000, rice: 20000 },
  },
  {
    id: 'bungo', castle: '府內', terrain: 'plain', bonuses: ['nanban_trade'],
    adjacent: ['satsuma', 'hizen', 'suo'],
    init: { owner: 'otomo', kokudaka: 42, commerce: 95, loyalty: 65, defense: 50, troops: 11000, rice: 24000 },
  },
  {
    id: 'hizen', castle: '佐嘉', terrain: 'plain', bonuses: ['port'],
    adjacent: ['satsuma', 'bungo', 'suo'],
    init: { owner: 'ryuzoji', kokudaka: 38, commerce: 60, loyalty: 60, defense: 45, troops: 6000, rice: 15000 },
  },
  {
    id: 'suo', castle: '吉田郡山', terrain: 'mountain', bonuses: ['silver_mine'],
    adjacent: ['bungo', 'hizen', 'izumo', 'awa'],
    init: { owner: 'mori', kokudaka: 48, commerce: 80, loyalty: 70, defense: 60, troops: 14000, rice: 28000 },
  },
  {
    id: 'izumo', castle: '月山富田', terrain: 'mountain', bonuses: ['iwami_silver'],
    adjacent: ['suo', 'kinai', 'awa'],
    init: { owner: 'amago', kokudaka: 40, commerce: 85, loyalty: 60, defense: 70, troops: 9000, rice: 18000 },
  },
  {
    id: 'tosa', castle: '岡豐', terrain: 'mountain', bonuses: ['ichiryo_gusoku'],
    adjacent: ['awa'],
    init: { owner: 'chosokabe', kokudaka: 30, commerce: 35, loyalty: 75, defense: 45, troops: 6000, rice: 14000 },
  },
  {
    id: 'awa', castle: '勝瑞', terrain: 'plain', bonuses: ['navy'],
    adjacent: ['tosa', 'suo', 'izumo', 'kinai'],
    init: { owner: 'miyoshi', kokudaka: 34, commerce: 55, loyalty: 65, defense: 45, troops: 8000, rice: 16000 },
  },
  {
    id: 'kinai', castle: '二條', terrain: 'plain', bonuses: ['kyoto'],
    adjacent: ['awa', 'izumo', 'yamato', 'omi', 'echizen', 'ise'],
    init: { owner: 'miyoshi', kokudaka: 50, commerce: 150, loyalty: 55, defense: 50, troops: 12000, rice: 22000 },
  },
  {
    id: 'yamato', castle: '筒井', terrain: 'mountain', bonuses: ['saiga_gunners'],
    adjacent: ['kinai', 'omi', 'ise'],
    init: { owner: 'tsutsui', kokudaka: 36, commerce: 60, loyalty: 55, defense: 45, troops: 6000, rice: 14000 },
  },
  {
    id: 'omi', castle: '小谷', terrain: 'plain', bonuses: ['lake_trade'],
    adjacent: ['kinai', 'yamato', 'echizen', 'mino', 'ise'],
    init: { owner: 'azai', kokudaka: 46, commerce: 90, loyalty: 65, defense: 55, troops: 7000, rice: 18000 },
  },
  {
    id: 'echizen', castle: '一乘谷', terrain: 'mountain', bonuses: ['ikko_ikki'],
    adjacent: ['omi', 'mino', 'echigo', 'kinai', 'kai'],
    init: { owner: 'asakura', kokudaka: 44, commerce: 70, loyalty: 50, defense: 50, troops: 8000, rice: 20000 },
  },
  {
    id: 'mino', castle: '稻葉山', terrain: 'mountain', bonuses: ['natural_fort'],
    adjacent: ['echizen', 'omi', 'owari', 'kai', 'mikawa'],
    init: { owner: 'saito', kokudaka: 48, commerce: 65, loyalty: 55, defense: 80, troops: 9000, rice: 20000 },
  },
  {
    id: 'ise', castle: '大河內', terrain: 'plain', bonuses: ['ise_shrine'],
    adjacent: ['yamato', 'omi', 'owari', 'kinai'],
    init: { owner: 'kitabatake', kokudaka: 40, commerce: 70, loyalty: 75, defense: 45, troops: 5000, rice: 15000 },
  },
  {
    id: 'owari', castle: '清洲', terrain: 'plain', bonuses: ['tsushima_port'],
    adjacent: ['mino', 'ise', 'mikawa'],
    init: { owner: 'oda', kokudaka: 52, commerce: 100, loyalty: 65, defense: 50, troops: 8000, rice: 18000 },
  },
  {
    id: 'mikawa', castle: '駿府', terrain: 'plain', bonuses: ['great_province'],
    adjacent: ['owari', 'kai', 'sagami', 'mino'],
    init: { owner: 'imagawa', kokudaka: 70, commerce: 95, loyalty: 65, defense: 55, troops: 22000, rice: 40000 },
  },
  {
    id: 'kai', castle: '躑躅崎館', terrain: 'mountain', bonuses: ['gold_mine_cav'],
    adjacent: ['mino', 'mikawa', 'echigo', 'sagami', 'echizen'],
    init: { owner: 'takeda', kokudaka: 55, commerce: 55, loyalty: 70, defense: 50, troops: 16000, rice: 26000 },
  },
  {
    id: 'echigo', castle: '春日山', terrain: 'mountain', bonuses: ['heavy_snow', 'port'],
    adjacent: ['echizen', 'kai', 'sagami', 'oshu'], snowMonths: [12, 1, 2],
    init: { owner: 'uesugi', kokudaka: 52, commerce: 75, loyalty: 70, defense: 65, troops: 15000, rice: 28000 },
  },
  {
    id: 'sagami', castle: '小田原', terrain: 'plain', bonuses: ['odawara'],
    adjacent: ['mikawa', 'kai', 'echigo', 'oshu'],
    init: { owner: 'hojo', kokudaka: 60, commerce: 90, loyalty: 80, defense: 95, troops: 16000, rice: 32000 },
  },
  {
    id: 'oshu', castle: '米澤', terrain: 'mountain', bonuses: ['vast_land', 'heavy_snow'],
    adjacent: ['echigo', 'sagami'], snowMonths: [12, 1, 2, 3],
    init: { owner: 'date', kokudaka: 65, commerce: 40, loyalty: 60, defense: 50, troops: 8000, rice: 26000 },
  },
];

export const REGION_MAP: Record<string, RegionDef> = Object.fromEntries(REGIONS.map(r => [r.id, r]));
