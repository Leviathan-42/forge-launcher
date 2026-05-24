# Architecture

## Overview

Forge Launcher is a two-process Tauri 2 application:

```
┌─────────────────────────────────────────────────────────────────┐
│  WebView (Svelte + Vite)                                         │
│  ┌───────────┐  ┌──────────────┐  ┌────────────────────────┐   │
│  │  Stores   │  │  Components  │  │  Types (mirrors Rust)  │   │
│  │  games.ts │  │  GameCard    │  │  Game, AppConfig,       │   │
│  │  launcher │  │  SteamImport │  │  SteamGame, ...         │   │
│  │  config   │  │  Toast       │  │                        │   │
│  └─────┬─────┘  └──────────────┘  └────────────────────────┘   │
│        │  invoke("command", args)                               │
└────────│────────────────────────────────────────────────────────┘
         │  Tauri IPC bridge (JSON serialisation)
┌────────▼────────────────────────────────────────────────────────┐
│  Rust backend (src-tauri/)                                       │
│  ┌──────────┐  ┌───────────┐  ┌──────────┐  ┌──────────────┐  │
│  │ main.rs  │  │ config.rs │  │launcher  │  │  steam.rs    │  │
│  │ (router) │  │ (persist) │  │  .rs     │  │  (ACF parse) │  │
│  └──────────┘  └───────────┘  └────┬─────┘  └──────────────┘  │
│                                    │                            │
│                         std::process::Command                   │
└────────────────────────────────────│────────────────────────────┘
                                     ▼
                          arch -x86_64 wine64 game.exe
                               │
                    ┌──────────▼──────────────────────┐
                    │  Rosetta 2  (x86_64 translation) │
                    │  Wine (Windows API layer)        │
                    │  GPTK D3DMetal / libd3dshared    │
                    │  Metal GPU (Apple Silicon)       │
                    └─────────────────────────────────┘
```

## Process model

| Layer | Technology | Memory budget |
|---|---|---|
| WebView | WKWebView (system, shared) | ~15 MB |
| Rust binary | Tauri 2 + stripped release build | ~5–8 MB |
| Wine (per game) | GPTK wine64 | ~80–200 MB (game-dependent) |

The Tauri binary itself targets **< 10 MB** via `opt-level = "z"`, `lto = true`, `strip = true` and `panic = "abort"` in `Cargo.toml`.

## IPC design

All frontend→backend calls use `invoke()` from `@tauri-apps/api/core`.  
All commands return `Result<T, String>` on the Rust side, which Tauri serialises to a rejected Promise on the TS side.

Commands are defined in `main.rs` and wired via `tauri::generate_handler![]`.

## State management

```
Svelte stores (writable<T>)
  ├── games        — full library array
  ├── runningGameIds — Set<string> of live PIDs
  ├── selectedGameId — currently focused game
  ├── appConfig    — global settings
  ├── steamGames   — scan results
  └── notifications — toast queue
```

All stores are mutated exclusively through exported **action functions** (e.g. `loadGames`, `upsertGame`, `launchGame`).  
Components never call `store.set()` directly.

## Data flow: launching a game

```
User clicks "Launch"
  → GameCard calls launchGame(id)
  → runningGameIds updated optimistically
  → invoke("launch_game", { gameId })
  → Rust: load game from games.json
  → Rust: build LaunchOptions (env vars, paths)
  → Rust: Command::new("arch").arg("-x86_64")...spawn()
  → GameProcess stored in RunningGames state
  → Poll loop (every 3s) reaps finished processes
  → runningGameIds synced
```

## Module responsibilities

| File | Responsibility |
|---|---|
| `src-tauri/src/main.rs` | Tauri command registration, global state, entry point |
| `src-tauri/src/config.rs` | `Game` + `AppConfig` structs, JSON read/write |
| `src-tauri/src/launcher.rs` | `LaunchOptions` builder, `spawn()`, `init_wine_prefix()` |
| `src-tauri/src/steam.rs` | ACF manifest parser, library scanner, Steam URI launch |
| `src/lib/stores/games.ts` | Library CRUD, running-state polling |
| `src/lib/stores/launcher.ts` | Launch/kill actions, toast notifications |
| `src/lib/stores/config.ts` | Config + Steam scan actions |
| `src/lib/types/index.ts` | TypeScript interfaces mirroring Rust structs |
| `src/lib/components/GameCard.svelte` | Single game tile in the grid |
| `src/lib/components/SteamImport.svelte` | Steam library scan + import modal |
| `src/lib/components/Toast.svelte` | Toast notification renderer |
| `src/App.svelte` | Root layout: sidebar, grid, detail panel, settings |
