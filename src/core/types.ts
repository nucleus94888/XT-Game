// ===== 共用型別定義 =====
// 遊戲邏輯層的所有資料結構。渲染層與 UI 層只讀取這些型別，不定義新的狀態。

export type RegionId =
  | 'satsuma' | 'bungo' | 'hizen' | 'suo' | 'izumo' | 'tosa' | 'awa' | 'kinai' | 'yamato'
  | 'omi' | 'echizen' | 'mino' | 'ise' | 'owari' | 'mikawa' | 'kai' | 'echigo' | 'sagami' | 'oshu';

export type FactionId =
  | 'oda' | 'imagawa' | 'takeda' | 'uesugi' | 'hojo' | 'mori' | 'miyoshi' | 'chosokabe' | 'shimazu' | 'otomo'
  | 'ryuzoji' | 'amago' | 'tsutsui' | 'azai' | 'asakura' | 'saito' | 'kitabatake' | 'date';

export type Terrain = 'plain' | 'mountain';

export type RegionBonus =
  | 'early_gun'      // 鐵砲研究 -1 回合
  | 'nanban_trade'   // 商業 +20%
  | 'port'           // 商業 +10%
  | 'silver_mine'    // 金 +15%
  | 'iwami_silver'   // 金 +25%
  | 'ichiryo_gusoku' // 徵兵成本 -20%
  | 'navy'           // 水軍：跨海攻擊無懲罰
  | 'kyoto'          // 京都：名聲
  | 'saiga_gunners'  // 鐵砲兵 +
  | 'lake_trade'     // 商業 +15%
  | 'ikko_ikki'      // 民忠不穩
  | 'natural_fort'   // 城防 +
  | 'ise_shrine'     // 民忠 +
  | 'tsushima_port'  // 商業 +20%
  | 'great_province' // 石高高
  | 'gold_mine_cav'  // 金山 + 騎馬
  | 'heavy_snow'     // 豪雪
  | 'odawara'        // 城防最高
  | 'vast_land';     // 廣大

export interface RegionDef {
  id: RegionId;
  /** 主城名（繁中，i18n 以 id 查表） */
  castle: string;
  adjacent: RegionId[];
  terrain: Terrain;
  bonuses: RegionBonus[];
  /** 開局數值 */
  init: {
    owner: FactionId | null;
    kokudaka: number;   // 石高（萬石 ×10，例如尾張 57 萬石 → 57）
    commerce: number;   // 商業 0–200
    loyalty: number;    // 民忠 0–100
    defense: number;    // 城防 0–100
    troops: number;     // 駐軍
    rice: number;       // 糧
  };
  /** 豪雪封鎖的月份（1–12） */
  snowMonths?: number[];
}

export type Trait =
  | 'cavalry' | 'gunner' | 'builder' | 'ninja_master' | 'diplomat' | 'berserk'
  | 'strategist' | 'loyal' | 'ambitious' | 'siege' | 'naval' | 'merchant' | 'farmer'
  | 'duelist' | 'inspiring' | 'scholar';

export type Rank = 'daimyo' | 'heir' | 'retainer' | 'ronin';

export interface OfficerDef {
  id: string;
  /** 漢字姓名（zh-TW 與 ja 共用） */
  name: string;
  /** 羅馬拼音（en） */
  nameEn: string;
  faction: FactionId | null;   // null = 在野
  region: RegionId;            // 開局所在區
  rank: Rank;
  birth: number;
  death: number;               // 史實死亡年
  lead: number;
  valor: number;
  intel: number;
  politics: number;
  charm: number;
  loyalty: number;             // 開局忠誠
  traits: Trait[];
  clanTie?: boolean;           // 一門
  /** 性格：影響 AI 大名決策與相性 */
  personality?: 'aggressive' | 'balanced' | 'defensive' | 'cunning';
}

export interface FactionDef {
  id: FactionId;
  name: string;                // 家名（漢字）
  nameEn: string;
  daimyo: string;              // officer id
  major: boolean;              // 可選
  difficulty: 1 | 2 | 3 | 4;
  /** 家徽 id（對應 src/data/kamon） */
  kamon: string;
  /** 勢力代表色（十六進位） */
  color: number;
  /** 開局資源 */
  init: { gold: number; princesses: number; credit: number };
  /** 開局已有技術 */
  techs: string[];
}

export type TechBranch = 'agri' | 'commerce' | 'military' | 'castle';

export interface TechDef {
  id: string;
  branch: TechBranch;
  tier: 1 | 2 | 3 | 4;
  cost: number;        // 研究點數
  requires?: string;   // 前置技術 id
}

