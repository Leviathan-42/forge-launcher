import { invoke } from "@tauri-apps/api/core";
import { open } from "@tauri-apps/plugin-dialog";
import type {
  AppConfig,
  Bottle,
  BottleApp,
  Game,
  LauncherStatus,
  WineStatus,
} from "$lib/types";

const mockPrefix = `${homeHint()}/Wine/Bottles/default`;

function homeHint() {
  return "/Users/levi";
}

function hasTauri() {
  return typeof window !== "undefined" && "__TAURI_INTERNALS__" in window;
}

async function command<T>(name: string, args?: Record<string, unknown>, fallback?: T): Promise<T> {
  if (!hasTauri()) {
    if (fallback !== undefined) return fallback;
    throw new Error(`Tauri command "${name}" is only available in the desktop app.`);
  }

  return invoke<T>(name, args);
}

export async function listBottles() {
  return command<Bottle[]>(
    "list_bottles",
    undefined,
    [
      {
        id: "default-preview",
        name: "Default",
        prefix_path: mockPrefix,
        exists: false,
        steam_installed: false,
        app_count: 0,
      },
    ],
  );
}

export async function createBottle(name: string, prefixPath?: string) {
  return command<Bottle[]>("create_bottle", { name, prefixPath }, [
    {
      id: `${name.toLowerCase().replace(/\s+/g, "-")}-preview`,
      name,
      prefix_path: prefixPath || `${homeHint()}/Wine/Bottles/${name.toLowerCase().replace(/\s+/g, "-")}`,
      exists: true,
      steam_installed: false,
      app_count: 0,
    },
  ]);
}

export async function launcherStatus(prefixPath: string) {
  return command<LauncherStatus>(
    "bottle_launcher_status",
    { prefixPath },
    {
      prefix_path: prefixPath,
      prefix_exists: false,
      steam_installed: false,
      steam_path: null,
    },
  );
}

export async function listBottleApps(prefixPath: string) {
  return command<BottleApp[]>("list_bottle_apps", { prefixPath }, []);
}

export async function installSteam(prefixPath: string) {
  return command<void>("install_steam_in_prefix", { prefixPath });
}

export async function openSteam(prefixPath: string) {
  return command<void>("open_steam_in_prefix", { prefixPath });
}

export async function repairSteam(prefixPath: string) {
  return command<void>("repair_steam_in_prefix", { prefixPath });
}

export async function runExe(prefixPath: string, exePath: string, args: string[] = []) {
  return command<void>("run_exe_in_prefix", { prefixPath, exePath, args });
}

export async function loadConfig() {
  return command<AppConfig>(
    "load_config",
    undefined,
    {
      wine64_path: "/opt/homebrew/bin/wine64",
      gptk_lib_path: "/opt/homebrew/lib/external",
      default_prefix: mockPrefix,
      suppress_wine_debug: true,
      theme: "system",
      global_hud: false,
      metalfx_enabled: false,
    },
  );
}

export async function saveConfig(cfg: AppConfig) {
  return command<void>("save_config", { cfg });
}

export async function checkWine() {
  return command<WineStatus>(
    "check_wine",
    undefined,
    {
      installed: false,
      path: null,
      gptk_lib: null,
      message: "Preview mode. Open the Tauri app to detect Wine.",
    },
  );
}

export async function loadGames() {
  return command<Game[]>("load_games", undefined, []);
}

export async function pickExe() {
  if (!hasTauri()) return null;
  const picked = await open({
    multiple: false,
    directory: false,
    filters: [{ name: "Windows executable", extensions: ["exe"] }],
  });

  return typeof picked === "string" ? picked : null;
}

export async function pickFolder() {
  if (!hasTauri()) return null;
  const picked = await open({
    multiple: false,
    directory: true,
  });

  return typeof picked === "string" ? picked : null;
}
