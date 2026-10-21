import zhTW from './zh-TW';
import { FACTION_MAP } from '../data/factions';
import { REGION_MAP } from '../data/regions';
import { TECH_MAP } from '../data/techs';
import { OFFICER_MAP } from '../core/state';

export type Lang = 'zh-TW' | 'ja' | 'en';
export const LANGS: Lang[] = ['zh-TW', 'ja', 'en'];
export const LANG_NAMES: Record<Lang, string> = { 'zh-TW': '繁體中文', ja: '日本語', en: 'English' };

const dicts: Partial<Record<Lang, Record<string, string>>> = { 'zh-TW': zhTW };
let current: Lang = (localStorage.getItem('xt.lang') as Lang) || 'zh-TW';

/** 延遲載入其他語言 */
export async function setLang(lang: Lang): Promise<void> {
  if (!dicts[lang]) {
    if (lang === 'ja') dicts.ja = (await import('./ja')).default;
    if (lang === 'en') dicts.en = (await import('./en')).default;
  }
  current = lang;
  localStorage.setItem('xt.lang', lang);
}
export function getLang(): Lang { return current; }

/** 自動翻譯參數：勢力/區域/技術 id → 名稱 */
function translateParam(v: string | number, key: string): string {
  if (typeof v === 'number') return key === 'year' || key === 'month' ? String(v) : v.toLocaleString();
  if (FACTION_MAP[v]) return t(`faction.${v}`);
  if (REGION_MAP[v]) return t(`region.${v}`);
  if (TECH_MAP[v]) return t(`tech.${v}.name`);
  if (OFFICER_MAP[v]) return officerName(v);
  if (v.startsWith('tactic:')) return t(`tactic.${v.slice(7)}`);
  return v;
}

export function t(key: string, params?: Record<string, string | number>): string {
  const d = dicts[current] ?? zhTW;
  let s = d[key] ?? zhTW[key] ?? key;
  if (params) for (const [k, v] of Object.entries(params)) s = s.split(`{${k}}`).join(translateParam(v, k));
  return s;
}

export function officerName(id: string): string {
  const o = OFFICER_MAP[id];
  if (!o) return id;
  return current === 'en' ? o.nameEn : o.name;
}

export function factionName(id: string | null | undefined): string {
  return id ? t(`faction.${id}`) : t('faction.none');
}
