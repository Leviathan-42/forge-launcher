# Setup Guide

## Prerequisites

### 1. macOS requirements

| Requirement | Version |
|---|---|
| macOS | 14.0 Sonoma or later |
| Mac hardware | Apple Silicon (M1 / M2 / M3 / M4) |
| Xcode Command Line Tools | latest |
| Rosetta 2 | required (installed below) |

### 2. Install Rosetta 2

```sh
softwareupdate --install-rosetta --agree-to-license
```

### 3. Install x86_64 Homebrew (required for GPTK)

GPTK's wine64 binary is x86_64, so you need the Intel version of Homebrew
installed alongside the native ARM64 one.

```sh
# Open a Rosetta terminal
arch -x86_64 zsh

# Install x86_64 Homebrew to /usr/local
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
```

Verify:
```sh
arch -x86_64 /usr/local/bin/brew --prefix
# → /usr/local
```

### 4. Install Game Porting Toolkit

```sh
arch -x86_64 /usr/local/bin/brew tap apple/apple http://formulae.brew.sh/tap/apple/
arch -x86_64 /usr/local/bin/brew install apple/apple/game-porting-toolkit
```

This installs:
- `wine64` at `/usr/local/bin/wine64`
- GPTK support libraries at `/usr/local/lib/`

#### Optional: copy D3DMetal from Apple's DMG (GPTK 2.1+)

Download the DMG from https://developer.apple.com/games/game-porting-toolkit/

```sh
# Mount the DMG first, then:
ditto "/Volumes/Evaluation environment for Windows games 2.1/redist/lib/" \
      "$(arch -x86_64 /usr/local/bin/brew --prefix game-porting-toolkit)/lib/"
```

### 5. Create your first Wine prefix

```sh
WINEPREFIX=~/Wine/Bottles/default \
  arch -x86_64 /usr/local/bin/wine64 winecfg
```

Set the Windows version to **Windows 10** in the dialog that appears.

### 6. Rust toolchain

```sh
curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh
rustup target add x86_64-apple-darwin   # optional: cross-compile target
```

### 7. Node.js (LTS)

```sh
# Using nvm (recommended)
curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.40.0/install.sh | bash
nvm install --lts
```

---

## Project setup

```sh
# Clone the project (or open the directory you already have)
cd "Gamehub clone"

# Install JS dependencies
npm install

# Generate icons from the source PNG (only needed once, or when you change app-icon.png)
npx tauri icon app-icon.png

# Run in development mode (hot reload)
npm run tauri dev

# Build a .dmg for distribution
npm run tauri build
```

### How the window works

In **development** (`tauri dev`), the Tauri window loads from Vite's HMR
server at `http://localhost:5173`. This gives you hot reload, but it does
appear as a native macOS window — not a browser tab. You can Cmd+Tab to it
just like any other app.

In **production** (`tauri build`), the compiled frontend (`dist/`) is
embedded inside the `.app` bundle and served via Tauri's internal
`asset://localhost` custom protocol. There is no web server, no port, and
no `localhost` in the process list. The app is fully self-contained and
behaves identically to a native macOS application.

### Common build errors and fixes

| Error | Cause | Fix |
|---|---|---|
| `OUT_DIR env var is not set` | `build.rs` is missing | Ensure `src-tauri/build.rs` exists with `fn main() { tauri_build::build() }` |
| `failed to open icon *.png` | `icons/` directory missing | Run `npx tauri icon app-icon.png` |
| `key must be a string` in tauri.conf.json | JSON comments (`//`) are not valid JSON | Remove all `//` comments from `tauri.conf.json` |
| `Permission fs:default not found` | Plugin added to capabilities but not Cargo.toml | Either add the plugin crate or remove the permission |

---

## Configuring the launcher

On first run, `config.json` is created at:

```
~/Library/Application Support/com.forgelauncher.app/config.json
```

Default values assume a standard GPTK Homebrew install. If your paths differ,
update them via **Settings** in the UI or edit the file directly.

| Key | Default | Notes |
|---|---|---|
| `wine64_path` | `/usr/local/bin/wine64` | Path to GPTK wine64 binary |
| `gptk_lib_path` | `/usr/local/lib/external` | D3DMetal + libd3dshared dir |
| `default_prefix` | `~/Wine/Bottles/default` | Default Wine bottle |

---

## Troubleshooting

### Game immediately exits / no window

1. Open a terminal and run the command manually to see raw output:
   ```sh
   WINEPREFIX=~/Wine/Bottles/default \
   DYLD_LIBRARY_PATH=/usr/local/lib/external \
   WINEDEBUG="" \
   arch -x86_64 /usr/local/bin/wine64 /path/to/game.exe
   ```

2. Turn off `suppress_wine_debug` in Settings to see Wine stderr.

### D3DMetal not found

```
Assertion failed: (GFXTHandle && "Failed to dlopen D3DMetal")
```

The GPTK library files are not in the expected location. Run:

```sh
ls /usr/local/lib/external/D3DMetal.framework
```

If missing, re-run step 4 (copy D3DMetal from the DMG).

### `arch -x86_64` fails

Rosetta 2 is not installed. Run step 2 above.

### Wine prefix not initialised

The game cannot find `c:\windows`. Run `create_prefix` or use:
```sh
WINEPREFIX=~/Wine/Bottles/default \
  arch -x86_64 /usr/local/bin/wine64 wineboot --init
```
