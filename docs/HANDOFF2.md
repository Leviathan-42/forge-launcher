# Forge Launcher — Agent Handoff #2

**Date:** 2026-05-23 (session 2)  
**Status:** Working. Games launch, downloads work, save sync works, perf stats work.  
**Stack:** Tauri 2 · Rust · Svelte 5 · Vite 6 · macOS Apple Silicon only  
**GitHub:** `https://github.com/Leviathan-42/forge-launcher` (public, `git pull` to update)

---

## How to run

```sh
cd "Gamehub clone"
npm install
npm run tauri dev
```

Requires:
- Rust, Node LTS, `@tauri-apps/cli`
- wine64 at `/opt/homebrew/bin/wine64`
- DepotDownloader at `/opt/homebrew/bin/DepotDownloader`
- Firefox with Steam login (for Steam Cloud save downloads)

---

## What changed since last handoff

### New files
| File | Purpose |
|---|---|
| `src-tauri/src/saves.rs` | Save sync system — recursive dir copy, SaveMapping struct, SyncDirection |
| `.gitignore` | Excludes target/, node_modules/, dist/, depots/ |

### Modified files
| File | Key changes |
|---|---|
| `src-tauri/Cargo.toml` | Added `nix` v0.29 (PTY support) |
| `src-tauri/src/main.rs` | Registered `saves` module; added 7 new commands (save sync, perf stats, mangohud detection, cloud saves); auto-sync on launch/exit |
| `src-tauri/src/config.rs` | Added `save_mappings` + `mangohud_enabled` to Game struct |
| `src-tauri/src/launcher.rs` | Added `pid()`, `mangohud_enabled` to LaunchOptions; MangoHud env vars; `WINE_MOUSE_WARP=1`; `user32=n,b` override |
| `src-tauri/src/downloader.rs` | Rewrote DD runner to use `forkpty()` (PTY-based, captures ANSI progress bars) |
| `src-tauri/tauri.conf.json` | Fixed CSP: added `http://asset.localhost` (was only `https://`) |
| `src/lib/types/index.ts` | Added `SaveMapping`, `ProcessStats` interfaces; `save_mappings` + `mangohud_enabled` on Game |
| `src/lib/stores/games.ts` | Added `liveStats` store; expanded polling to fetch per-game process stats |
| `src/App.svelte` | Added save sync UI, performance stats panel, quick toggles (Metal HUD/ESYNC/MangoHud), Steam Cloud buttons |
| `src/lib/components/GameDownload.svelte` | Initializes `save_mappings: []` + `mangohud_enabled: false` |
| `src/lib/components/SteamImport.svelte` | Same |

---

## New features summary

### 1. Save file sync (`saves.rs`)
Per-game configurable save path pairs. Auto-syncs before launch and after exit:
- **Before launch**: copies saves FROM macOS backup → INTO Wine prefix
- **After exit**: copies saves FROM Wine prefix → BACK to macOS backup
- `SaveMapping` = `{source: "~/Documents/Game Saves/", target: "~/Wine/Bottles/default/..."}`
- `SyncDirection::ToPrefix` / `FromPrefix`
- Recursive copy with symlink support, `~` path expansion

### 2. Performance monitoring
- `process_stats(gameId)` → `{pid, rss_mb, vsz_mb, cpu_percent, elapsed_secs, fps_hint}` (uses macOS `ps` command)
- `check_mangohud()` → detects MangoHud installation paths
- Frontend polls stats every 3s via `liveStats` store (Map<gameId, ProcessStats>)
- Detail panel shows live: Runtime, RAM (RSS MB), CPU%, VM Size while game runs

### 3. MangoHud support
- `mangohud_enabled: bool` on Game
- Sets `MANGOHUD=1` + `MANGOHUD_CONFIG=fps,frametime,cpu_load,gpu_load,ram,vram...`
- Only works with DXVK+MoltenVK; D3DMetal uses MTL_HUD_ENABLED instead
- Requires `brew install mangohud`

