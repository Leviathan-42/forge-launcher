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

Most native code still lives in:

```text
macos/ForgeNative/Sources/ForgeNative/ForgeNativeApp.swift
```

The profile editor has been split into:

```text
macos/ForgeNative/Sources/ForgeNative/GameProfileEditorSheet.swift
```

`ForgeNativeApp.swift` still includes core UI views, config models, scanning, backend resolution, and launch/stop behavior. Keep extracting isolated pieces as compatibility work stabilizes.
