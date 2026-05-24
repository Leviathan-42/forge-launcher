# Forge Launcher — Agent Handoff Document

**Date:** 2026-05-23  
**Status:** Working. Games launch. Downloads work. Cover art shows.  
**Stack:** Tauri 2 · Rust · Svelte 5 · Vite 6 · macOS Apple Silicon only

---

## How to run

```sh
cd "Gamehub clone"
npm install          # already done, node_modules present
npm run tauri dev    # starts Vite HMR + Rust backend
```

Requires:
- Rust (rustup), Node LTS, `@tauri-apps/cli` (in devDeps)
- wine64 at `/opt/homebrew/bin/wine64` — installed via `brew install --cask gcenx/wine/game-porting-toolkit`
- DepotDownloader at `/opt/homebrew/bin/DepotDownloader` — installed via `brew tap steamre/tools && brew install depotdownloader`

---

## Project layout

```
Gamehub clone/
├── src/                          Svelte frontend
│   ├── main.ts                   App entry point
│   ├── App.svelte                Root: sidebar, library grid, detail panel, settings
│   └── lib/
│       ├── types/index.ts        TypeScript interfaces (mirrors Rust structs exactly)
│       ├── stores/
│       │   ├── index.ts          Re-exports everything
│       │   ├── games.ts          Library CRUD + 3s polling loop for running state
│       │   ├── launcher.ts       launchGame/killGame actions + toast queue
│       │   └── config.ts         AppConfig store + Steam scan
│       └── components/
│           ├── GameCard.svelte   Tile: cover art, delete btn, setup-needed state
│           ├── GameDownload.svelte  Two-phase Steam download UI
│           ├── SteamImport.svelte   Scan already-installed Steam games
│           └── Toast.svelte      Fixed-position notification renderer
│
├── src-tauri/
│   ├── build.rs                  REQUIRED — runs tauri-build (sets OUT_DIR)
│   ├── Cargo.toml                deps: tauri 2, serde, serde_json, flate2, tauri-plugin-dialog
│   ├── tauri.conf.json           Window config, CSP, bundle settings
│   ├── entitlements.plist        App sandbox DISABLED (required for Wine spawning)
│   ├── capabilities/main.json   core:* + dialog:allow-open permissions
│   └── src/
│       ├── main.rs               All Tauri command registrations + entry point
│       ├── config.rs             Game/AppConfig structs, JSON persistence, wine64 auto-detection
│       ├── launcher.rs           Wine process spawning, prefix auto-creation, env vars
│       ├── steam.rs              ACF manifest parser, Steam library scanner
│       └── downloader.rs         DepotDownloader/SteamCMD integration, credential detection
│
├── docs/                         Documentation
│   ├── HANDOFF.md                This file
│   ├── ARCHITECTURE.md           System design, IPC diagram, data flow
│   ├── SETUP.md                  Installation guide
│   ├── STEAM.md                  Steam integration details
│   ├── API.md                    Tauri command reference
│   ├── ENV_VARS.md               Wine/GPTK environment variable reference
│   └── PROJECT_LAYOUT.md         Annotated file tree
│
├── config/games.json             Sample/reference games.json (not the live one)
├── app-icon.png                  1024x1024 source icon
├── package.json
├── vite.config.ts
├── svelte.config.js
└── tsconfig.json
```

**Live data** (not in project dir):
```
~/Library/Application Support/com.forgelauncher.app/
  config.json       Global settings (wine64 path, GPTK path, default prefix)
  games.json        User's game library
  covers/           Steam cover art JPEGs (fetched automatically)
```

---

## Tauri commands — complete list

All registered in `src-tauri/src/main.rs` via `tauri::generate_handler![]`.

| Command | Args | Returns | Notes |
|---|---|---|---|
| `load_games` | — | `Game[]` | Reads `games.json` |
| `save_games` | `games: Game[]` | `void` | Overwrites `games.json` |
| `upsert_game` | `game: Game` | `Game[]` | Insert or update by `id`; auto-fetches Steam cover art |
| `remove_game` | `id: string` | `Game[]` | Remove by UUID |
| `launch_game` | `gameId: string` | `void` | Spawns `wine64 start /unix <exe>`; auto-creates prefix if missing |
| `kill_game` | `gameId: string` | `void` | SIGKILL the process |
| `running_games` | — | `string[]` | Polled every 3s; reaps finished processes; writes playtime |
| `create_prefix` | `prefixPath: string` | `void` | `wineboot --init` |
| `load_config` | — | `AppConfig` | Auto-saves on first run with detected paths |
| `save_config` | `cfg: AppConfig` | `void` | |
| `scan_steam_games` | — | `SteamGame[]` | Reads ACF manifests from `~/Library/.../Steam/steamapps/` |
| `launch_steam_game` | `appId: number` | `void` | Opens `steam://rungameid/<id>` via `open -a Steam` |
| `launch_steam_game_direct` | `appId, prefixPath` | `void` | Launches through Wine, bypassing Steam client |
| `check_wine` | — | `{installed, path, gptk_lib, message}` | Scans known locations for wine64 |
| `check_download_tools` | — | `ToolStatus` | Detects DepotDownloader + SteamCMD |
| `check_steam_credentials` | `username: string` | `boolean` | Searches IsolatedStorage for account.config |
| `get_cached_steam_username` | — | `string \| null` | Reads username from DepotDownloader's account.config |
| `authenticate_steam` | `username: string` | `void` | Opens Terminal.app with auth script |
| `download_steam_game` | `request: DownloadRequest` | `void` | Spawns DepotDownloader; emits `download://progress` events |
| `cancel_download` | `appId: number` | `void` | Sets AtomicBool cancel flag |
| `validate_game_files` | `appId, username, installDir, backend` | `void` | Re-verify with `-validate` |

