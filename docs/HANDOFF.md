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

## Current failing title

Against the Storm, Steam appid `1336490`, is not fixed.

Findings:

- Unity Vulkan path is not usable: forced Vulkan says the renderer was not built with usable shaders.
- Unity OpenGL/Core path is not usable: forced GLCore says the renderer was not built.
- DXVK 2.7.1 loads but rejects MoltenVK/Apple GPU because required `geometryShader` support is missing.
- GPTK/D3DMetal is the right class of layer, but current experiments still fail D3D11 device creation.
- Starting Steam with Forge WoW64 Wine and then using GPTK `wine64` in the same prefix caused a wineserver version mismatch, so current experimental code direct-launches D3DMetal games under GPTK `wine64` with `SteamAppId` set.

Current experimental code in `ForgeNativeApp.swift`:

- Hardcoded Against the Storm backend override to `.d3dMetal`.
- D3DMetal launches use GPTK `wine64`.
- D3DMetal Steam games currently skip `steam.exe -applaunch` to avoid mixed-wineserver mismatch.
- Conservative flags are set: `D3DM_MTL4=0`, `D3DM_SUPPORT_DXR=0`, `D3DM_ENABLE_METALFX=0`.

Do not claim Against the Storm is fixed.

## Recommended next work

Implement per-game compatibility profiles in UI/config:

```text
Bottle default backend
  -> per-game backend override
  -> per-game launch args
  -> per-game env overrides
  -> reset-to-default button
```

Expose backends per game:

```text
DXVK/VKD3D
DXVK
VKD3D
WineD3D
D3DMetal
None
future: DXMT
```

Persist profiles keyed by Steam appid when available, else normalized EXE path.

Likely future solution for Against the Storm: add a Forge-owned/open-source `DXMT` backend for D3D11 -> Metal. DXVK is blocked by MoltenVK features for this game, and GPTK/D3DMetal is not ideal for Forge's open-source runtime goals.

Useful logs:

```text
~/Library/Application Support/com.forgelauncher.app/Logs/swiftui-launch-*.log
~/Library/Application Support/com.forgelauncher.app/Logs/manual-against-*.log
~/Wine/Bottles/default/drive_c/users/forge/AppData/LocalLow/Eremite Games/Against the Storm/Player.log
```
