import type { GameState } from './types';

const PREFIX = 'xt.save.';
export const SLOTS = [1, 2, 3] as const;

export interface SaveMeta { slot: number; faction: string; year: number; month: number; savedAt: number }

export function saveGame(state: GameState, slot: number): void {
  localStorage.setItem(PREFIX + slot, JSON.stringify(state));
  const meta: SaveMeta = { slot, faction: state.player, year: state.year, month: state.month, savedAt: Date.now() };
  localStorage.setItem(PREFIX + slot + '.meta', JSON.stringify(meta));
}

export function loadGame(slot: number): GameState | null {
  const raw = localStorage.getItem(PREFIX + slot);
  if (!raw) return null;
  try {
    const s = JSON.parse(raw) as GameState;
    s.battleQueue ??= []; s.pendingEvents ??= [];
    return s;
  } catch { return null; }
}

export function saveMeta(slot: number): SaveMeta | null {
  const raw = localStorage.getItem(PREFIX + slot + '.meta');
  return raw ? JSON.parse(raw) as SaveMeta : null;
}

/** 自動存檔（每回合） */
export function autosave(state: GameState): void { saveGame(state, 0); }
export function loadAutosave(): GameState | null { return loadGame(0); }
