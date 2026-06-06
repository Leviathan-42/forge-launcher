# Forge Launcher Design

Forge is a macOS-native Wine bottle launcher for Windows launchers and apps.

The active frontend is SwiftUI on macOS 26. The old Svelte/Tauri UI is legacy/reference only.

## Product direction

Forge manages Wine prefixes called bottles. A bottle can contain:

- Windows Steam
- Epic Games Launcher
- Battle.net
- EA App
- Ubisoft Connect
- Rockstar Launcher
- standalone `.exe` apps
- games installed by those launchers

The bottle is the core object. Games and launchers are entries inside a bottle.

## Main workflow

```text
Open Forge
  -> select/use bottle
  -> drag/drop .exe or choose Select EXE
  -> or refresh detected installed apps/games
  -> choose graphics backend
  -> toggle Metal HUD if desired
  -> Play
  -> Stop when finished
```

## UI principles

- macOS-native SwiftUI, not HTML/CSS.
- Clean glass/material styling, not a busy web dashboard.
- No fake/unwired buttons.
- Every visible action should do something real.
- Use normal system typography; avoid overly heavy/rounded text.
- Keep the first screen useful, not a marketing page.

## Current native layout

1. Sidebar
   - Forge icon/title
   - selected bottle
   - bottle/app status
   - graphics backend picker
   - Metal HUD toggle
   - refresh action

2. Action cards
   - Add EXE drag/drop
   - Select EXE
   - Reveal bottle folder
   - Rescan apps

3. Apps panel
   - detected launchers/games
   - Steam manifest games as single entries
   - Play/Stop action per row
   - search

## Steam behavior

Windows Steam can live inside a Forge bottle. Steam itself may need a safe UI backend, but games should use the selected game backend.

Forge hides Steam helper EXEs and launcher-managed child EXEs so the app list shows the thing the user actually launches, not every internal executable.

## Graphics backends

Forge supports backend selection per bottle:

- DXVK/VKD3D through MoltenVK
- DXVK through MoltenVK
- VKD3D through MoltenVK
- GPTK D3DMetal
- Wine builtin fallback

OpenGL/WineD3D should be treated as a fallback, not the preferred path.

## Compatibility expectations

Works best:

- single-player Windows games
- games with no kernel anti-cheat
- launchers that work under Wine
- games known to work through Wine/Proton-like stacks

Likely not supported:

- kernel anti-cheat
- Windows drivers/services
- Vanguard/EAC/BattlEye/Ricochet-protected games when they require kernel support

## Active code

```text
macos/ForgeNative/Sources/ForgeNative/ForgeNativeApp.swift
```

Run with:

```sh
npm run native:dev
```
