# API Reference

Forge's active frontend is the native SwiftUI app in `macos/ForgeNative`. There is no public HTTP or IPC API for the current app.

This document replaces the old Tauri command API reference. The previous Svelte/Tauri command surface still exists in `src-tauri/` as legacy/reference code, but it is not the primary integration point.

## Current native entry points

| Area | Swift location |
|---|---|
| Load config | `ForgeStore.loadConfig(from:)` |
| Save config | `ForgeStore.saveConfig(_:to:)` |
| Load bottles | `ForgeStore.loadBottles(from:config:)` |
| Save bottle backend | `ForgeStore.saveBottle(_:to:config:)` |
| Scan launchable apps | `ForgeStore.scanApps(prefixPath:)` |
| Scan Steam manifests | `ForgeStore.scanSteamGames(prefixPath:into:seen:)` |
| Launch EXE | `ForgeStore.launch(_:)` |
| Spawn Wine process | `ForgeStore.spawn(...)` |
| Stop bottle session | `ForgeStore.stopWineSession(...)` |

## Runtime JSON schema notes

ForgeNative uses the same Application Support folder:

```text
~/Library/Application Support/com.forgelauncher.app/
```

Main files:

- `config.json`
- `bottles.json`
- `runtime_profiles.json`

Swift models live at the bottom of `ForgeNativeApp.swift`:

- `AppConfig`
- `RuntimeProfile`
- `BottleEntry`
- `BottleAppItem`
- `GraphicsBackend`

## Legacy Tauri API

If you need to inspect the old API, read the Rust commands under `src-tauri/src/`. Treat them as historical implementation details until the project explicitly reintroduces Tauri.
