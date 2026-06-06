#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PACKAGE_DIR="$ROOT/macos/ForgeNative"
APP_DIR="$ROOT/dist/Forge.app"
CONTENTS="$APP_DIR/Contents"
MACOS="$CONTENTS/MacOS"
RESOURCES="$CONTENTS/Resources"
EXECUTABLE="$PACKAGE_DIR/.build/debug/ForgeNative"

swift build --package-path "$PACKAGE_DIR"

rm -rf "$APP_DIR"
mkdir -p "$MACOS" "$RESOURCES"
cp "$EXECUTABLE" "$MACOS/Forge"
chmod +x "$MACOS/Forge"

if [[ -f "$ROOT/src-tauri/icons/icon.icns" ]]; then
  cp "$ROOT/src-tauri/icons/icon.icns" "$RESOURCES/Forge.icns"
fi

cat > "$CONTENTS/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleDevelopmentRegion</key>
  <string>en</string>
  <key>CFBundleExecutable</key>
  <string>Forge</string>
  <key>CFBundleIconFile</key>
  <string>Forge</string>
  <key>CFBundleIdentifier</key>
  <string>com.forgelauncher.native</string>
  <key>CFBundleName</key>
  <string>Forge</string>
  <key>CFBundleDisplayName</key>
  <string>Forge</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>CFBundleShortVersionString</key>
  <string>0.1.0</string>
  <key>CFBundleVersion</key>
  <string>1</string>
  <key>LSMinimumSystemVersion</key>
  <string>26.0</string>
  <key>LSUIElement</key>
  <false/>
  <key>NSHighResolutionCapable</key>
  <true/>
  <key>NSSupportsAutomaticGraphicsSwitching</key>
  <true/>
</dict>
</plist>
PLIST

open -n "$APP_DIR"
echo "Opened $APP_DIR"
