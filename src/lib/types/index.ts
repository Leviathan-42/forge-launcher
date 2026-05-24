/**
 * types/index.ts
 *
 * Shared TypeScript types that mirror the Rust structs in config.rs and
 * steam.rs. Keep these in sync whenever you update the Rust side.
 */

// ---------------------------------------------------------------------------
// Game library
// ---------------------------------------------------------------------------

/** Which D3D translation backend the game should use. */
export type TranslationBackend = "d3dmetal" | "dxvk" | "none";

/** Where the game entry originated. */
export type GameSource = "manual" | "steam";

/** A save file mapping — pairs a macOS save location with its Wine-prefix location. */
export interface SaveMapping {
  /** macOS directory where saves are stored / backed up. */
  source: string;
  /** Absolute path inside the Wine prefix where the game writes saves. */
  target: string;
}

/** Live performance stats for a running game process. */
export interface ProcessStats {
  /** Process ID. */
  pid: number;
  /** Resident Set Size in MB (physical RAM currently used). */
  rss_mb: number;
  /** Virtual memory size in MB (address space allocated). */
  vsz_mb: number;
  /** CPU usage as a percentage (100 = one full core). */
  cpu_percent: number;
  /** Seconds since the game process was spawned. */
  elapsed_secs: number;
  /** FPS hint from Metal HUD (if available). */
  fps_hint: string | null;
}

/** A single game in the user's library — mirrors `config::Game` in Rust. */
export interface Game {
  /** UUID v4 — stable primary key. */
  id: string;
  /** Human-readable display name. */
  name: string;
  /** Absolute macOS path to the Windows .exe. */
  exe_path: string;
  /** Working directory passed to Wine. Null = exe parent dir. */
  working_dir: string | null;
  /** Optional cover art path (PNG/JPG). */
  cover_art: string | null;
  /** Wine prefix path. Null = use AppConfig.default_prefix. */
  wine_prefix: string | null;
  /** Extra CLI args forwarded after the .exe path. */
  extra_args: string[];
  /** D3D translation backend. */
  translation_backend: TranslationBackend;
  /** Show the Metal Performance Shader HUD overlay. */
  show_hud: boolean;
  /** Enable WINEESYNC (eventfd threading). */
  esync: boolean;
  /** Enable WINEMSYNC (mach-port sync, macOS-specific). */
  msync: boolean;
  /** Advertise AVX via Rosetta (macOS 15+ Sequoia). */
  advertise_avx: boolean;
  /** Enable DXR via D3DMetal (M3 Macs only). */
  enable_dxr: boolean;
  /** Origin of this library entry. */
  source: GameSource;
  /** Steam AppID when source === "steam". */
  steam_app_id: number | null;
  /** Freeform user notes. */
  notes: string;
  /** Total seconds of recorded playtime. */
  playtime_secs: number;
  /** Save file mappings — synced before launch and after exit. */
  save_mappings: SaveMapping[];
  /** Enable MangoHud (FPS, CPU, GPU, RAM overlay) — requires DXVK + MoltenVK. */
  mangohud_enabled: boolean;
}

// ---------------------------------------------------------------------------
// App configuration
// ---------------------------------------------------------------------------

/** Global launcher settings — mirrors `config::AppConfig` in Rust. */
export interface AppConfig {
  /** Absolute path to the wine64 binary (GPTK/Homebrew). */
  wine64_path: string;
  /** GPTK external libs directory (D3DMetal, libd3dshared). */
  gptk_lib_path: string;
  /** Default Wine prefix path used when a game has none set. */
  default_prefix: string;
  /** Suppress Wine debug output (WINEDEBUG=-all). */
  suppress_wine_debug: boolean;
  /** UI theme: "dark" | "light" | "system". */
  theme: string;
  /** Show the Metal HUD for all games globally. */
  global_hud: boolean;
  /** Enable MetalFX upscaling (GPTK 3.0+). */
  metalfx_enabled: boolean;
}

// ---------------------------------------------------------------------------
// Steam integration
// ---------------------------------------------------------------------------

/** A Steam game detected in the local library — mirrors `steam::SteamGame`. */
export interface SteamGame {
  /** Steam numeric application identifier. */
  app_id: number;
  /** Game display name from ACF manifest. */
  name: string;
  /** Absolute path to the install directory. */
  install_dir: string;
  /** Absolute path to the primary .exe (best-effort). */
  exe_path: string;
  /** Raw `oslist` value from the manifest. */
  os_list: string;
  /** Size on disk in bytes. */
  size_on_disk: number;
}

// ---------------------------------------------------------------------------
// UI-only helpers
// ---------------------------------------------------------------------------

/** Notification / toast message shown in the UI. */
export interface Notification {
  id: string;
  type: "info" | "success" | "warning" | "error";
  message: string;
  /** Auto-dismiss after this many ms. 0 = persist until dismissed. */
  duration: number;
}
