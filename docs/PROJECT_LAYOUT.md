# Project Layout

```text
forge-launcher/
│
├── app-icon.png                         # Source app icon
├── package.json                         # Convenience scripts
├── design.md                            # Product direction
│
├── macos/ForgeNative/                   # Active macOS 26 SwiftUI app
│   ├── Package.swift                    # Swift package manifest
│   └── Sources/ForgeNative/
│       ├── ForgeNativeApp.swift         # UI, store, scanner, launch logic
│       └── Resources/AppIcon.png        # Runtime icon resource
│
├── scripts/
│   ├── run-native-app.sh                # Builds/opens dist/Forge.app
│   ├── setup-macos.sh                   # macOS setup helper
│   ├── build-forge-wine-from-sources.sh # Forge Wine build helper
│   └── test-steam-launch.sh             # Steam diagnostics helper
│
├── docs/
│   ├── ARCHITECTURE.md                  # Native architecture
│   ├── SETUP.md                         # Setup/run guide
│   ├── STEAM.md                         # Windows Steam-in-bottle behavior
│   ├── RUNTIME_PROFILES.md              # Bottle/profile/backend model
│   ├── ENV_VARS.md                      # Launch environment reference
│   ├── NATIVE_SWIFTUI.md                # Native UI notes
│   ├── API.md                           # Legacy Tauri API note
│   └── PROJECT_LAYOUT.md                # This file
│
├── src/                                 # Legacy Svelte frontend reference
├── src-tauri/                           # Legacy Tauri/Rust backend reference
└── config/                              # Sample/reference JSON
```

## Active development path

Use the native app:

```sh
npm run native:dev
npm run native:build
```

`npm run native:dev` creates and opens `dist/Forge.app`, so it appears in Cmd-Tab and the Dock like a normal macOS app.

## Legacy web/Tauri files

These files still exist because they contain useful backend experiments and UI history, but they are not the current frontend:

- `src/App.svelte`
- `src/lib/**`
- `index.html`
- `vite.config.ts`
- `svelte.config.js`
- `src-tauri/**`

Do not update these for new UI behavior unless the project intentionally re-enables the Tauri app.

## Runtime data location

ForgeNative uses:

```text
~/Library/Application Support/com.forgelauncher.app/
  config.json
  bottles.json
  runtime_profiles.json
  Logs/
```

## Adding native UI features

1. Edit `macos/ForgeNative/Sources/ForgeNative/ForgeNativeApp.swift`.
2. Keep controls wired to real `ForgeStore` actions; avoid decorative/unwired buttons.
3. Build with `npm run native:build`.
4. Run with `npm run native:dev`.
5. Update relevant docs.

## Adding launch/runtime behavior

Most launch behavior is currently in `ForgeStore.spawn(...)` inside `ForgeNativeApp.swift`:

- Wine path resolution
- backend-specific env vars
- Steam safe mode
- Metal HUD
- app logs
- Stop via `wineserver -k`

Long term, this can be split into separate Swift files, but the current app is intentionally simple while compatibility is being tested.
