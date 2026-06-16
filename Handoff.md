# Handoff

## Current focus

Forge is an experimental macOS launcher/runtime. The launcher/app code is vibe coded; runtime work builds on upstream open-source Wine code, including Wine sources published with CodeWeavers/CrossOver releases, plus Forge-specific patches.

User goals/preferences:

- One main user-visible bottle, not one bottle per game.
- Own/open-source stack where possible; do **not** send the user to Whisky/CrossOver as the solution.
- External paid/abandoned runtimes are not acceptable as product direction.
- Per-game graphics/backend switching is desired and now partially implemented.
- User prefers direct game launches during debugging instead of repeatedly restarting the whole Forge app.
- Important: do not leave Wine/Steam test processes around. A previous Overwatch loop left 936 Wine/Windows child processes (~19 GB RSS). Always run `npm run kill` before/after bounded launch experiments.

Active app code:

```text
macos/ForgeNative/Sources/ForgeNative/ForgeNativeApp.swift
```

Run/build:

```sh
npm run native:dev
npm run native:build
npm run kill
npm run doctor
scripts/overwatch-test-once.sh dxvk 30
```

Latest build status:

```text
npm run native:build
Build complete
```

Latest pushed commits:

```text
c05213a Document Overwatch investigation state
0ea46b4 Add bounded Wine cleanup helpers
bc5d3cd Improve Forge launch profiles and diagnostics
```

Current git status at handoff: clean.

## Current working model

Main bottle:

```text
~/Wine/Bottles/default
```

Forge-owned WoW64 runtime:

```text
~/Wine/Runtimes/forge-cx-wine-11-open-wow64/bin/wine
~/Wine/Runtimes/forge-cx-wine-11-open-wow64/bin/wineserver
```

DXMT downloaded/runtime files:

```text
~/Wine/Runtimes/dxmt-v0.80/v0.80/x86_64-windows
~/Wine/Runtimes/dxmt-v0.80/v0.80/i386-windows
~/Wine/Runtimes/dxmt-v0.80/v0.80/x86_64-unix/winemetal.so
```

DXVK versions downloaded during testing:

```text
~/Wine/Runtimes/dxvk-2.7.1/dxvk-2.7.1
~/Wine/Runtimes/dxvk-1.10.3/dxvk-1.10.3
```

Windows Steam is installed inside the default bottle. Steam games normally launch through:

```text
steam.exe -applaunch <appid>
```

Steam's UI runs in a safe builtin/WineD3D path, with Forge-specific `FORGE_GAME_*` env intended to restore game graphics settings for Steam child processes. This handoff focuses on direct game launch validation; Steam auth may be absent when launching direct.

## Code changes implemented

Main file changed:

```text
macos/ForgeNative/Sources/ForgeNative/ForgeNativeApp.swift
```

Implemented/changed:

- Per-game graphics backend picker in the app list.
- Persistent game compatibility profiles saved at:
  ```text
  ~/Library/Application Support/com.forgelauncher.app/game_compatibility_profiles.json
  ```
- Effective backend priority:
  ```text
  per-game override -> bottle backend -> runtime profile default
  ```
- Seeded profiles now include:
  - Against the Storm (`steam:1336490`) -> `dxmt`
  - Among Us (`steam:945360`) -> `wine_builtin` with WineD3D Vulkan env
  - PEAK (`name:peak`) -> `dxvk_vkd3d`
- Added actual DXMT setup path:
  - `ensureDXMTInstalled(winePath:prefixPath:)`
  - copies DXMT x64 PE DLLs to Forge runtime and `system32`
  - copies DXMT x86 PE DLLs to Forge runtime `i386-windows` and `syswow64`
  - copies `winemetal.so` into runtime `x86_64-unix`
  - creates Unity `dd3d11.dll` alias from `d3d11.dll`
- DXMT backend env:
  ```text
  WINEDLLOVERRIDES=dd3d11,d3d11,dxgi,d3d10core=b;user32=n,b;mscoree,mshtml=
  ```