export type TroopType = 'ashigaru' | 'cavalry' | 'gun';

export type Tactic = 'charge' | 'hold' | 'volley' | 'maneuver' | 'fire' | 'duel' | 'retreat';

// ===== 執行期狀態 =====

export interface RegionState {
  id: RegionId;
  owner: FactionId | null;
  kokudaka: number;
  commerce: number;
  loyalty: number;
  defense: number;
  troops: { ashigaru: number; cavalry: number; gun: number };
  training: number;   // 0–100
}

export interface OfficerState {
  id: string;
  faction: FactionId | null;
  region: RegionId;
  rank: Rank;
  loyalty: number;
  /** 本月是否已行動 */
  acted: boolean;
  /** 本月執行的指令（cmd key 的尾段，如 commerce） */
  lastCmd?: string;
  /** 連續閒置月數 */
  idleMonths: number;
  injuredMonths: number;
  alive: boolean;
  /** 真實死亡年（史實 ± 隨機） */
  deathYear: number;
  clanTie: boolean;
  /** 正在出征的軍團 id */
  armyId?: string;
}

export interface Army {
  id: string;
  faction: FactionId;
  from: RegionId;
  target: RegionId;
  troops: { ashigaru: number; cavalry: number; gun: number };
  training: number;
  commander: string;
  officers: string[];  // 含主將
  /** 剩餘行軍回合 */
  eta: number;
  /** 圍城中 */
  sieging?: boolean;
}

export interface DiplomacyPair {
  relation: number;        // -100〜100
  alliance?: number;       // 剩餘月數
  truce?: number;
  marriage?: number;       // 婚姻同盟剩餘月數
}

export interface FactionState {
  id: FactionId;
  gold: number;
  rice: number;                // 兵糧（全勢力共用）
  princesses: number;
  credit: number;              // 信用 0–100
  techs: string[];
  research: { tech: string | null; progress: number };
  ninja: { clan: string | null; level: number };
  alive: boolean;
  /** 已知情報（諜報結果）：區域 id → 到期回合 */
  intel: Record<string, number>;
  /** 歷史名聲：影響勸降、登用 */
  fame: number;
}

export interface GameState {
  seed: number;
  turn: number;          // 從 0 起算
  year: number;
  month: number;         // 1–12
  player: FactionId;
  regions: Record<RegionId, RegionState>;
  officers: Record<string, OfficerState>;
  factions: Record<FactionId, FactionState>;
  armies: Army[];
  diplomacy: Record<string, DiplomacyPair>;   // key: `${a}|${b}` 以字母序
  log: LogEntry[];
  flags: Record<string, boolean | number>;    // 事件旗標
  /** 等待玩家指揮的戰鬥（依序處理） */
  battleQueue: BattleState[];
  /** 等待玩家回應的事件 */
  pendingEvents: PendingEvent[];
  gameOver?: { winner: FactionId | null; reason: string };
}

export interface PendingEvent {
  id: string;                  // 事件 id（i18n: event.<id>.title / .desc）
  params?: Record<string, string | number>;
  choices: string[];           // 選項 key（i18n: event.<id>.choice.<key>）
}

// ===== 戰鬥 =====

export interface BattleSide {
  faction: FactionId;
  troops: { ashigaru: number; cavalry: number; gun: number };
  initial: number;
  training: number;
  morale: number;
  commander: string | null;    // officer id；null = 無將（以 40 計）
  officers: string[];
  fireUsed: boolean;
  /** 本回合選擇的戰術（由 UI 或 AI 填入） */
  tactic?: Tactic;
}

export interface BattleRoundLog {
  round: number;
  atkTactic: Tactic;
  defTactic: Tactic;
  atkLoss: number;
  defLoss: number;
  atkMorale: number;
  defMorale: number;
  notes: string[];             // i18n keys，如 battle.note.fireSuccess
}

export interface BattleState {
  id: string;
  armyId: string;
  region: RegionId;
  terrain: Terrain;
  weather: 'clear' | 'rain';
  siege: boolean;              // 攻城戰（守方在城內）
  defense: number;             // 城防
  attacker: BattleSide;
  defender: BattleSide;
  round: number;
  maxRounds: number;
  rounds: BattleRoundLog[];
  over: boolean;
  winner?: 'attacker' | 'defender';
  /** 特殊事件（如桶狹間） */
  special?: 'okehazama';
}

export interface LogEntry {
  turn: number;
  key: string;                 // i18n key
  params?: Record<string, string | number>;
  faction?: FactionId;
  important?: boolean;
}
