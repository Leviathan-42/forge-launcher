/**
 * stores/games.ts
 *
 * Svelte stores for the game library.
 *
 * Architecture note:
 * All mutation goes through the exported action functions (loadGames,
 * upsertGame, etc.) which call the Tauri Rust backend and then update the
 * store.  Components must never write to the store directly — they call the
 * action and let the store react.
 *
 *  Component → action fn → Tauri invoke → Rust → JSON → store update → UI
 */

import { writable, derived, get } from "svelte/store";
import { invoke }                  from "@tauri-apps/api/core";
import type { Game, ProcessStats } from "../types";

// ---------------------------------------------------------------------------
// Raw stores
// ---------------------------------------------------------------------------

/** The full, ordered game library. */
export const games = writable<Game[]>([]);

/** IDs of games whose child processes are currently running. */
export const runningGameIds = writable<Set<string>>(new Set());

/** The game currently selected / shown in the detail panel. */
export const selectedGameId = writable<string | null>(null);

/** True while any load/save operation is in flight. */
export const libraryLoading = writable<boolean>(false);

/**
 * Live performance stats (RAM, CPU%, elapsed time) for all running games,
 * keyed by game UUID.  Populated by the fast stats poll loop.
 */
export const liveStats = writable<Map<string, ProcessStats>>(new Map());

// ---------------------------------------------------------------------------
// Derived stores (computed, read-only)
// ---------------------------------------------------------------------------

/** The full Game object for the currently selected game. */
export const selectedGame = derived(
  [games, selectedGameId],
  ([$games, $id]) => $games.find((g) => g.id === $id) ?? null
);

/** Games that are currently running. */
export const runningGames = derived(
  [games, runningGameIds],
  ([$games, $ids]) => $games.filter((g) => $ids.has(g.id))
);

/** Games grouped by first letter of name, for sidebar indexing. */
export const gamesByLetter = derived(games, ($games) => {
  const map = new Map<string, Game[]>();
  for (const game of $games) {
    const letter = game.name[0]?.toUpperCase() ?? "#";
    if (!map.has(letter)) map.set(letter, []);
    map.get(letter)!.push(game);
  }
  return map;
});

// ---------------------------------------------------------------------------
// Actions — all async, return the updated list or throw
// ---------------------------------------------------------------------------

/** Fetch the game library from disk and populate the store. */
export async function loadGames(): Promise<void> {
  libraryLoading.set(true);
  try {
    const list = await invoke<Game[]>("load_games");
    games.set(list);
  } finally {
    libraryLoading.set(false);
  }
}

/** Persist the full library to disk (rarely needed directly; prefer upsert). */
export async function saveGames(list: Game[]): Promise<void> {
  await invoke<void>("save_games", { games: list });
  games.set(list);
}

/** Insert or update a game. Returns the updated library. */
export async function upsertGame(game: Game): Promise<Game[]> {
  const updated = await invoke<Game[]>("upsert_game", { game });
  games.set(updated);
  return updated;
}

/** Remove a game by UUID. Returns the updated library. */
export async function removeGame(id: string): Promise<Game[]> {
  const updated = await invoke<Game[]>("remove_game", { id });
  games.set(updated);
  // Deselect if we just removed the selected game
  if (get(selectedGameId) === id) selectedGameId.set(null);
  return updated;
}

// ---------------------------------------------------------------------------
// Running state polling
// ---------------------------------------------------------------------------

let pollInterval: ReturnType<typeof setInterval> | null = null;

/**
 * Start polling the backend every `intervalMs` ms to sync which games are
 * running.  Call stopPolling() when the window is destroyed.
 */
export function startPolling(intervalMs = 3000): void {
  if (pollInterval !== null) return; // already running
  pollInterval = setInterval(async () => {
    try {
      const ids = await invoke<string[]>("running_games");
      const idSet = new Set(ids);
      runningGameIds.set(idSet);

      // Fetch live stats for each running game (fast, 1 poll per game)
      const statsMap = new Map<string, ProcessStats>();
      const fetches = ids.map(async (id) => {
        try {
          const stats = await invoke<ProcessStats>("process_stats", { gameId: id });
          statsMap.set(id, stats);
        } catch {
          // Game may have just exited; ignore
        }
      });
      await Promise.all(fetches);
      liveStats.set(statsMap);
    } catch {
      // Silently ignore — backend may be temporarily unavailable
    }
  }, intervalMs);
}

export function stopPolling(): void {
  if (pollInterval !== null) {
    clearInterval(pollInterval);
    pollInterval = null;
  }
  liveStats.set(new Map());
}