- DXMT clears Vulkan/DXVK env to avoid cross-contamination.
- WineD3D backend now removes app-local staged D3D/DXGI DLLs via `removeStagedD3DMetalDlls()`.
- Added consumer-facing graphics backend guide in the sidebar:
  - DirectX 9 -> DXVK first
  - DirectX 10/11 -> DXVK first; DXMT if DXVK/Vulkan fails
  - DirectX 12 -> VKD3D or D3DMetal
  - Vulkan/OpenGL -> None/WineD3D only if the game supports it
  - Fallback -> WineD3D
- Steam/game launch logs include `FORGE_GAME_*` handoff vars and Metal HUD vars.
- Game launch uses direct `wine exe.exe` instead of `wine start /unix exe.exe`; this was changed to preserve env propagation.
- DXVK/DXVK-VKD3D backends stage app-local DXVK DLLs into Steam game directories when needed, via `ensureDXVKInstalled(...)`.
- Removed the user-visible `Forge optimized` badge after user disliked it.
- Metal HUD toggle now sets `MTL_HUD_ENABLED`, `MTL_HUD_LAYER`, and global `MetalForceHudEnabled`; user still did not see HUD in D3DMetal/DXMT tests.
- Added robust cleanup:
  - `npm run kill` / `scripts/forge-kill.sh` now kills Windows path-shaped Wine children like `C:\windows\system32\conhost.exe`.
  - `scripts/overwatch-test-once.sh` runs bounded Overwatch tests and cleans before/after to avoid hundreds of Wine processes.

## Saved compatibility profiles currently set

File:

```text
~/Library/Application Support/com.forgelauncher.app/game_compatibility_profiles.json
```

Important current entries:

```json
[
  {
    "id": "steam:1336490",
    "display_name": "Against the Storm",
    "backend_override": "dxmt",
    "launch_args": ["-screen-fullscreen", "1"]
  },
  {
    "id": "steam:945360",
    "display_name": "Among Us",
    "backend_override": "wine_builtin",
    "launch_args": [],
    "env": {
      "WINE_D3D_CONFIG": "renderer=vulkan",
      "WINEDLLOVERRIDES": "*dxgi,*d3d8,*d3d9,*d3d10core,*d3d11,*d3d12,*d3d12core=b;vulkan-1,winevulkan=b;mscoree,mshtml=",
      "VK_ICD_FILENAMES": "/opt/homebrew/share/vulkan/icd.d/MoltenVK_icd.json",
      "VK_DRIVER_FILES": "/opt/homebrew/share/vulkan/icd.d/MoltenVK_icd.json"
    }
  },
  {
    "id": "name:peak",
    "display_name": "PEAK",
    "backend_override": "dxvk_vkd3d",
    "launch_args": ["-force-vulkan", "-force-gfx-st", "-disable-gpu-skinning", "-screen-fullscreen", "1"]
  },
  {
    "id": "steam:2357570",
    "display_name": "Overwatch 2",
    "backend_override": "dxvk_vkd3d",
    "launch_args": []
  }
]
```

## Working game: Against the Storm

Game:

```text
Against the Storm
Steam appid: 1336490
Install dir: ~/Wine/Bottles/default/drive_c/Program Files (x86)/Steam/steamapps/common/Against the Storm
Unity: 2021.3.45f2
```

Working backend:

```text
DXMT (D3D11 -> Metal)
```

Critical details:

- Against the Storm is 64-bit D3D11-only Unity.
- Unity has a weird literal `dd3d11.dll` lookup/string. Adding `dd3d11.dll` alias is important.
- DXVK failed due to MoltenVK missing/insufficient features for this title, especially geometryShader issues.
- D3DMetal/GPTK paths were unstable/messy and should not be the default direction.
- DXMT installed/staged into Forge runtime and system32 got it past D3D11 initialization.

Successful direct launch evidence:

