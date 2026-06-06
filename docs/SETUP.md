# Setup Guide

Forge is currently a macOS 26 native SwiftUI app for running Windows launchers and `.exe` apps inside Wine bottles.

The normal workflow is:

```text
create/use bottle -> install Windows launcher/game -> launch from Forge or Steam inside the bottle
```

## Requirements

- macOS 26 target SDK/runtime for the native app
- Apple Silicon Mac with Rosetta 2
- Xcode command line tools / Swift toolchain
- Homebrew
- Wine runtime configured in `runtime_profiles.json` or `config.json`
- Optional: Game Porting Toolkit for D3DMetal
- Optional: MoltenVK/DXVK/VKD3D for Vulkan backends

## One-command setup

From the project root:

```sh
./scripts/setup-macos.sh
```

The setup script checks common dependencies and prepares local config where possible.

## Manual setup

### 1. Rosetta 2

```sh
softwareupdate --install-rosetta --agree-to-license
```

### 2. Homebrew

Install Homebrew from <https://brew.sh> if needed.

### 3. Swift / Xcode tools

```sh
xcode-select --install
```

### 4. Node dependencies for scripts

```sh
npm install
```

### 5. Wine / GPTK / MoltenVK

Forge can use runtime profiles. Common paths are:

```text
Forge Wine: ~/Wine/Runtimes/forge-wine-11-full/bin/wine
GPTK wine64: /Applications/Game Porting Toolkit.app/Contents/Resources/wine/bin/wine64
GPTK libs: /Applications/Game Porting Toolkit.app/Contents/Resources/wine/lib/external
MoltenVK ICD: /opt/homebrew/opt/molten-vk/etc/vulkan/icd.d/MoltenVK_icd.json
```

## Run Forge

Use the native app:

```sh
npm run native:dev
```

This builds `dist/Forge.app` and opens it as a normal macOS app.

Raw Swift run, without the `.app` wrapper:

```sh
npm run native:run-raw
```

Release build:

```sh
npm run native:build
```

## First-use flow

1. Open Forge.
2. Use the default bottle or configure bottles in Application Support.
3. Drag a Windows `.exe` onto Forge or click **Select EXE**.
4. For Steam games, install Windows Steam inside the bottle, then press **Refresh** so Forge can detect installed Steam games.
5. Choose a graphics backend in the sidebar.
6. Toggle Metal HUD if desired.
7. Click **Play**. The button changes to **Stop** while a session is active.

## Graphics backend guidance

| Backend | Use for |
|---|---|
| DXVK/VKD3D | Default Vulkan path through MoltenVK |
| DXVK | D3D9/10/11 games |
| VKD3D | D3D12 games |
| D3DMetal | GPTK compatibility path |
| WineD3D | Last-resort compatibility fallback only |

Avoid OpenGL/WineD3D for performance unless a game only runs there.

## Logs

Launch logs are written to:

```text
~/Library/Application Support/com.forgelauncher.app/Logs/
```

Use the newest `swiftui-launch-*.log` when diagnosing crashes.

## Troubleshooting

### Forge does not appear in Cmd-Tab

Run through the `.app` wrapper:

```sh
npm run native:dev
```

### Steam or a game is stuck

Use the in-app **Stop** button or kill the bottle session manually:

```sh
WINEPREFIX="$HOME/Wine/Bottles/default" \
  "$HOME/Wine/Runtimes/forge-wine-11-full/bin/wineserver" -k
```

### Metal HUD does not appear

The toggle applies to the next launch. The HUD only appears for Metal-backed rendering paths; it may not appear for launcher UI windows or non-Metal fallback paths.

### PEAK compatibility note

PEAK is currently being tested. DXVK/MoltenVK, GPTK/D3DMetal, and WineD3D paths have each shown different failure modes on this machine. Check the latest launch log before assuming the UI failed to launch it.
