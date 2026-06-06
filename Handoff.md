# Forge Launcher Handoff

## Current goal
Make Forge a free, independent macOS Wine game launcher with a native SwiftUI UI and a Forge-owned Wine 11 runtime.

## Runtime
- Preferred runtime: `~/Wine/Runtimes/forge-wine-11-full/bin/wine`
- Prefix: `~/Wine/Bottles/default`
- Runtime source tree: `~/Downloads/sources/wine`
- Steam webhelper compatibility is implemented in Forge Wine `dlls/kernelbase/process.c` by appending Chromium helper flags only to `steamwebhelper.exe`.

## Important launcher behavior
- Steam itself should launch with the normal bottle graphics backend so Steam-launched games inherit GPU-capable DXVK/VKD3D/D3DMetal settings.
- Do not globally disable Vulkan/DXVK/D3D for Steam; that makes child games inherit slow/unstable WineD3D/OpenGL settings.
- Keep Steam CEF compatibility limited to the Forge Wine process-command patch and Steam command-line args.
- DXVK/VKD3D should use Forge/Homebrew MoltenVK, not GPTK's older external MoltenVK.
- D3DMetal/GPTK DYLD paths should only be injected for the D3DMetal backend.

## Files to know
- Swift UI: `macos/ForgeNative/Sources/ForgeNative/ForgeNativeApp.swift`
- Tauri launcher backend: `src-tauri/src/launcher.rs`
- Runtime config: `src-tauri/src/config.rs`
- Build script: `scripts/build-forge-wine-from-sources.sh`
- Wine Steam patch: `~/Downloads/sources/wine/dlls/kernelbase/process.c`
- Wine crash dialog strings: `~/Downloads/sources/wine/programs/winedbg/winedbg.rc`
- macOS hosted-app plist template: `~/Downloads/sources/wine/loader/wine_info.plist.in`

## Current PEAK issue
PEAK crashed inside `UnityPlayer` on `UnityGfxDeviceWorker` after being launched from a Steam session that had inherited Steam UI safe-mode environment:
- `WINEDLLOVERRIDES=*dxgi,*d3d...=b`
- `WINE_D3D_CONFIG=renderer=gl`
- Vulkan disabled via `/dev/null`

Fix direction: relaunch Steam after removing that inherited environment so PEAK uses the bottle's GPU backend (`dxvk_vkd3d` by default) instead of WineD3D/OpenGL.