```text
~/Library/Application Support/com.forgelauncher.app/Logs/manual-against-dxmt-system-start-final-20260616T062053Z.log
~/Wine/Bottles/default/drive_c/users/forge/AppData/LocalLow/Eremite Games/Against the Storm/Player.log
```

Player log reached:

```text
[Scene] MainController ... releasing loading screen
Loading completed
```

Remaining direct-launch error is Steam callback/DLC/auth related because the game was launched directly without Steam, not a graphics failure:

```text
InvalidOperationException: Callback dispatcher is not initialized.
```

## Working game: PEAK

PEAK works from the main default bottle through Windows Steam using Forge WoW64 runtime.

Working profile:

```text
backend: DXVK/VKD3D
launch args: -force-vulkan -force-gfx-st -disable-gpu-skinning -screen-fullscreen 1
```

Why:

- PEAK works on Unity's native Vulkan path.
- `-disable-gpu-skinning` fixed avatar/mesh corruption.
- It is not actually using DirectX when `-force-vulkan` succeeds; the DXVK/VKD3D backend is mostly the bottle setting around it.

## Working game: Among Us

Game:

```text
Among Us
Steam appid: 945360
Install dir: ~/Wine/Bottles/default/drive_c/Program Files (x86)/Steam/steamapps/common/Among Us
Unity: 2022.3.44f1
Executable: PE32 Intel 80386 (32-bit)
```

Working backend/path found:

```text
WineD3D + Vulkan renderer
```

Direct launch command shape that worked:

```sh
PREFIX="$HOME/Wine/Bottles/default"
R="$HOME/Wine/Runtimes/forge-cx-wine-11-open-wow64"
GAME="$PREFIX/drive_c/Program Files (x86)/Steam/steamapps/common/Among Us/Among Us.exe"
GD="$(dirname "$GAME")"

# Important: no app-local DXMT/DXVK DLLs for WineD3D test
rm -f "$GD"/{d3d11.dll,dd3d11.dll,dxgi.dll,d3d10core.dll,winemetal.dll,d3d9.dll,d3d12.dll}

cd "$GD"
env \
  WINEPREFIX="$PREFIX" \
  WINEDEBUG="fixme-all" \
  WINEDBG="-all" \
  SteamAppId=945360 \
  SteamGameId=945360 \
  DYLD_LIBRARY_PATH="$R/lib:/opt/homebrew/lib" \
  DYLD_FALLBACK_LIBRARY_PATH="$R/lib:/opt/homebrew/lib:/usr/local/lib" \
  WINEDLLOVERRIDES="*dxgi,*d3d8,*d3d9,*d3d10core,*d3d11,*d3d12,*d3d12core=b;vulkan-1,winevulkan=b;mscoree,mshtml=" \
  VK_ICD_FILENAMES="/opt/homebrew/share/vulkan/icd.d/MoltenVK_icd.json" \
  VK_DRIVER_FILES="/opt/homebrew/share/vulkan/icd.d/MoltenVK_icd.json" \
  WINE_D3D_CONFIG="renderer=vulkan" \
  "$R/bin/wine" "$GAME"
```

Successful evidence:

```text
~/Library/Application Support/com.forgelauncher.app/Logs/manual-among-wined3d-vulkan-20260616T070554Z.log
~/Wine/Bottles/default/drive_c/users/forge/AppData/LocalLow/Innersloth/Among Us/Player.log
```

Player log reached main/menu-ish game state:

```text
Direct3D:
    Version:  Direct3D 11.0 [level 11.1]
    Renderer: Apple M5 (ID=0x0)
    Vendor:   Unknown (ID=106b)
    VRAM:     901 MB
...
[AmongUsClient::OnActiveSceneChange()] Scene change detected.
```

Process was running:

```text
C:\Program Files (x86)\Steam\steamapps\common\Among Us\Among Us.exe
```

User confirmed it launched, but direct launch had no Steam auth. This is expected because it was not launched through Steam.

### Among Us paths tested and rejected

#### DXMT

Not viable in current Forge WoW64 runtime for Among Us.

