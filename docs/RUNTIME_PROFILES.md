# Runtime Profiles

Forge uses runtime profiles to separate Wine runner paths from bottle settings.

## Model

```text
RuntimeProfile
  -> Wine / wineserver paths
  -> optional GPTK lib path
  -> optional DXVK/VKD3D/MoltenVK paths
  -> default graphics backend
  -> environment overrides

BottleEntry
  -> prefix path
  -> runtime_profile_id
  -> optional graphics_backend override
  -> environment overrides
```

## Backends

```swift
enum GraphicsBackend {
  case d3dMetal
  case dxvk
  case vkd3d
  case dxvkVkd3d
  case wineBuiltin
  case dxmt
  case none
}
```

## CrossOver no-GUI launches

Forge can use CrossOver compatibility without opening the CrossOver app UI. When a
local CrossOver install is present, Forge adds a runtime profile named:

```text
CrossOver (no GUI)
```

It points at CrossOver's bundled `wine` wrapper and discovers CrossOver bottles from:

```text
~/Library/Application Support/CrossOver/Bottles
~/Wine/Bottles
```

For CrossOver bottles, use the `Bottle Default` graphics backend unless you explicitly
want Forge to override DLL/backends. Forge pins the selected bottle with an absolute
`CX_BOTTLE`/`WINEPREFIX`, so the game starts through CrossOver Wine directly but the
CrossOver application window is not launched.

## Recommended defaults

Forge is experimental. The current recommended default on Apple Silicon is:

```text
Forge-owned WoW64 Wine runtime + Windows Steam + dxvk_vkd3d/MoltenVK game backend
```

- General Steam-game default: `dxvk_vkd3d`
- D3D11-only games: `dxvk` first; `dxmt` can be better when MoltenVK lacks needed D3D11 features
- D3D12-only games: `vkd3d` or experimental `d3dmetal`
- GPTK-specific testing: `d3dmetal`
- Last resort only: `wine_builtin`

Current local runtime:

```text
~/Wine/Runtimes/forge-cx-wine-11-open-wow64/bin/wine
~/Wine/Runtimes/forge-cx-wine-11-open-wow64/bin/wineserver
```

## MoltenVK

DXVK/VKD3D paths require a MoltenVK ICD. Common Homebrew path:

```text
/opt/homebrew/opt/molten-vk/etc/vulkan/icd.d/MoltenVK_icd.json
```

Forge attempts to configure both:

```text
VK_ICD_FILENAMES
VK_DRIVER_FILES
```

## D3DMetal

D3DMetal uses GPTK resources, commonly:

```text
/Applications/Game Porting Toolkit.app/Contents/Resources/wine/bin/wine64
/Applications/Game Porting Toolkit.app/Contents/Resources/wine/lib/external
/Applications/Game Porting Toolkit.app/Contents/Resources/wine/lib/wine/x86_64-windows
```

Forge may use GPTK's `wine64` for D3DMetal launches so GPTK's builtin DLL/unix library pairing is consistent.

## Merge order

```text
AppConfig.env
  -> RuntimeProfile.env
  -> BottleEntry.envOverrides
  -> backend-specific launch cleanup
```

Direct game launches clear Steam-only DXVK filters so Steam safe mode does not leak into games.

## Compatibility notes

Per-game launch options are expected. Keep these in a compatibility profile, not in a
separate bottle, when the game is installed through Steam.

The native app now exposes those profiles directly from the app list. Each row shows
compact profile badges when launch args, env overrides, or notes exist, and the pencil
action opens an editor for:

```text
Backend override
Launch args
Environment overrides
Notes
Reset to seeded profile
```

Unity games are especially sensitive to graphics threading and GPU skinning under
translation layers. Useful launch options to test:

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

Direct-launching Steam games can fail because Steamworks is unavailable. Prefer Windows
Steam `-applaunch <appid>` from the main bottle for Steam games.

## Current per-game notes

- Against the Storm (`steam:1336490`): DXMT; Unity D3D11 path works through
  D3D11 -> Metal after staging DXMT DLLs.
- Among Us (`steam:945360`): WineD3D with `WINE_D3D_CONFIG=renderer=vulkan`;
  DXMT/DXVK are not viable for its 32-bit Unity build in the current WoW64 runtime.
- PEAK (`name:peak`): native Unity Vulkan via
  `-force-vulkan -force-gfx-st -disable-gpu-skinning -screen-fullscreen 1`.
- Overwatch 2 (`steam:2357570`): still under investigation. The active Wine patch behind `FORGE_STACK_GUARANTEE_BYTES=262144` changes the failure from an immediate `virtual_setup_exception stack overflow` / loader-lock spin to a short exit before rendering. Steam tracks the game briefly, then reports exit code `0xe1d0ffff`. This is progress, not a working profile yet.
