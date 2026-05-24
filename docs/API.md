# Tauri Command API Reference

All commands are invoked from the frontend via:

```ts
import { invoke } from "@tauri-apps/api/core";
const result = await invoke<ReturnType>("command_name", { arg1, arg2 });
```

Every command returns a `Promise` that:
- **Resolves** with the typed return value on success
- **Rejects** with a `string` error message on failure

---

## Game Library

### `load_games`

Load the persisted game library from disk.

```ts
invoke<Game[]>("load_games")
```

Returns: `Game[]` — empty array on first run.

---

### `save_games`

Overwrite the full game library on disk.

```ts
invoke<void>("save_games", { games: Game[] })
```

---

### `upsert_game`

Insert or update a single game (matched by `id`). Safer than `save_games` for
single-game operations — avoids overwriting concurrent changes.

```ts
invoke<Game[]>("upsert_game", { game: Game })
```

Returns: updated `Game[]`.

---

### `remove_game`

Remove a game by UUID.

```ts
invoke<Game[]>("remove_game", { id: string })
```

Returns: updated `Game[]`.

---

## Launcher

### `launch_game`

Launch a game through `arch -x86_64 wine64 <exe>` with all environment
variables constructed from the game's config and global AppConfig.

```ts
invoke<void>("launch_game", { gameId: string })
```

Errors if:
- The game UUID is not in the library
- `arch` or `wine64` is not found at the configured path
- The `.exe` path does not exist

---

### `kill_game`

Send `SIGKILL` to the running game process.

```ts
invoke<void>("kill_game", { gameId: string })
```

Silent no-op if the game is not running.

---

### `running_games`

Return UUIDs of games currently running. Also reaps processes that have exited.

```ts
invoke<string[]>("running_games")
```

Call this on a polling interval (the store does this every 3 seconds).

---

### `create_prefix`

Initialise a new Wine bottle at `prefix_path`.

```ts
invoke<void>("create_prefix", { prefixPath: string })
```

Runs: `arch -x86_64 wine64 wineboot --init`

This can take 5–15 seconds. Show a loading state while it completes.

---

## Configuration

### `load_config`

Read global launcher settings. Returns defaults on first run.

```ts
invoke<AppConfig>("load_config")
```

---

### `save_config`

Persist global launcher settings.

```ts
invoke<void>("save_config", { cfg: AppConfig })
```

---

## Steam

### `scan_steam_games`

Scan the local Steam library for Windows-only games.

```ts
invoke<SteamGame[]>("scan_steam_games")
```

Errors if `~/Library/Application Support/Steam/steamapps/` does not exist.

---

### `launch_steam_game`

Launch a Steam game via the `steam://` URI (recommended).

```ts
invoke<void>("launch_steam_game", { appId: number })
```

Runs: `open -a Steam steam://rungameid/<appId>`  
Requires Steam to be installed and running.

---

### `launch_steam_game_direct`

Launch a Steam game directly through GPTK/Wine, bypassing the Steam client.

```ts
invoke<void>("launch_steam_game_direct", {
  appId:      number,
  prefixPath: string,
})
```

The game must be in the scanned Steam library (matching AppID).

---

## Type reference

```ts
interface Game {
  id:                   string;
  name:                 string;
  exe_path:             string;
  working_dir:          string | null;
  cover_art:            string | null;
  wine_prefix:          string | null;
  extra_args:           string[];
  translation_backend:  "d3dmetal" | "dxvk" | "none";
  show_hud:             boolean;
  esync:                boolean;
  msync:                boolean;
  advertise_avx:        boolean;
  enable_dxr:           boolean;
  source:               "manual" | "steam";
  steam_app_id:         number | null;
  notes:                string;
  playtime_secs:        number;
}

interface AppConfig {
  wine64_path:         string;
  gptk_lib_path:       string;
  default_prefix:      string;
  suppress_wine_debug: boolean;
  theme:               "dark" | "light" | "system";
  global_hud:          boolean;
  metalfx_enabled:     boolean;
}

interface SteamGame {
  app_id:       number;
  name:         string;
  install_dir:  string;
  exe_path:     string;
  os_list:      string;
  size_on_disk: number;
}
```

---

## Environment variables injected at launch

| Variable | Value | Condition |
|---|---|---|
| `WINEPREFIX` | game or default prefix path | always |
| `DYLD_LIBRARY_PATH` | `<gptk_lib_path>:<gptk_lib_path>/external` | always |
| `WINEDEBUG` | `-all` | `suppress_wine_debug = true` |
| `WINEESYNC` | `1` | `esync = true` |
| `WINEMSYNC` | `1` | `msync = true` |
| `MTL_HUD_ENABLED` | `1` | `show_hud = true` or `global_hud = true` |
| `WINEDLLOVERRIDES` | `d3d11=n,b;d3d10core=n,b` | `translation_backend = "dxvk"` |
| `D3DM_SUPPORT_DXR` | `1` | `enable_dxr = true` |
| `D3DM_ENABLE_METALFX` | `1` | `metalfx_enabled = true` |
| `ROSETTA_ADVERTISE_AVX` | `1` | `advertise_avx = true` |