Why:

- Among Us is 32-bit (`PE32 Intel 80386`).
- DXMT x86 PE DLLs exist, but this runtime has no `x86_32on64-unix` side equivalent for DXMT; the 32-bit builtin/native load path repeatedly failed.
- Logs showed `d3d11.dll` load failure / `dd3d11.dll` failure for DXMT attempts:
  ```text
  d3d11: could not load dd3d11.dll
  d3d11: failed to load directx dlls (80029c4a)
  ```
- Copying x64 DXMT DLLs app-local caused arch mismatch:
  ```text
  open_dll_file ... d3d11.dll is for arch 8664, continuing search
  ```
- Copying i386 DXMT files app-local/system32/syswow64 still failed under the new WoW64 load path.

#### DXVK 2.7.1 x32

Not viable.

- Initially failed because Vulkan driver path was not loaded correctly:
  ```text
  DXVK: No adapters found
  Failed to initialize DXVK
  ```
- With `vulkan-1,winevulkan=b`, Vulkan loaded but DXVK 2.x requires Vulkan 1.3 and/or features that did not produce a working adapter.

#### DXVK 1.10.3 x32

Closer but still not viable.

- DXVK 1.10.3 found Apple M5/MoltenVK.
- Config tried:
  ```text
  d3d11.maxFeatureLevel = 11_0
  ```
- Still failed:
  ```text
  D3D11CoreCreateDevice: Requested feature level not supported
  d3d11: failed to create device and context (80070057)
  ```

#### Unity native Vulkan/OpenGL flags

Not viable.

Commands/args tested:

```text
-force-vulkan
-force-opengl
-force-glcore
```

Player logs:

```text
Forced GfxDevice 'Vulkan' was not built from editor, shaders will not be available
InitializeEngineGraphics failed
```

```text
Forced GfxDevice 'OpenGL Core' was not built from editor, shaders will not be available
InitializeEngineGraphics failed
```

## Additional first-try game results

User reported these launched first try through Forge, which is important validation of the default product path:

```text
Slime Rancher
ULTRAKILL
```

No Metal HUD appeared for ULTRAKILL on D3DMetal or Slime Rancher on DXMT, even with Forge setting HUD env/defaults.

## Important runtime/prefix mutation notes

The default prefix has been heavily modified during debugging. Before testing a game/backend, remove app-local DLLs that could shadow the intended backend:

```sh
GAME_DIR="~/Wine/Bottles/default/drive_c/Program Files (x86)/Steam/steamapps/common/<Game>"
rm -f "$GAME_DIR"/{d3d11.dll,dd3d11.dll,dxgi.dll,d3d10core.dll,winemetal.dll,d3d9.dll,d3d12.dll}
```

Known backup from earlier D3D/DXGI replacement experiments:

```text
~/Library/Application Support/com.forgelauncher.app/Backups/system32-d3d-before-gptk-20260616T060453Z
~/Library/Application Support/com.forgelauncher.app/Backups/forge-runtime-d3d-before-dxmt-20260616T061700Z
```

Current system32/syswow64 may contain staged DXMT files from testing. WineD3D backend now removes app-local D3D DLLs, but system32/syswow64 staging may still exist.

Current runtime cleanup state:

- Forge runtime `ntdll.so` was restored from backup after failed emergency-stack experiments.
- Do **not** leave CrossOver proprietary `cxcompatdb.so`, `compatdb-26.dat`, or copied `share/crossover` data in the Forge runtime. A reference test copied them briefly, failed signature checks, and they were removed.
- Keep DXVK app-local DLLs in Overwatch if testing DXVK, but remove app-local D3D DLLs before WineD3D/DXMT/D3DMetal tests.

## Current caveats / next tasks

### Overwatch current investigation

Steam appid `2357570` currently starts `Overwatch.exe` but no window appears. Use bounded tests only:

```sh
npm run kill
scripts/overwatch-test-once.sh dxvk 30
npm run kill
```

