import type { FactionDef } from '../core/types';

export const FACTIONS: FactionDef[] = [
  // ===== 大勢力 =====
  { id: 'oda', name: '織田', nameEn: 'Oda', daimyo: 'oda_nobunaga', major: true, difficulty: 3,
    kamon: 'oda_mokko', color: 0xc0392b, init: { gold: 3000, princesses: 2, credit: 60 }, techs: [] },
  { id: 'imagawa', name: '今川', nameEn: 'Imagawa', daimyo: 'imagawa_yoshimoto', major: true, difficulty: 1,
    kamon: 'ashikaga_futatsubiki', color: 0x8e44ad, init: { gold: 7000, princesses: 2, credit: 70 }, techs: ['agri1'] },
  { id: 'takeda', name: '武田', nameEn: 'Takeda', daimyo: 'takeda_shingen', major: true, difficulty: 2,
    kamon: 'takeda_bishi', color: 0xd35400, init: { gold: 4000, princesses: 3, credit: 55 }, techs: ['mil1'] },
  { id: 'uesugi', name: '上杉', nameEn: 'Uesugi', daimyo: 'uesugi_kenshin', major: true, difficulty: 2,
    kamon: 'uesugi_take_ni_suzume', color: 0x2980b9, init: { gold: 4500, princesses: 1, credit: 90 }, techs: ['mil1'] },
  { id: 'hojo', name: '北條', nameEn: 'Hojo', daimyo: 'hojo_ujiyasu', major: true, difficulty: 2,
    kamon: 'hojo_mitsuuroko', color: 0xf1c40f, init: { gold: 6000, princesses: 3, credit: 75 }, techs: ['agri1', 'castle1'] },
  { id: 'mori', name: '毛利', nameEn: 'Mori', daimyo: 'mori_motonari', major: true, difficulty: 2,
    kamon: 'mori_ichimonji_mitsuboshi', color: 0x16a085, init: { gold: 6000, princesses: 2, credit: 65 }, techs: ['com1'] },
  { id: 'miyoshi', name: '三好', nameEn: 'Miyoshi', daimyo: 'miyoshi_nagayoshi', major: true, difficulty: 2,
    kamon: 'miyoshi_sangaibishi', color: 0x7f8c8d, init: { gold: 8000, princesses: 2, credit: 50 }, techs: ['com1'] },
  { id: 'chosokabe', name: '長宗我部', nameEn: 'Chosokabe', daimyo: 'chosokabe_motochika', major: true, difficulty: 4,
    kamon: 'chosokabe_katabami', color: 0x27ae60, init: { gold: 1500, princesses: 1, credit: 60 }, techs: [] },
  { id: 'shimazu', name: '島津', nameEn: 'Shimazu', daimyo: 'shimazu_takahisa', major: true, difficulty: 3,
    kamon: 'shimazu_juji', color: 0x2c3e50, init: { gold: 2500, princesses: 2, credit: 65 }, techs: ['mil1', 'mil2'] },
  { id: 'otomo', name: '大友', nameEn: 'Otomo', daimyo: 'otomo_sorin', major: true, difficulty: 2,
    kamon: 'otomo_gyoyo', color: 0xe67e22, init: { gold: 5500, princesses: 2, credit: 60 }, techs: ['com1'] },
  // ===== 小勢力 =====
  { id: 'ryuzoji', name: '龍造寺', nameEn: 'Ryuzoji', daimyo: 'ryuzoji_takanobu', major: false, difficulty: 3,
    kamon: 'ryuzoji_hiashi', color: 0xa93226, init: { gold: 1500, princesses: 1, credit: 50 }, techs: [] },
  { id: 'amago', name: '尼子', nameEn: 'Amago', daimyo: 'amago_haruhisa', major: false, difficulty: 3,
    kamon: 'amago_yotsumeyui', color: 0x5d6d7e, init: { gold: 3000, princesses: 1, credit: 55 }, techs: [] },
  { id: 'tsutsui', name: '筒井', nameEn: 'Tsutsui', daimyo: 'tsutsui_junkei', major: false, difficulty: 4,
    kamon: 'tsutsui_umebachi', color: 0x9b59b6, init: { gold: 1500, princesses: 0, credit: 55 }, techs: [] },
  { id: 'azai', name: '淺井', nameEn: 'Azai', daimyo: 'azai_nagamasa', major: false, difficulty: 3,
    kamon: 'azai_kikko', color: 0x1abc9c, init: { gold: 2000, princesses: 1, credit: 70 }, techs: [] },
  { id: 'asakura', name: '朝倉', nameEn: 'Asakura', daimyo: 'asakura_yoshikage', major: false, difficulty: 3,
    kamon: 'asakura_mokko', color: 0x6c3483, init: { gold: 3000, princesses: 1, credit: 60 }, techs: ['com1'] },
  { id: 'saito', name: '齋藤', nameEn: 'Saito', daimyo: 'saito_yoshitatsu', major: false, difficulty: 3,
    kamon: 'saito_tatsunami', color: 0x117a65, init: { gold: 2500, princesses: 1, credit: 45 }, techs: ['castle1'] },
  { id: 'kitabatake', name: '北畠', nameEn: 'Kitabatake', daimyo: 'kitabatake_tomonori', major: false, difficulty: 4,
    kamon: 'kitabatake_waribishi', color: 0xb9770e, init: { gold: 1500, princesses: 1, credit: 65 }, techs: [] },
  { id: 'date', name: '伊達', nameEn: 'Date', daimyo: 'date_harumune', major: false, difficulty: 3,
    kamon: 'date_mitsubiki', color: 0x1f618d, init: { gold: 2000, princesses: 1, credit: 60 }, techs: [] },
];

export const FACTION_MAP: Record<string, FactionDef> = Object.fromEntries(FACTIONS.map(f => [f.id, f]));
