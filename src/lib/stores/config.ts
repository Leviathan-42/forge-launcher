/**
 * stores/config.ts
 *
 * Global launcher configuration store.
 * Mirrors AppConfig in src-tauri/src/config.rs.
 */

import { writable } from "svelte/store";
import { invoke }   from "@tauri-apps/api/core";
import type { AppConfig } from "../types";

// ---------------------------------------------------------------------------
// Default values (match Rust defaults in config.rs)
// ---------------------------------------------------------------------------

const DEFAULT_CONFIG: AppConfig = {
  wine64_path:         "/usr/local/bin/wine64",
  gptk_lib_path:       "/usr/local/lib/external",
  // Rust config.rs expands ~ to the real home path on load.
  // This JS-side default is only used for the settings UI placeholder
  // before the first load_config() call resolves.
  default_prefix: "~/Wine/Bottles/default",
  suppress_wine_debug: true,
  theme:               "system",
  global_hud:          false,
  metalfx_enabled:     false,
};

// ---------------------------------------------------------------------------
// Store
// ---------------------------------------------------------------------------

export const appConfig    = writable<AppConfig>(DEFAULT_CONFIG);
export const configLoaded = writable<boolean>(false);

// ---------------------------------------------------------------------------
// Actions
// ---------------------------------------------------------------------------

/** Load config from disk, falling back to defaults on first run. */
export async function loadConfig(): Promise<void> {
  const cfg = await invoke<AppConfig>("load_config");
  appConfig.set(cfg);
  configLoaded.set(true);
}

/** Persist changed config to disk. */
export async function saveConfig(cfg: AppConfig): Promise<void> {
  await invoke<void>("save_config", { cfg });
  appConfig.set(cfg);
}

// ---------------------------------------------------------------------------
// Steam store
// ---------------------------------------------------------------------------

import type { SteamGame } from "../types";

export const steamGames        = writable<SteamGame[]>([]);
export const steamScanLoading  = writable<boolean>(false);

/** Scan the local Steam library and populate the steamGames store. */
export async function scanSteamGames(): Promise<void> {
  steamScanLoading.set(true);
  try {
    const list = await invoke<SteamGame[]>("scan_steam_games");
    steamGames.set(list);
  } finally {
    steamScanLoading.set(false);
  }
}