---

## Key data types

```typescript
// src/lib/types/index.ts — mirrors Rust structs exactly

interface Game {
  id: string                          // UUID v4
  name: string
  exe_path: string                    // absolute macOS path to .exe
  working_dir: string | null          // null = use exe parent dir
  cover_art: string | null            // absolute path; use convertFileSrc() to display
  wine_prefix: string | null          // null = use AppConfig.default_prefix
  extra_args: string[]
  translation_backend: "d3dmetal" | "dxvk" | "none"
  show_hud: boolean                   // MTL_HUD_ENABLED
  esync: boolean                      // WINEESYNC
  msync: boolean                      // WINEMSYNC (also sets WINEESYNC=1 per Whisky)
  advertise_avx: boolean              // ROSETTA_ADVERTISE_AVX (macOS 15+)
  enable_dxr: boolean                 // D3DM_SUPPORT_DXR (M3+ only)
  source: "manual" | "steam"
  steam_app_id: number | null
  notes: string
  playtime_secs: number               // updated when process exits in running_games poll
}

interface AppConfig {
  wine64_path: string                 // default: auto-detected on first run
  gptk_lib_path: string              // D3DMetal/libd3dshared directory
  default_prefix: string             // ~/Wine/Bottles/default
  suppress_wine_debug: boolean       // WINEDEBUG=fixme-all when true
  theme: "dark" | "light" | "system"
  global_hud: boolean
  metalfx_enabled: boolean           // D3DM_ENABLE_METALFX (GPTK 3.0+)
}
```

---

## Critical implementation details

### Wine launching (`src-tauri/src/launcher.rs`)

**Command:** `wine64 start /unix <exe_path> [extra_args]`  
**No `arch -x86_64` wrapper** — Rosetta activates automatically for x86_64 binaries.

**Environment variables injected:**
```
WINEPREFIX          = expanded prefix path
DYLD_LIBRARY_PATH   = gptk_lib_path:gptk_lib_path/external:<existing>
WINEDEBUG           = fixme-all (or "" if suppress_wine_debug=false)
GST_DEBUG           = 1
MTL_HUD_ENABLED     = 1 or 0
WINEESYNC           = 1 if esync OR msync (msync requires ESYNC=1 for D3DMetal)
WINEMSYNC           = 1 if msync
WINEDLLOVERRIDES    = "dxgi,d3d9,d3d10core,d3d11=n,b" if DXVK
DXVK_ASYNC          = 1 if DXVK
D3DM_SUPPORT_DXR    = 1 if enable_dxr
D3DM_ENABLE_METALFX = 1 if metalfx_enabled
ROSETTA_ADVERTISE_AVX = 1 if advertise_avx
```

**Auto-creates Wine prefix:** If `WINEPREFIX` dir doesn't exist, `spawn()` runs `wineboot --init` before launching the game. Creates parent directories too. First launch ~5-10s slower.

### DepotDownloader authentication (`src-tauri/src/downloader.rs`)

**Two-phase approach:**

1. **Phase 1 (first time only):** Opens Terminal.app via `osascript`. User types password + Steam Guard. DepotDownloader saves a token to .NET IsolatedStorage.

2. **Phase 2 (all subsequent):** DepotDownloader reads the cached token silently. We pipe stderr (all DD output goes there), parse `Progress: X.XX%` lines, emit `download://progress` Tauri events.

**Credential detection:** Searches `~/Library/Application Support/IsolatedStorage/` recursively for `account.config`. Then deflate-decompresses (raw deflate, .NET format) and scans protobuf bytes for the username string. The username stored in the token must exactly match what's passed to DepotDownloader via `-username`.

**`get_cached_steam_username` command** auto-detects the stored username so the UI can pre-fill it. This is critical — if the wrong username is passed, DepotDownloader exits with code 1 even with valid credentials.

### Steam cover art

Auto-fetched in `upsert_game` when `cover_art == null` and `steam_app_id` is set:
```
https://cdn.akamai.steamstatic.com/steam/apps/{app_id}/library_600x900.jpg
```
Saved to `~/Library/Application Support/com.forgelauncher.app/covers/{app_id}.jpg`.

