import { invoke } from "@tauri-apps/api/core";
import { open } from "@tauri-apps/plugin-dialog";
import type {
  AppConfig,
  Bottle,
  BottleApp,
  Game,
  GraphicsBackend,
  WineStatus,
} from "$lib/types";

const previewHome = "~";
const mockPrefix = `${previewHome}/Wine/Bottles/default`;
const previewRuntimeProfileId = "wine-vulkan";
const previewGraphicsBackend: GraphicsBackend = "dxvk_vkd3d";

function bottleSlug(name: string) {
  return name.trim().toLowerCase().replace(/\s+/g, "-") || "bottle";
}

function hasTauri() {
  return typeof window !== "undefined" && "__TAURI_INTERNALS__" in window;
}

export function canUseDesktopCommands() {
  return hasTauri();
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
        runtime_profile_id: previewRuntimeProfileId,
        graphics_backend: previewGraphicsBackend,
        env_overrides: {},
        app_count: 0,
      },
    ],
  );
}

export async function createBottle(name: string, prefixPath?: string) {
  const slug = bottleSlug(name);
  return command<Bottle[]>("create_bottle", { name, prefixPath }, [
    {
      id: `${slug}-preview`,
      name,
      prefix_path: prefixPath || `${previewHome}/Wine/Bottles/${slug}`,
      exists: true,
      steam_installed: false,
      runtime_profile_id: previewRuntimeProfileId,
      graphics_backend: previewGraphicsBackend,
      env_overrides: {},
      app_count: 0,
    },
  ]);
}

export async function updateBottleRuntime(
  prefixPath: string,
  runtimeProfileId: string,
  graphicsBackend: GraphicsBackend | null,
  envOverrides: Record<string, string> = {},
  force = false,
) {
  return command<Bottle[]>("update_bottle_runtime", {
    prefixPath,
    runtimeProfileId,
    graphicsBackend,
    envOverrides,
    force,
  });
}

export async function listBottleApps(prefixPath: string) {
  return command<BottleApp[]>("list_bottle_apps", { prefixPath }, []);
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
      gptk_lib_path: "",
      default_prefix: mockPrefix,
      suppress_wine_debug: true,
      theme: "system",
      global_hud: false,
      metalfx_enabled: false,
      env: {},
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

export async function upsertGame(game: Game) {
  return command<Game[]>("upsert_game", { game }, [game]);
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