Do not run open-ended loops. The helper kills Wine/Steam before and after each bounded run.

Findings so far:

- CrossOver app profile for Overwatch uses `win7_64` and dependencies Core Fonts + VC++ 2005/2008 x64; those DLLs/fonts are present in the Forge bottle.
- CrossOver/Wine sources have an Overwatch-specific `KernelCallbackTable`/`user32.dll` patch in `include/ntuser.h`; Forge runtime callback-table entries were verified to point inside `user32.dll`.
- DXVK app-local staging works (`dxgi.dll`/`d3d11.dll` native load from game directory).
- D3DMetal, WineD3D Vulkan/GL, win7/win10 app defaults, no-sync, and thread-count/windowed args have not opened a window.
- Consistent original failure: `Overwatch_loader.dll` triggers `EXCEPTION_STACK_OVERFLOW`/`virtual_setup_exception stack overflow` before rendering.
- Experimental ntdll emergency-stack patches got past the immediate abort but caused a CPU spin in `__wine_syscall_dispatcher`/loader lock, so they were reverted and the runtime ntdll was restored from backup.
- One sample during the emergency-stack experiment showed Overwatch at ~100% CPU, stuck under `__wine_syscall_dispatcher`/`segv_handler`/loader-related code; no window appeared.
- Do not copy/use CrossOver proprietary `cxcompatdb.so`/compatdb as product direction. A reference test with it failed signature checks and did not fix the loader.
- CrossOver's Overwatch app profile in `crossover.tie` is for `win7_64`; that is a compatibility lie/profile, not a recommendation that Windows 7 is modern. Testing both win7 and win10 did not fix the current loader issue.

Useful Overwatch logs/samples from latest work:

```text
~/Library/Application Support/com.forgelauncher.app/Logs/manual-overwatch-emergency-nodebug-20260616T151604Z.log
~/Library/Application Support/com.forgelauncher.app/Logs/overwatch-sample-64047.txt
```

Next useful work: inspect the `Overwatch_loader.dll` exception/VEH path and Wine's `KiUserExceptionDispatcher`/stack-overflow dispatch semantics rather than swapping graphics backends.

1. **Steam auth handoff for Among Us**
   - Direct WineD3D/Vulkan launch works but has no Steam auth.
   - Need to verify launching via `steam.exe -applaunch 945360` correctly applies the Among Us WineD3D/Vulkan child-game env.
   - If Steam child env propagation fails, fix Forge's `FORGE_GAME_*` application in the runtime/wrapper.

2. **Metal HUD**
   - User reported no Metal HUD across games.
   - Check `MTL_HUD_ENABLED` propagation, especially Steam child launches.
   - Add launch-log lines for effective backend, `MTL_HUD_ENABLED`, child `FORGE_GAME_MTL_HUD_ENABLED`.

3. **Clean product behavior**
   - Keep one visible default bottle.
   - Use per-game profiles instead of telling user to create separate bottles.
   - Do not route users to Whisky/CrossOver.

4. **Backend recommendations to preserve**
   - Against the Storm: DXMT.
   - PEAK: native Vulkan via launch args, profile backend DXVK/VKD3D.
   - Among Us: WineD3D with `renderer=vulkan`, not DXMT/DXVK.

## Log paths to inspect

Forge launch logs:

```text
~/Library/Application Support/com.forgelauncher.app/Logs/
```

Against the Storm player logs:

```text
~/Wine/Bottles/default/drive_c/users/forge/AppData/LocalLow/Eremite Games/Against the Storm/Player.log
~/Wine/Bottles/default/drive_c/users/crossover/AppData/LocalLow/Eremite Games/Against the Storm/Player.log
```

Among Us player log:

```text
~/Wine/Bottles/default/drive_c/users/forge/AppData/LocalLow/Innersloth/Among Us/Player.log
```

Useful latest logs:

```text
manual-against-dxmt-system-start-final-20260616T062053Z.log
manual-among-wined3d-vulkan-20260616T070554Z.log
```
