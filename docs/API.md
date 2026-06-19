# API Reference

Forge's active frontend is the native SwiftUI app in `macos/ForgeNative`. There is no public HTTP or IPC API for the current app.

This document replaces the old Tauri command API reference. The previous Svelte/Tauri command surface still exists in `src-tauri/` as legacy/reference code, but it is not the primary integration point.

## Current native entry points

| Area | Swift location |
|---|---|
| Load config | `ForgePersistence.swift` / `ForgeStore.loadConfig(from:)` |
| Save config | `ForgePersistence.swift` / `ForgeStore.saveConfig(_:to:)` |
| Load bottles | `ForgePersistence.swift` / `ForgeStore.loadBottles(from:config:)` |
| Save bottle backend | `ForgePersistence.swift` / `ForgeStore.saveBottle(_:to:config:)` |
| Load game profiles | `ForgeStore.loadGameProfiles(from:)` |
| Save game profiles | `ForgeStore.saveGameProfiles(_:to:)` |
| Scan launchable apps | `ForgeAppScanner.swift` / `ForgeStore.scanApps(prefixPath:)` |
| Scan Steam manifests | `ForgeAppScanner.swift` / `ForgeStore.scanSteamGames(prefixPath:into:seen:)` |
| Launch EXE | `ForgeStore.swift` / `ForgeStore.launch(_:)` |
| Spawn Wine process | `ForgeLaunchSupport.swift` / `ForgeStore.spawn(...)` |
| Stop bottle session | `ForgeLaunchSupport.swift` / `ForgeStore.stopWineSession(...)` |

## Runtime JSON schema notes

ForgeNative uses the same Application Support folder:

```text
~/Library/Application Support/com.forgelauncher.app/
```

Main files:

- `config.json`
- `bottles.json`
- `runtime_profiles.json`
- `game_compatibility_profiles.json`

Core Swift models live in `ForgeModels.swift`:

- `AppConfig`
- `RuntimeProfile`
- `BottleEntry`
- `BottleAppItem`
- `GraphicsBackend`

Per-game compatibility profile models, store actions, and seeded-profile helpers live in `GameCompatibilityProfiles.swift`.
Profile editor text parsers live in `GameProfileTextParsing.swift`.

## Legacy Tauri API

If you need to inspect the old API, read the Rust commands under `src-tauri/src/`. Treat them as historical implementation details until the project explicitly reintroduces Tauri.
