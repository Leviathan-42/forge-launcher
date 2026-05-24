/**
 * stores/launcher.ts
 *
 * Actions for launching and killing games, plus a notification queue used by
 * the toast component.
 *
 * Launch flow:
 *
 *   1. UI calls launchGame(gameId)
 *   2. runningGameIds is updated optimistically
 *   3. invoke("launch_game") fires the Rust backend
 *   4. If it rejects, runningGameIds is rolled back and an error toast fires
 *   5. The polling loop in games.ts keeps runningGameIds accurate thereafter
 */

import { get }      from "svelte/store";
import { writable } from "svelte/store";
import { invoke }   from "@tauri-apps/api/core";
import type { Notification } from "../types";

function uuid(): string {
  return "xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx".replace(/[xy]/g, (c) => {
    const r = (Math.random() * 16) | 0;
    return (c === "x" ? r : (r & 0x3) | 0x8).toString(16);
  });
}
import { runningGameIds }    from "./games";

// ---------------------------------------------------------------------------
// Notification store
// ---------------------------------------------------------------------------

export const notifications = writable<Notification[]>([]);

/** Push a toast notification. Auto-dismissed after `duration` ms if > 0. */
export function notify(
  type: Notification["type"],
  message: string,
  duration = 4000
): void {
  const id = uuid();
  notifications.update((n) => [...n, { id, type, message, duration }]);
  if (duration > 0) {
    setTimeout(() => dismiss(id), duration);
  }
}

/** Remove a notification by id. */
export function dismiss(id: string): void {
  notifications.update((n) => n.filter((t) => t.id !== id));
}

// ---------------------------------------------------------------------------
// Launch / kill actions
// ---------------------------------------------------------------------------

/** Launch a game by UUID through GPTK / Wine / Rosetta 2. */
export async function launchGame(gameId: string): Promise<void> {
  // Optimistic update — shows the "running" badge immediately
  runningGameIds.update((ids) => {
    const next = new Set(ids);
    next.add(gameId);
    return next;
  });

  try {
    await invoke<void>("launch_game", { gameId });
    notify("success", "Game launched successfully");
  } catch (err) {
    // Roll back optimistic update
    runningGameIds.update((ids) => {
      const next = new Set(ids);
      next.delete(gameId);
      return next;
    });
    notify("error", `Launch failed: ${err}`);
    throw err;
  }
}

/** Kill a running game by UUID. */
export async function killGame(gameId: string): Promise<void> {
  try {
    await invoke<void>("kill_game", { gameId });
    runningGameIds.update((ids) => {
      const next = new Set(ids);
      next.delete(gameId);
      return next;
    });
    notify("info", "Game process terminated");
  } catch (err) {
    notify("error", `Could not kill process: ${err}`);
    throw err;
  }
}

// ---------------------------------------------------------------------------
// Wine prefix management
// ---------------------------------------------------------------------------

export const prefixCreating = writable<boolean>(false);

/** Create a new Wine prefix at the given path. */
export async function createPrefix(prefixPath: string): Promise<void> {
  prefixCreating.set(true);
  try {
    await invoke<void>("create_prefix", { prefixPath });
    notify("success", `Prefix created at ${prefixPath}`);
  } catch (err) {
    notify("error", `Prefix creation failed: ${err}`);
    throw err;
  } finally {
    prefixCreating.set(false);
  }
}

// ---------------------------------------------------------------------------
// Steam launch helpers
// ---------------------------------------------------------------------------

/** Launch a Steam game via the steam:// URI scheme (recommended). */
export async function launchSteamGame(appId: number): Promise<void> {
  try {
    await invoke<void>("launch_steam_game", { appId });
    notify("info", `Launched Steam AppID ${appId}`);
  } catch (err) {
    notify("error", `Steam launch failed: ${err}`);
    throw err;
  }
}

/**
 * Launch a Steam game directly through GPTK/Wine, bypassing the Steam client.
 * Requires the game's Wine prefix path.
 */
export async function launchSteamGameDirect(
  appId: number,
  prefixPath: string
): Promise<void> {
  runningGameIds.update((ids) => new Set([...ids, String(appId)]));

  try {
    await invoke<void>("launch_steam_game_direct", { appId, prefixPath });
    notify("success", `Game ${appId} launched directly`);
  } catch (err) {
    runningGameIds.update((ids) => {
      const next = new Set(ids);
      next.delete(String(appId));
      return next;
    });
    notify("error", `Direct launch failed: ${err}`);
    throw err;
  }
}
