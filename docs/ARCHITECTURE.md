# Architecture

Forge Launcher is now a macOS-native SwiftUI app. The old Svelte/Tauri UI is kept only as legacy/reference code while the active product lives in `macos/ForgeNative`.

Forge is very experimental. The current runtime work builds on open-source Wine code, including Wine sources published with CodeWeavers/CrossOver releases, plus Forge-specific launcher/runtime patches.

## Current app model

```text
Forge.app / ForgeNative
  -> SwiftUI Liquid Glass-style UI
  -> ForgeStore reads JSON config from Application Support
  -> one main Wine bottle for Windows Steam and installed games
  -> Forge-owned WoW64 Wine runtime profile resolver
  -> Steam safe UI launch + game backend handoff
  -> DXVK/VKD3D/MoltenVK, DXMT, GPTK D3DMetal, or Wine builtin backend
```

## Important paths

| Path | Purpose |
|---|---|
| `macos/ForgeNative/Sources/ForgeNative/ForgeNativeApp.swift` | Active SwiftUI app, store, scanning, launch logic |
| `macos/ForgeNative/Sources/ForgeNative/ForgeUIComponents.swift` | Shared SwiftUI cards, rows, styling, backend display text |
| `macos/ForgeNative/Sources/ForgeNative/ForgeModels.swift` | Core config, bottle, app, backend models and JSON helpers |
| `macos/ForgeNative/Sources/ForgeNative/GameCompatibilityProfiles.swift` | Per-game compatibility profile model, seeds, reset, parsing |
| `macos/ForgeNative/Sources/ForgeNative/GameProfileEditorSheet.swift` | Native profile editor UI |
| `macos/ForgeNative/Package.swift` | Swift package targeting macOS 26 |
| `scripts/run-native-app.sh` | Builds and opens `dist/Forge.app` for Cmd-Tab/Dock behavior |
| `~/Library/Application Support/com.forgelauncher.app/` | Runtime config, bottles, profiles, logs |
| `src-tauri/` | Legacy Rust/Tauri backend reference |
| `src/` | Legacy Svelte frontend reference |

## Runtime data files

ForgeNative reads and writes:

- `config.json` — global Wine/GPTK paths, HUD setting, env overrides
- `bottles.json` — Wine bottles and selected graphics backend
- `runtime_profiles.json` — Wine runner paths, MoltenVK/DXVK/VKD3D/GPTK paths
- `Logs/swiftui-launch-*.log` — per-launch Wine stdout/stderr

## Launch flow

```text
User drops/selects an .exe or clicks Play
  -> ForgeStore resolves selected BottleEntry
  -> RuntimeProfile supplies Wine path and backend resources
  -> graphics backend builds env + DLL overrides
  -> Wine starts the Windows app
  -> UI switches Play to Stop
```

## Steam handling

Steam itself is treated as a launcher. Steam's Chromium UI is launched in a safer builtin/WineD3D mode, while games use the selected game backend through the patched `FORGE_GAME_*` handoff.

Forge also scans Windows Steam manifests in the main bottle and exposes installed Steam games as single launchable entries. Helper EXEs such as `steamwebhelper.exe`, crash handlers, uninstallers, and secondary launcher-managed EXEs are hidden. Steam games should not need separate per-game bottles for normal use.

## Graphics backends

| Backend | Purpose |
|---|---|
| `dxvk_vkd3d` | Default experimental Vulkan path through DXVK/VKD3D + MoltenVK |
| `dxvk` | D3D9/10/11 through DXVK + MoltenVK |
| `vkd3d` | D3D12 through VKD3D-Proton + MoltenVK |
| `d3dmetal` | GPTK/D3DMetal path |
| `dxmt` | D3D11 to Metal path; currently used for Against the Storm |
| `wine_builtin` | Compatibility fallback; avoid for performance-sensitive games |
| `none` | No D3D override |

## Native UI responsibilities

- Bottle status and selected backend
- Drag/drop or Finder-select `.exe`
- Installed app/game scan
- Metal HUD toggle
- Graphics backend selector
- Play/Stop controls
- Reveal bottle folder
- Rescan library

## Legacy code note

The old Tauri/Svelte app is not the primary frontend anymore. Do not add new UI features there unless explicitly reviving the legacy app.
