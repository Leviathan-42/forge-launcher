# Handoff 2

## Summary

The project has moved away from the old Svelte/Tauri UI. The active app is the native macOS 26 SwiftUI frontend in `macos/ForgeNative`.

## What changed

- Native `.app` wrapper via `scripts/run-native-app.sh`.
- SwiftUI UI replaces web UI work.
- Drag/drop and Select EXE are the primary add/run actions.
- Steam install/open buttons were removed from the main UI.
- Steam games are detected from Windows Steam manifests and shown as single launchable entries.
- Helper EXEs are hidden.
- Metal HUD is toggleable.
- Backend selection is exposed in the sidebar.
- Play changes to Stop after launch.

## PEAK debugging notes

Observed:

- Steam-owned launch reached loading but froze.
- Direct DXVK/VKD3D launch hit DXVK/MoltenVK adapter problems and `dxgi` crashes.
- D3DMetal with copied/staged DLLs caused loader failures.
- WineD3D/OpenGL produced grey-screen behavior and is not desired.

Current experiment:

- PEAK override remains D3DMetal.
- D3DMetal launches should prefer GPTK's own `wine64` rather than mixing Forge Wine with GPTK builtin DLL copies.
- Staged D3D DLL files next to `PEAK.exe` were removed.

## Next steps

1. Run `npm run native:dev`.
2. Launch PEAK from Forge.
3. Inspect newest non-empty log in Application Support.
4. Confirm whether the launch uses GPTK `wine64` and whether `DXVK` still appears in the log.
5. If DXVK appears during D3DMetal launch, D3DMetal DLL resolution is still wrong.
