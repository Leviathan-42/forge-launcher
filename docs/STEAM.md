# Steam Integration

## How game detection works

Forge Launcher scans Steam's ACF (AppCache Format) manifest files, which are
plain-text key-value files Steam writes for every installed game.

```
~/Library/Application Support/Steam/steamapps/
  appmanifest_220.acf        ← Half-Life 2
  appmanifest_1245620.acf    ← Elden Ring
  libraryfolders.vdf         ← additional library paths
  common/
    Elden Ring/
      Game/
        eldenring.exe        ← detected exe
```

The Rust `steam.rs` module:

1. Reads `libraryfolders.vdf` to find any additional Steam library roots
   (external drives, etc.)
2. Iterates every `appmanifest_*.acf` file in each root
3. Parses `appid`, `name`, `installdir`, `oslist`, `SizeOnDisk`
4. **Skips** any game whose `oslist` includes `"macos"` (has a native Mac build)
5. Runs a heuristic to find the primary `.exe` in the `common/<installdir>/`
   directory
6. Returns a sorted `Vec<SteamGame>` to the frontend

## Launch modes

### Mode 1: Steam Protocol (recommended)

```
open -a Steam steam://rungameid/1245620
```

- Steam handles authentication, updates, DRM, and the overlay
- The Steam client must be running
- Forge Launcher cannot track this process directly (Steam owns it)
- **Use this for most games**, especially those with online components

### Mode 2: Direct GPTK/Wine launch

```
arch -x86_64 wine64 /path/to/game.exe -steam -steamid 1245620
```

- Bypasses the Steam client entirely
- Forge Launcher tracks the process (shows running badge, can kill it)
- Works offline
- Steam overlay will not be available
- **Use when**: Steam overlay crashes the game, running offline, or needing
  fine-grained Wine environment control

## Import workflow

1. Click **"+ Steam"** in the sidebar
2. Click **"Re-scan"** if your library is not showing
3. Select games you want to add to Forge Launcher's library
4. Click **"Import N Games"**

Each imported game is added as a `GameSource::Steam` entry with:
- `translation_backend: d3dmetal` (default; change per-game in settings)
- `esync: true`
- `wine_prefix: null` → falls back to the global default prefix

## Per-game Wine prefix for Steam games

Many Steam games use DRM that writes to the Windows registry inside the Wine
prefix. It's generally safest to give Steam games their own dedicated prefix:

```sh
WINEPREFIX=~/Wine/Bottles/steam \
  arch -x86_64 /usr/local/bin/wine64 wineboot --init
```

Then set `wine_prefix` to `~/Wine/Bottles/steam` when importing Steam games.

## Steam Runtime / Proton note

Forge Launcher does **not** use Steam's Proton or the Steam Linux Runtime.
It uses Apple's GPTK wine64 binary directly. For best results:

- GPTK works best with **DirectX 12** titles
- DX9/DX10/DX11 games may work better with the `dxvk` backend
- Anti-cheat (EasyAntiCheat, BattlEye) **will not work** via Wine on macOS

## ACF field reference

| Field | Example | Used for |
|---|---|---|
| `appid` | `1245620` | Unique game identifier |
| `name` | `"ELDEN RING"` | Display name |
| `installdir` | `"ELDEN RING"` | Subfolder under `common/` |
| `oslist` | `"windows"` | Filter: skip if includes "macos" |
| `SizeOnDisk` | `44000000000` | Displayed in import UI |
| `StateFlags` | `4` | `4` = fully installed |

## Known limitations

- Games installed via **Family Sharing** may have incomplete manifests
- **Workshop content** directories are not scanned for exes
- Some games have their `.exe` in a subdirectory — the heuristic may pick the
  wrong one. You can correct it manually in the game detail panel.
- Games that require **Visual C++ Redistributables** or **DirectX** must have
  those installed inside the Wine prefix first. See SETUP.md for details.
