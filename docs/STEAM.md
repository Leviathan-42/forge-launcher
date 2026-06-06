# Steam Integration

Forge uses Windows Steam inside a Wine bottle for games that expect a real Steam session.

## Current model

```text
Forge bottle
  -> Windows Steam
    -> installed Windows games
```

Steam owns authentication, updates, DRM, Steam Cloud, and Steamworks APIs. Forge scans the bottle and exposes launchable entries in the native SwiftUI app.

## Detection

ForgeNative scans:

```text
<WINEPREFIX>/drive_c/Program Files (x86)/Steam/steamapps/
  appmanifest_<appid>.acf
  common/<install dir>/
```

For each manifest it reads:

- `appid`
- `name`
- `installdir`

It then finds a likely primary `.exe` and hides helper files such as:

- `steamwebhelper.exe`
- `UnityCrashHandler*.exe`
- crash reporters
- uninstallers
- launcher-managed child EXEs where only the launcher should show

## Launch modes

### 1. Launch Steam

Steam itself is launched with a safe backend because its Chromium UI can break under full game rendering settings.

Forge passes `-no-cef-sandbox` and `-cef-disable-sandbox` to Steam.

### 2. Launch detected Steam game directly

Forge can show installed Steam games as app rows. Direct launches set:

```text
SteamAppId=<appid>
SteamGameId=<appid>
```

This can work for offline/simpler Steamworks games, but some titles still require Steam's full process/session to be running.

### 3. Launch from inside Steam

For games with strict Steamworks/DRM behavior, open Windows Steam in the bottle and launch the game from Steam itself.

## Steam safe mode split

Steam UI safe mode should not become the game backend. Forge uses `FORGE_GAME_*` variables so a patched Forge Wine runtime can restore the intended game backend for child game processes.

## Compatibility limits

Likely not supported:

- kernel-level anti-cheat
- Windows drivers/services
- games requiring EAC/BattlEye/Ricochet/Vanguard in kernel mode

Examples that usually fail on Wine/macOS:

- Valorant
- Fortnite
- Call of Duty / Warzone
- Destiny 2
- many modern competitive shooters with kernel anti-cheat

## PEAK note

PEAK is currently a test case. It is detected from Steam manifests and can be launched directly, but current logs show backend-specific failures on this machine. Keep testing DXVK/VKD3D, D3DMetal/GPTK, and Steam-owned launch behavior from logs rather than assuming one universal fix.
