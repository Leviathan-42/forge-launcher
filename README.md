# Forge Launcher

> **Vibe-coded project:** Forge's launcher/app code is 100% vibe coded. No real human-authored production code is claimed here, except for upstream open-source components that Forge builds on, such as Wine and the open-source Wine work published with CodeWeavers/CrossOver sources. (ahahah ai go build free crossover)

Forge is an experimental macOS launcher/runtime for Windows games.

Current development focus:

```text
CodeWeavers/CrossOver open-source Wine sources -> Forge-owned Wine runtime -> Windows Steam in one Forge bottle -> game backend handoff
```

## Experimental status

Forge is very experimental. Expect per-game launch options, rendering bugs, broken Steam updates, missing anti-cheat support, and occasional Wine prefix resets while the runtime model stabilizes.

## Active app

The active app is the native SwiftUI app:

```text
macos/ForgeNative/Sources/ForgeNative/ForgeNativeApp.swift
```

Useful commands:

```sh
npm run native:dev
npm run native:build
npm run check:all
npm run kill
```

## Current runtime model

The current working runtime on this machine is a Forge-owned WoW64 Wine build:

```text
~/Wine/Runtimes/forge-cx-wine-11-open-wow64/bin/wine
~/Wine/Runtimes/forge-cx-wine-11-open-wow64/bin/wineserver
```

The main/default bottle should be the normal Steam bottle:

```text
~/Wine/Bottles/default
```

Do not create per-game bottles for normal use unless testing a compatibility issue. Steam games should be installed in the main bottle and launched through Windows Steam so Steamworks/DRM/session APIs are available.

## Graphics and launch options

Forge currently treats Steam itself as a safe UI process, then uses `FORGE_GAME_*` environment variables in the patched Wine runtime to hand game backend settings to Steam child processes.

Unity games may need compatibility launch options. For PEAK, the working options are:

```text
-force-vulkan -force-gfx-st -disable-gpu-skinning -screen-fullscreen 1
```

These fix the observed avatar/mesh corruption by disabling Unity GPU skinning and using a simpler graphics threading mode.

## Docs

See:

- `docs/ARCHITECTURE.md`
- `docs/RUNTIME_PROFILES.md`
- `docs/STEAM.md`
- `docs/ENV_VARS.md`
