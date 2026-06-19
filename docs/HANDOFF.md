# Current Handoff

Forge is an experimental macOS launcher/runtime. The launcher/app code is vibe coded; runtime work builds on upstream open-source Wine code, including Wine sources published with CodeWeavers/CrossOver releases.

## Current model

```text
Forge-owned WoW64 Wine runtime
  -> one main Forge bottle
  -> Windows Steam
  -> Steam games via steam.exe -applaunch <appid> when possible
  -> per-game launch options/backend handling
```

Runtime:

```text
~/Wine/Runtimes/forge-cx-wine-11-open-wow64/bin/wine
~/Wine/Runtimes/forge-cx-wine-11-open-wow64/bin/wineserver
```

Main bottle:

```text
~/Wine/Bottles/default
```

## Working title

PEAK works from the main Steam bottle.

Working args:

```text
-force-vulkan -force-gfx-st -disable-gpu-skinning -screen-fullscreen 1
```

## Working title: Against the Storm

Against the Storm, Steam appid `1336490`, works with Forge's DXMT compatibility profile.

Working profile:

```text
backend: dxmt
launch args: -screen-fullscreen 1
```

Findings:

- Against the Storm is a 64-bit Unity D3D11 title.
- Unity Vulkan and OpenGL/Core paths are not usable in this build.
- DXVK reaches MoltenVK feature limits for this title, especially geometry shader support.
- GPTK/D3DMetal experiments were unstable and are not the preferred Forge-owned runtime direction.
- DXMT gets the game through D3D11 initialization when staged into the Forge Wine runtime and prefix.
- The `dd3d11.dll` alias matters because this Unity build probes that DLL name.

Current code in `ForgeNativeApp.swift`:

- Seeds `steam:1336490` as `backend_override: dxmt`.
- Migrates older stale Against the Storm D3DMetal profiles to DXMT.
- `ensureDXMTInstalled(winePath:prefixPath:)` stages DXMT PE DLLs and `winemetal.so`.
- Direct launch graphics validation reached `Loading completed`; Steam/DLC callback errors from direct launch are separate from graphics initialization.

## Recommended next work

Polish per-game compatibility profiles in UI/config:

```text
Bottle default backend
  -> per-game backend override
  -> per-game launch args
  -> per-game env overrides
  -> reset-to-seeded-profile button
```

Expose/edit per-game details:

```text
Backend: DXVK/VKD3D, DXVK, VKD3D, DXMT, WineD3D, D3DMetal, None
Launch args: editable text field
Environment overrides: advanced section
Notes: why this profile exists
```

Persist profiles keyed by Steam appid when available, else normalized EXE path.

Useful logs:

```text
~/Library/Application Support/com.forgelauncher.app/Logs/swiftui-launch-*.log
~/Library/Application Support/com.forgelauncher.app/Logs/manual-against-*.log
~/Wine/Bottles/default/drive_c/users/forge/AppData/LocalLow/Eremite Games/Against the Storm/Player.log
```
