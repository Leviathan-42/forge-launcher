# Setup Guide

Forge is now bottle-first: the normal Steam flow is **Windows Steam inside Wine**, not DepotDownloader/direct `.exe` launches. This fixes games that expect a real Steam session and avoids the fake `hostname.local`-style Steam persona that can appear when launching game files directly.

## One-command setup on a new Apple Silicon Mac

From the project root:

```sh
./scripts/setup-macos.sh
```

The script installs/checks:

- Rosetta 2
- Game Porting Toolkit Wine (`/opt/homebrew/bin/wine64`)
- DepotDownloader as an optional advanced/fallback tool
- Rust/Cargo via rustup
- Node dependencies

It then runs `npm run check` and `cargo check`.

## Manual setup

### 1. Rosetta 2

```sh
softwareupdate --install-rosetta --agree-to-license
```

### 2. Homebrew

Install Homebrew from <https://brew.sh> if needed.

### 3. Game Porting Toolkit Wine

```sh
brew tap gcenx/wine
brew install --cask gcenx/wine/game-porting-toolkit
```

This provides:

- `/opt/homebrew/bin/wine64`
- `/opt/homebrew/bin/wineserver`

### 4. Rust

```sh
curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y --profile minimal
. "$HOME/.cargo/env"
```

### 5. Node dependencies

```sh
npm install
```

## Run Forge

```sh
npm run tauri dev
```

## First-use Steam flow

1. Select or create a bottle in the sidebar.
2. Click **Install Steam**.
3. Sign into the Windows Steam client that opens inside Wine.
4. Install your Windows games from that Steam client.
5. Launch games from Steam, or use Forge's app list once Steam/game executables are detected.

For Steam games, prefer Steam-owned launching:

```text
steam.exe -applaunch <appid>
```

Direct `.exe` launching remains available as an escape hatch, but it is not the recommended Steam path.

## Optional: DepotDownloader

DepotDownloader is still useful for advanced depot downloads or file repair, but it is no longer the main user workflow.

```sh
brew tap steamre/tools
brew install --cask steamre/tools/depotdownloader
xattr -dr com.apple.quarantine /opt/homebrew/bin/depotdownloader 2>/dev/null || true
```

## Runtime settings

Forge auto-detects these on first run when possible:

| Setting | Typical value |
|---|---|
| Wine binary | `/opt/homebrew/bin/wine64` |
| GPTK library | `/Applications/Game Porting Toolkit.app/Contents/Resources/wine/lib/external` or detected GPTK lib dir |
| Default bottle | `~/Wine/Bottles/default` |

If Wine is not detected, open **Settings** and set the Wine binary manually.

## Troubleshooting

### Wine command is missing

```sh
brew reinstall --cask gcenx/wine/game-porting-toolkit
```

### DepotDownloader is killed immediately

Remove Gatekeeper quarantine:

```sh
xattr -dr com.apple.quarantine /opt/homebrew/Caskroom/depotdownloader /opt/homebrew/bin/depotdownloader
```

### Cargo command is missing in a new terminal

```sh
. "$HOME/.cargo/env"
```

Add that line to `~/.zshrc` if it is not already there.

### Steam installer opens but Steam does not finish installing

Use **Repair Steam**, or run the installer again from Forge. If the bottle is badly broken, create a fresh bottle and install Steam there.