**Display:** Cover art paths are absolute filesystem paths. Use `convertFileSrc(path)` from `@tauri-apps/api/core` to convert to `asset://localhost/...` URL before setting as `src`. WKWebView cannot load `file://` URLs directly.

### wine64 auto-detection (`src-tauri/src/config.rs`)

`detect_wine64()` searches these paths in order:
1. `/opt/homebrew/bin/wine64` (ARM Homebrew — GPTK cask)
2. `/usr/local/bin/wine64` (Intel Homebrew)
3. `~/Library/Application Support/com.isaacmarovitz.Whisky/Libraries/Wine/bin/wine64`
4. `/Applications/CrossOver.app/Contents/SharedSupport/CrossOver/bin/wine64`
5. `which wine64` (PATH fallback)

On first run, `load_config` detects and saves the found path to `config.json`.

### SteamCMD is broken on Homebrew macOS ARM

The Homebrew `steamcmd` cask fails at runtime with `Failed to load steamconsole.dylib`. This is detected in `find_steamcmd()` and the tool is marked unavailable. **Use DepotDownloader** — it's native ARM64 and works correctly.

---

## Known issues / what's not done yet

| Issue | Where | Notes |
|---|---|---|
| Per-game Wine prefix UI | `App.svelte` detail panel | `wine_prefix` field exists in `Game` but no picker in UI. User must edit `games.json` manually or you need to add a text input + Browse button. |
| DXVK HUD level per-game | `App.svelte` / `GameCard` | `DxvkHud` enum exists in Rust (`Off/Fps/Partial/Full`) but UI only exposes the backend toggle, not HUD level. |
| `metal_trace` per-game | Settings | `metal_trace: bool` exists in `LaunchOptions` but hardcoded to `false`. Needs a toggle. |
| `advertise_avx` / `enable_dxr` UI | Detail panel | Both fields exist in `Game` struct and are wired to env vars but there's no UI to toggle them. |
| No search/filter in library | `App.svelte` | Library grid has no search bar. Usable at small scale, becomes painful at 50+ games. |
| Playtime display in detail panel | `App.svelte` | `playtime_secs` is tracked and persisted but only shown in `GameCard`, not the detail panel. |
| No per-game prefix creation | `App.svelte` | The `create_prefix` command exists but isn't exposed in the UI. |
| `depots/` directory in project root | Root | DepotDownloader left behind `depots/232250/` test data in the project directory. Should be in `.gitignore` or cleaned up. |
| No `.gitignore` | Root | Project has no `.gitignore`. Should exclude `node_modules/`, `target/`, `dist/`, `depots/`, `src-tauri/gen/`. |
| Cover art not re-fetched | `upsert_game` | If cover art fetch fails silently (offline), it won't retry on next launch. |

---

## Environment — what's installed on this machine

```
macOS: Apple Silicon (M-series)
wine64: /opt/homebrew/bin/wine64  (wine-7.7 Game Porting Toolkit 1.1)
GPTK libs: not confirmed — gptk_lib_path may need to be set manually in Settings
DepotDownloader: /opt/homebrew/bin/DepotDownloader
SteamCMD: installed but broken (steamconsole.dylib missing — known Homebrew ARM bug)
Steam username: little__leviathan (stored in DepotDownloader IsolatedStorage token)
Wine prefix: ~/Wine/Bottles/default (created, working)
Game installed: Storebound (AppID 3417410) at ~/Games/3417410/Storebound.exe
```

---

## Things that work end-to-end (confirmed)

- [x] `npm run tauri dev` — starts and opens native macOS window
- [x] `npm run build` — clean Vite production build (77 KB JS, 25 KB CSS)
- [x] `cargo check` — zero errors, zero warnings
- [x] DepotDownloader auth via Terminal — credentials cached, auto-detected
- [x] Game download (Storebound AppID 3417410) — files at `~/Games/3417410/`
- [x] exe path picker — native macOS file dialog, saves to `games.json`
- [x] Game launch — Storebound runs via `wine64 start /unix`
- [x] Wine prefix auto-creation — `wineboot --init` on first launch
- [x] Cover art — auto-fetched and displayed via `convertFileSrc()`
- [x] Delete game — hover ✕ on card, two-click confirm
- [x] Playtime tracking — incremented when process exits
- [x] Wine not installed banner — yellow banner with install command + Copy button

---

## Quick reference: adding a new Tauri command

**Rust (`src-tauri/src/main.rs`):**
```rust
#[tauri::command]
async fn my_command(arg: String) -> Result<String, String> {
    Ok(format!("got: {}", arg))
}

// In main():
.invoke_handler(tauri::generate_handler![
    // ... existing ...
    my_command,
])
```

**TypeScript (any store or component):**
```typescript
import { invoke } from "@tauri-apps/api/core";
const result = await invoke<string>("my_command", { arg: "hello" });
```

**Rules:**
- Return `Result<T, String>` — Tauri serialises `Err` to a rejected Promise
- Argument names in `invoke({})` must match Rust parameter names exactly (snake_case)
- Add to `docs/API.md` when done
