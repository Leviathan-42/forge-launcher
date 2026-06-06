# Native SwiftUI UI

Forge can keep the existing Tauri/Svelte UI while a native macOS SwiftUI shell is developed in parallel.

Current prototype:

- Path: `macos/ForgeNative`
- Reads existing Forge app data from `~/Library/Application Support/com.forgelauncher.app/`
- Uses Forge-owned Wine bottles only
- Shows one bottle and user-visible EXEs
- Gives each app a `Play` button
- Applies the same Steam-safe launch split: Steam UI uses builtin/safe mode; games keep the bottle/profile backend

Run it:

```sh
npm run native:dev
```

Build it:

```sh
npm run native:build
```

This prototype uses Forge-owned/free runtime paths. Keep launcher configuration independent of any paid app runtime or bottle.
