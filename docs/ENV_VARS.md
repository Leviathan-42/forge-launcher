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
| `MTL_HUD_ENABLED` | Apple Metal HUD toggle |

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
| `FORGE_GAME_VK_ICD_FILENAMES` | Game MoltenVK ICD path |
| `FORGE_GAME_MTL_HUD_ENABLED` | Game Metal HUD setting |
| `FORGE_GAME_DYLD_LIBRARY_PATH` | Game D3DMetal native libs |
| `FORGE_GAME_WINEDLLPATH` | Game Wine DLL path |

The custom Forge Wine patch is expected to restore these for non-Steam child EXEs.

## Steam App IDs

Direct Steam game entries detected from manifests get:

```sh
SteamAppId=<appid>
SteamGameId=<appid>
```

This helps some Steamworks games initialize when launched outside the Steam UI.

## Metal HUD

```sh
MTL_HUD_ENABLED=1
```

The HUD applies on the next launch and only appears for Metal-backed rendering. It may not appear for Steam's UI, WineD3D/OpenGL, or games that fail before creating a Metal device.

## Config merge order

```text
process environment
  -> AppConfig.env
  -> RuntimeProfile.env
  -> BottleEntry.envOverrides
  -> backend-specific safety cleanup
```

Later values override earlier values. Direct game launches clear Steam-only filters such as `DXVK_FILTER_DEVICE_NAME`.
