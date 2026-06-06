#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

log() { printf '\n\033[1;32m==>\033[0m %s\n' "$*"; }
warn() { printf '\n\033[1;33mwarning:\033[0m %s\n' "$*"; }
need_cmd() {
  if ! command -v "$1" >/dev/null 2>&1; then
    printf 'Missing required command: %s\n' "$1" >&2
    return 1
  fi
}

if [[ "$(uname -s)" != "Darwin" ]]; then
  echo "Forge setup currently targets macOS Apple Silicon." >&2
  exit 1
fi

if [[ "$(uname -m)" != "arm64" ]]; then
  warn "This script is intended for Apple Silicon Macs. Continuing anyway."
fi

log "Installing Rosetta 2 if needed"
if /usr/bin/pgrep oahd >/dev/null 2>&1; then
  echo "Rosetta already appears to be active."
else
  softwareupdate --install-rosetta --agree-to-license || true
fi

log "Checking Homebrew"
if ! command -v brew >/dev/null 2>&1; then
  echo "Install Homebrew first: https://brew.sh" >&2
  exit 1
fi

log "Installing runtime tools"
brew tap gcenx/wine >/dev/null
brew tap steamre/tools >/dev/null
brew install --cask gcenx/wine/game-porting-toolkit
brew install --cask wine@devel || brew install --cask wine-stable || true
brew install molten-vk || true
brew install --cask steamre/tools/depotdownloader || brew install depotdownloader || true

# Homebrew casks can keep quarantine bits, which makes macOS kill the binary on first run.
if [[ -e /opt/homebrew/bin/depotdownloader ]]; then
  xattr -dr com.apple.quarantine /opt/homebrew/bin/depotdownloader 2>/dev/null || true
fi
if [[ -d /opt/homebrew/Caskroom/depotdownloader ]]; then
  xattr -dr com.apple.quarantine /opt/homebrew/Caskroom/depotdownloader 2>/dev/null || true
fi

log "Installing Rust with rustup if needed"
if ! command -v cargo >/dev/null 2>&1; then
  curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y --profile minimal
fi
# shellcheck source=/dev/null
[[ -f "$HOME/.cargo/env" ]] && . "$HOME/.cargo/env"

if [[ -f "$HOME/.zshrc" ]] && ! grep -q 'cargo/env' "$HOME/.zshrc"; then
  printf '\n# Rust/Cargo\n. "$HOME/.cargo/env"\n' >> "$HOME/.zshrc"
elif [[ ! -f "$HOME/.zshrc" ]]; then
  printf '# Rust/Cargo\n. "$HOME/.cargo/env"\n' > "$HOME/.zshrc"
fi

log "Installing JavaScript dependencies"
cd "$ROOT"
npm install

log "Verifying setup"
need_cmd node
need_cmd npm
need_cmd cargo
need_cmd /opt/homebrew/bin/wine64
if command -v depotdownloader >/dev/null 2>&1; then
  depotdownloader --version || true
elif [[ -x /opt/homebrew/bin/depotdownloader ]]; then
  /opt/homebrew/bin/depotdownloader --version || true
else
  warn "DepotDownloader was not found. It is optional for the new Steam-in-bottle workflow."
fi
npm run check
(cd src-tauri && cargo check)

cat <<EOF

Forge setup complete.

Run the app:
  cd "$ROOT"
  npm run tauri dev

Recommended first-use flow:
  1. Create/select the Default bottle.
  2. Click Install Steam.
  3. Sign into Windows Steam inside the bottle.
  4. Install and launch games from that Steam client.

EOF