### 4. Steam Cloud save bridge
- `steam_cloud_url(appId)` → returns browser URL for Steam cloud page
- `download_steam_cloud_saves(appId, targetDir)` → reads `steamLoginSecure` cookie from Firefox cookies.sqlite, fetches all cloud save files via curl, saves to target directory
- UI button "Download All Cloud Saves" (auto-syncs to game directory after download)

### 5. PTY-based DepotDownloader progress
- Replaced piped stderr with `forkpty()` from `nix` crate
- DepotDownloader sees a real TTY → emits ANSI escape code progress bars
- Download UI now shows accurate real-time X.XX% progress (not just "Connecting…")

### 6. Wine compatibility fixes
- `WINE_MOUSE_WARP=1` — helps cursor capture in shooters
- `user32=n,b` — WINEDLLOVERRIDES fix for missing functions (e.g., IsMouseInPointerEnabled)
- CSP fix: `http://asset.localhost` added (cover art now loads correctly)

---

## Complete Tauri command list (updated)

| Command | Args | Returns | Notes |
|---|---|---|---|
| `load_games` | — | `Game[]` | |
| `save_games` | `games: Game[]` | `void` | |
| `upsert_game` | `game: Game` | `Game[]` | Auto-fetches Steam cover art if missing |
| `remove_game` | `id: string` | `Game[]` | |
| `launch_game` | `gameId: string` | `void` | **Now auto-syncs saves before launch** |
| `kill_game` | `gameId: string` | `void` | |
| `running_games` | — | `string[]` | **Now auto-syncs saves after exit + updates playtime** |
| `create_prefix` | `prefixPath: string` | `void` | |
| `load_config` | — | `AppConfig` | |
| `save_config` | `cfg: AppConfig` | `void` | |
| `scan_steam_games` | — | `SteamGame[]` | |
| `launch_steam_game` | `appId: number` | `void` | |
| `launch_steam_game_direct` | `appId, prefixPath` | `void` | |
| `check_wine` | — | `{installed, path, gptk_lib, message}` | |
| `check_download_tools` | — | `ToolStatus` | |
| `check_steam_credentials` | `username: string` | `boolean` | |
| `get_cached_steam_username` | — | `string \| null` | |
| `authenticate_steam` | `username: string` | `void` | |
| `download_steam_game` | `request: DownloadRequest` | `void` | **Now uses PTY for real progress** |
| `cancel_download` | `appId: number` | `void` | |
| `validate_game_files` | `appId, username, installDir, backend` | `void` | |
| **`sync_game_saves`** ✨ | `gameId, direction` | `number` | `direction`: "to_prefix" or "from_prefix". Returns files copied. |
| **`guess_wine_username`** ✨ | `prefixPath` | `string` | Lists drive_c/users/ to find Wine username |
| **`process_stats`** ✨ | `gameId` | `ProcessStats` | RSS, VSZ, CPU% via `ps` command |
| **`check_mangohud`** ✨ | — | `{installed, path}` | Detects MangoHud installation |
| **`steam_cloud_url`** ✨ | `appId` | `string` | Returns browser URL for Steam Cloud page |
| **`download_steam_cloud_saves`** ✨ | `appId, targetDir` | `string` | Bulk downloads from Steam Cloud using Firefox cookie |

---

## Current data types

```typescript
interface SaveMapping {
  source: string;    // macOS dir where saves are stored
  target: string;    // path inside Wine prefix
}

interface ProcessStats {
  pid: number;
  rss_mb: number;        // physical RAM
  vsz_mb: number;        // virtual memory
  cpu_percent: number;
  elapsed_secs: number;
  fps_hint: string | null;
}

interface Game {
  id: string;
  name: string;
  exe_path: string;
  working_dir: string | null;
  cover_art: string | null;
  wine_prefix: string | null;
  extra_args: string[];
  translation_backend: "d3dmetal" | "dxvk" | "none";
  show_hud: boolean;
  esync: boolean;
  msync: boolean;
  advertise_avx: boolean;
  enable_dxr: boolean;
  source: "manual" | "steam";
  steam_app_id: number | null;
  notes: string;
  playtime_secs: number;
  save_mappings: SaveMapping[];         // ✨ NEW
  mangohud_enabled: boolean;            // ✨ NEW
}

interface AppConfig {
  wine64_path: string;
  gptk_lib_path: string;
  default_prefix: string;
  suppress_wine_debug: boolean;
  theme: "dark" | "light" | "system";
  global_hud: boolean;
  metalfx_enabled: boolean;
}
```

