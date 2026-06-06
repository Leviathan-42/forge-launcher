# Handoff

## Active frontend

Forge is currently a macOS 26 SwiftUI app:

```text
macos/ForgeNative
```

Do not treat Svelte/Tauri as the active frontend. `src/` and `src-tauri/` are legacy/reference unless explicitly revived.

## Run/build

```sh
npm run native:dev
npm run native:build
```

`native:dev` builds and opens `dist/Forge.app`.

## Current features

- SwiftUI native UI
- app icon and Cmd-Tab/Dock app wrapper
- selected bottle status
- graphics backend selector
- Metal HUD toggle
- drag/drop `.exe`
- Finder **Select EXE**
- installed app/game scan
- Steam manifest game detection
- Play/Stop controls
- Reveal bottle folder
- Rescan

## Current compatibility work

PEAK is the main test case. It still needs more backend work. Current logs showed failures across DXVK/MoltenVK and mixed Forge Wine + GPTK D3DMetal DLL paths. The newest code uses GPTK `wine64` when D3DMetal is selected and removes staged local D3D DLLs.

## Logs

```text
~/Library/Application Support/com.forgelauncher.app/Logs/swiftui-launch-*.log
```

Use the newest non-empty log.

## Notes

- Avoid OpenGL fallback unless explicitly requested.
- Keep Steam safe mode isolated from game launches.
- Keep visible UI actions wired to real store actions.
