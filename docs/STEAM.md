# Steam Integration

Forge uses Windows Steam inside a Wine bottle for games that expect a real Steam session.

## Current model

```text
One main Forge bottle
  -> Windows Steam
    -> installed Windows games
```

Steam owns authentication, updates, DRM, Steam Cloud, and Steamworks APIs. Forge scans the bottle and exposes launchable entries in the native SwiftUI app. Do not create separate per-game bottles for normal Steam usage; keep games in the main Steam bottle and use per-game launch options for compatibility.

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

### 2. Launch detected Steam game through Steam

Forge shows installed Steam games as app rows and launches them through Windows Steam with:

```text
steam.exe -applaunch <appid> <game launch options>
```

This keeps Steamworks, DRM, Steam Cloud, and the logged-in Steam session available to the game.

### 3. Direct EXE launch for diagnostics only

Direct launches may set:

```text
SteamAppId=<appid>
SteamGameId=<appid>
```

but many games still fail because `SteamAPI_Init()` cannot connect to a valid Steam session. Use direct launch only for diagnostics or non-Steam applications.

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

## Unity game launch options

Unity titles can show mesh/avatar corruption under translation layers. First try keeping the game in the main Steam bottle and adding launch options rather than making a separate bottle.

Useful options:

```text
-force-vulkan
-force-gfx-st
-disable-gpu-skinning
-screen-fullscreen 1
```

Known local example:

```text
PEAK: -force-vulkan -force-gfx-st -disable-gpu-skinning -screen-fullscreen 1
```

This fixed PEAK's avatar/character mesh corruption on the Forge WoW64 + MoltenVK path.