---

## Wine launch env vars (current)

```
WINEPREFIX          = expanded prefix path
DYLD_LIBRARY_PATH   = gptk_lib_path:gptk_lib_path/external:<existing>
WINEDEBUG           = fixme-all (or "")
GST_DEBUG           = 1
MTL_HUD_ENABLED     = 1 or 0
WINE_MOUSE_WARP     = 1                            ← NEW
WINEESYNC           = 1 if esync OR msync
WINEMSYNC           = 1 if msync
WINEDLLOVERRIDES    = "dxgi,d3d9,d3d10core,d3d11,user32=n,b" (DXVK)
                      "user32=n,b" (D3DMetal)      ← NEW separate user32
DXVK_ASYNC          = 1 if DXVK
D3DM_SUPPORT_DXR    = 1 if enable_dxr
D3DM_ENABLE_METALFX = 1 if metalfx_enabled
ROSETTA_ADVERTISE_AVX = 1 if advertise_avx
MANGOHUD            = 1 if mangohud_enabled        ← NEW
MANGOHUD_CONFIG     = fps,frametime,cpu_load,...    ← NEW
```

---

## ULTRAKILL specifics (AppID 1229490)

- **Installed at:** `~/Games/1229490/` (ULTRAKILL.exe exists, exe_path now set)
- **Saves stored in game directory** (not AppData): `~/Games/1229490/Saves/Slot1/`
- **Save mapping already configured** → syncs with `~/Documents/ULTRAKILL Saves/GameInstall/`
- **Steam Cloud:** 49 `.bepis` files across 3 save slots + Prefs.json — on Steam servers, ready to download
- **Download saves from Steam Cloud:** click "Download All Cloud Saves" button in ULTRAKILL detail panel (uses Firefox steamLoginSecure cookie)

---

## Known issues / what's not done yet

| Issue | Notes |
|---|---|
| No per-game Wine prefix UI picker | `wine_prefix` field exists, no Browse button |
| No search/filter in library grid | |
| `advertise_avx` / `enable_dxr` no UI toggle | Fields exist in Rust, wired to env vars, no UI |
| `metal_trace` hardcoded to false | LaunchOptions has it but no toggle |
| DXVK HUD level not exposed in UI | `DxvkHud` enum exists (Off/Fps/Partial/Full) |
| Cover art won't retry if offline fetch fails | |
| MangoHud requires DXVK+MoltenVK | Won't work with D3DMetal (use MTL_HUD_ENABLED for Metal games) |
| `download_steam_cloud_saves` needs Firefox login | Reads cookie from Firefox's cookies.sqlite |
| No `.exe` auto-detection for ULTRAKILL | exe_path was blank initially — now set manually |

---

## Environment (this machine)

```
macOS: Apple Silicon (M-series)
wine64: /opt/homebrew/bin/wine64 (wine-7.7 GPTK 1.1)
DepotDownloader: /opt/homebrew/bin/DepotDownloader v3.4.0
Firefox Steam login: little__leviathan (steamLoginSecure cookie present)
Steam user ID: 76561199048601059 / accountid: 1088335331
Wine prefix: ~/Wine/Bottles/default
Games installed: Storebound (3417410), ULTRAKILL (1229490)
```

---

## Quick reference: adding a new Tauri command

```rust
// Rust (src-tauri/src/main.rs):
#[tauri::command]
async fn my_command(arg: String) -> Result<String, String> {
    Ok(format!("got: {}", arg))
}
// Register in .invoke_handler(tauri::generate_handler![..., my_command])
```

```typescript
// TypeScript:
import { invoke } from "@tauri-apps/api/core";
const result = await invoke<string>("my_command", { arg: "hello" });
```

Rules: Return `Result<T, String>`, args match snake_case exactly, add to `docs/API.md`.