# Native SwiftUI App

Forge's active frontend is the macOS 26 SwiftUI app in:

```text
macos/ForgeNative
```

The previous Svelte/Tauri UI is legacy/reference code. New UI work should happen in SwiftUI unless the project explicitly reactivates Tauri.

## Run

```sh
npm run native:dev
```

This builds and opens `dist/Forge.app`, giving Forge a Dock/Cmd-Tab identity and app icon.

## Build

```sh
npm run native:build
```

## Current UI features

- native SwiftUI glass-style layout
- bottle status sidebar
- graphics backend picker
- Metal HUD toggle
- drag/drop `.exe`
- Finder **Select EXE**
- installed app/Steam game list
- per-game compatibility profile badges
- per-game profile editor for backend, launch args, env, notes, and reset
- Play/Stop buttons
- Reveal bottle folder
- Refresh/rescan

## Design rules

- Keep the UI clean and native, not web-like.
- Avoid decorative controls that are not wired to actions.
- Prefer system font/weights over overly rounded/heavy text.
- Use glass/material subtly; no colorful fake gradient background.
- All game/launcher actions should flow through `ForgeStore`.

## Implementation note

The app entry lives in:

```text
macos/ForgeNative/Sources/ForgeNative/ForgeNativeApp.swift
```

Main store state and high-level actions have been split into:

```text
macos/ForgeNative/Sources/ForgeNative/ForgeStore.swift
```

The main library shell has been split into:

```text
macos/ForgeNative/Sources/ForgeNative/ForgeContentView.swift
```

The profile editor has been split into:

```text
macos/ForgeNative/Sources/ForgeNative/GameProfileEditorSheet.swift
```

Shared SwiftUI cards and controls have been split into:

```text
macos/ForgeNative/Sources/ForgeNative/ForgeUIComponents.swift
```

Shared visual styles have been split into:

```text
macos/ForgeNative/Sources/ForgeNative/ForgeVisualStyles.swift
```

App list row views have been split into:

```text
macos/ForgeNative/Sources/ForgeNative/ForgeAppRow.swift
```

macOS app/window setup has been split into:

```text
macos/ForgeNative/Sources/ForgeNative/ForgeAppDelegate.swift
```

Per-game compatibility profile models and store actions have been split into:

```text
macos/ForgeNative/Sources/ForgeNative/GameCompatibilityProfiles.swift
```

Core config/runtime/app models have been split into:

```text
macos/ForgeNative/Sources/ForgeNative/ForgeModels.swift
```

Config/runtime/bottle persistence helpers have been split into:

```text
macos/ForgeNative/Sources/ForgeNative/ForgePersistence.swift
```

Bottle EXE and Steam manifest scanning have been split into:

```text
macos/ForgeNative/Sources/ForgeNative/ForgeAppScanner.swift
```

MoltenVK/GPTK path resolution and graphics environment helpers have been split into:

```text
macos/ForgeNative/Sources/ForgeNative/ForgeGraphicsEnvironment.swift
```

Launch/runtime support and process orchestration have been split into:

```text
macos/ForgeNative/Sources/ForgeNative/ForgeLaunchSupport.swift
```

Runtime DLL staging helpers have been split into:

```text
macos/ForgeNative/Sources/ForgeNative/ForgeRuntimeStaging.swift
```

`ForgeStore.swift` still includes high-level launch requests, backend selection, and HUD/bottle actions. Keep extracting isolated pieces as compatibility work stabilizes.
