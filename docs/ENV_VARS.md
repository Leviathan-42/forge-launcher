# Wine / GPTK / MoltenVK Environment Reference

ForgeNative builds the Wine environment at launch time from global config, runtime profile, bottle overrides, and the selected backend.

## Core variables

| Variable | Purpose |
|---|---|
| `WINEPREFIX` | Selected bottle path |
| `WINEDEBUG` | Suppresses or enables Wine debug output |
| `WINEDBG` | Set to `-all` to avoid debugger popups during crashes |
| `WINEESYNC` | Enables ESYNC when available |
| `WINEMSYNC` | Enables macOS MSYNC in Forge Wine |
| `WINEDLLOVERRIDES` | Selects native vs builtin DirectX DLLs |
| `WINEDLLPATH` | Additional Wine builtin DLL search path |
| `DYLD_LIBRARY_PATH` | Native macOS library path for GPTK/D3DMetal |
| `VK_ICD_FILENAMES` / `VK_DRIVER_FILES` | Vulkan ICD path for MoltenVK |
| `MTL_HUD_ENABLED` / `MTL_HUD_LAYER` | Apple Metal HUD toggles |
| `FORGE_STACK_GUARANTEE_BYTES` | Experimental Forge Wine stack-overflow handling reserve for protected loaders such as Overwatch |

## Backend behavior

### DXVK/VKD3D

Typical values:

```sh
WINEDLLOVERRIDES=dxgi,d3d9,d3d10core,d3d11,d3d12,user32=n,b
VK_ICD_FILENAMES=/opt/homebrew/opt/molten-vk/etc/vulkan/icd.d/MoltenVK_icd.json
VK_DRIVER_FILES=/opt/homebrew/opt/molten-vk/etc/vulkan/icd.d/MoltenVK_icd.json
DXVK_ASYNC=1
```

Used for DirectX through Vulkan/MoltenVK.

### DXVK only

```sh
WINEDLLOVERRIDES=dxgi,d3d9,d3d10core,d3d11,user32=n,b
DXVK_ASYNC=1
```

### VKD3D only

```sh
WINEDLLOVERRIDES=d3d12,dxgi,user32=n,b
```

### D3DMetal / GPTK

Typical values:

```sh
DYLD_LIBRARY_PATH=<GPTK lib/external>:<GPTK lib>
WINEDLLPATH=<GPTK wine/lib/wine/x86_64-windows>
WINEDLLOVERRIDES=dxgi,d3d9,d3d10core,d3d11,d3d12=n,b;user32=n,b
```

Forge may use GPTK's `wine64` for D3DMetal-specific launches when available.

### Wine builtin fallback

```sh
WINEDLLOVERRIDES=*dxgi,*d3d8,*d3d9,*d3d10core,*d3d11,*d3d12,*d3d12core=b;user32=n,b;mscoree,mshtml=
WINE_D3D_CONFIG=renderer=gl
LIBGL_ALWAYS_SOFTWARE=1
```

This is a last-resort compatibility mode and should not be the default for performance-sensitive games.

## Steam safe mode variables

Steam's Chromium UI can be fragile under DXVK/D3DMetal. Forge can launch Steam in a safe builtin mode while passing the intended game backend through `FORGE_GAME_*` variables:

| Variable | Meaning |
|---|---|
| `FORGE_STEAM_SAFE_MODE=1` | Marks Steam UI safe mode |
| `FORGE_GAME_WINEDLLOVERRIDES` | Backend DLL overrides for child game EXEs |
| `FORGE_GAME_WINE_D3D_CONFIG` | Game WineD3D renderer config, e.g. `renderer=vulkan` |
| `FORGE_GAME_LIBGL_ALWAYS_SOFTWARE` | Game GL software fallback flag when intentionally needed |
| `FORGE_GAME_VK_ICD_FILENAMES` | Game MoltenVK ICD path |
| `FORGE_GAME_VK_DRIVER_FILES` | Game Vulkan driver file path |
| `FORGE_GAME_MTL_HUD_ENABLED` | Game Metal HUD setting |
| `FORGE_GAME_MTL_HUD_LAYER` | Game Metal HUD layer toggle |
| `FORGE_GAME_DXVK_ASYNC` | Game DXVK async toggle when DXVK is selected |
| `FORGE_GAME_DYLD_LIBRARY_PATH` | Game D3DMetal native libs |
| `FORGE_GAME_WINEDLLPATH` | Game Wine DLL path |

The custom Forge Wine patch is expected to restore these for non-Steam child EXEs.

## Experimental loader stack handling

`FORGE_STACK_GUARANTEE_BYTES` enables a Forge Wine patch for loaders that run exception-handler code while the guest stack is already at the final stack page. Current Overwatch investigation uses:

```sh
FORGE_STACK_GUARANTEE_BYTES=262144
```

Current status: this avoids the original immediate `virtual_setup_exception stack overflow` abort and avoids the later 100% CPU loader-lock spin in direct tests, but Overwatch still exits before rendering. Keep it per-game/diagnostic until the remaining loader path is fixed.

## Steam App IDs

Steam game entries detected from manifests are launched through Windows Steam when possible:

```sh
steam.exe -applaunch <appid> <launch options>
```

Direct diagnostic launches may also set:

```sh
SteamAppId=<appid>
SteamGameId=<appid>
```

but this is not enough for many Steamworks games. If logs show `SteamAPI_Init() failed`, launch through Windows Steam in the main bottle.

## Metal HUD

```sh
MTL_HUD_ENABLED=1
MTL_HUD_LAYER=1
```

The HUD applies on the next launch and only appears for Metal-backed rendering. It may not appear for Steam's UI, WineD3D/OpenGL, or games that fail before creating a Metal device.

## Config merge order

```text
process environment
  -> backend default env
  -> AppConfig.env
  -> RuntimeProfile.env
  -> BottleEntry.envOverrides
  -> GameCompatibilityProfile.env
  -> backend-specific safety cleanup
```

Later values override earlier values. Direct game launches clear Steam-only filters such as `DXVK_FILTER_DEVICE_NAME`.

## Unity compatibility launch options

These are command-line arguments, not environment variables, but they are important enough to track with runtime settings:

```text
-force-vulkan
-force-gfx-st
-disable-gpu-skinning
-screen-fullscreen 1
```

`-disable-gpu-skinning` can fix avatar/character mesh corruption in some Unity games under MoltenVK. PEAK currently uses all four options in Forge's per-game launch profile.
