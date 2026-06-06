# Handoff

## Current status

Forge Launcher is now focused on the macOS 26 native SwiftUI app in `macos/ForgeNative`.

Use:

```sh
npm run native:dev
npm run native:build
```

The old Svelte/Tauri UI remains in the repo as legacy/reference code only.

## Recent native work

- Added native SwiftUI glass-style UI.
- Added app icon and `.app` wrapper for Dock/Cmd-Tab.
- Removed unwired web-style controls.
- Added drag/drop `.exe` and Finder **Select EXE**.
- Added Play/Stop behavior using `wineserver -k`.
- Added Metal HUD toggle.
- Added graphics backend picker.
- Added Steam manifest scanning so installed Steam games appear as single entries.
- Hid helper EXEs and launcher-managed child EXEs.

## PEAK status

PEAK is still not confirmed working. Observed failures:

- DXVK/MoltenVK: DXVK adapter rejection / `dxgi` crash.
- D3DMetal attempts: launch issues around GPTK/Wine DLL pairing.
- WineD3D/OpenGL: grey screen and not desired.

Latest direction: use GPTK `wine64` for D3DMetal launches rather than mixing Forge Wine with GPTK DLLs. Local staged D3D DLL copies were removed because Wine could not resolve them correctly.

Check latest logs in:

```text
~/Library/Application Support/com.forgelauncher.app/Logs/
```

## Important files

- `macos/ForgeNative/Sources/ForgeNative/ForgeNativeApp.swift`
- `macos/ForgeNative/Package.swift`
- `scripts/run-native-app.sh`
- `docs/ARCHITECTURE.md`
- `docs/SETUP.md`
- `docs/RUNTIME_PROFILES.md`
- `docs/STEAM.md`
