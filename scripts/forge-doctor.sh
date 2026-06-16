#!/usr/bin/env bash
set -euo pipefail

APP_SUPPORT="$HOME/Library/Application Support/com.forgelauncher.app"
RUNTIME="$HOME/Wine/Runtimes/forge-cx-wine-11-open-wow64"
PREFIX="$HOME/Wine/Bottles/default"
LOGDIR="$APP_SUPPORT/Logs"
SOURCES_ROOT="$HOME/Downloads/sources"
CX_SOURCES_ROOT="$HOME/Downloads/crossover-sources-26.1.0/sources"

echo "Forge Doctor"
echo "============"
echo

echo "Config files:"
for f in config.json bottles.json runtime_profiles.json game_compatibility_profiles.json; do
  if [[ -f "$APP_SUPPORT/$f" ]]; then
    echo "  OK $APP_SUPPORT/$f"
  else
    echo "  MISSING $APP_SUPPORT/$f"
  fi
done

echo

echo "Runtime: $RUNTIME"
for f in bin/wine bin/wineserver lib/libinotify.dylib lib/wine/i386-windows/ntdll.dll lib/wine/x86_64-windows/ntdll.dll; do
  if [[ -e "$RUNTIME/$f" ]]; then
    echo "  OK $f"
  else
    echo "  MISSING $f"
  fi
done

if [[ -x "$RUNTIME/bin/wineserver" ]]; then
  echo
  echo "wineserver dylib check:"
  if otool -L "$RUNTIME/bin/wineserver" | grep -q '@loader_path/../lib/libinotify.dylib'; then
    echo "  OK libinotify uses @loader_path"
  else
    echo "  WARN libinotify is not loader-relative; fixing..."
    install_name_tool -change libinotify.dylib '@loader_path/../lib/libinotify.dylib' "$RUNTIME/bin/wineserver" || true
  fi
fi

echo

echo "Prefix: $PREFIX"
for f in "drive_c/Program Files (x86)/Steam/steam.exe" "drive_c/Program Files (x86)/Steam/steamapps/appmanifest_3527290.acf"; do
  if [[ -e "$PREFIX/$f" ]]; then
    echo "  OK $f"
  else
    echo "  MISSING $f"
  fi
done

echo

echo "Open-source source/license cache:"
for root in "$SOURCES_ROOT" "$CX_SOURCES_ROOT"; do
  if [[ -d "$root" ]]; then
    echo "  OK $root"
    find "$root" -maxdepth 2 \( -iname 'LICENSE*' -o -iname 'COPYING*' -o -iname 'COPYRIGHT*' \) -type f 2>/dev/null | head -12 | sed "s#^#    #"
  else
    echo "  MISSING $root"
  fi
done

echo

echo "Seeded game profiles:"
if [[ -f "$APP_SUPPORT/game_compatibility_profiles.json" ]]; then
  python3 - <<'PY' "$APP_SUPPORT/game_compatibility_profiles.json"
import json, sys
with open(sys.argv[1]) as f:
    profiles = json.load(f)
for p in profiles:
    if p.get('id') in {'steam:1336490', 'steam:945360', 'name:peak'}:
        print(f"  OK {p.get('display_name')} ({p.get('id')}) backend={p.get('backend_override') or 'default'} args={' '.join(p.get('launch_args') or [])}")
PY
else
  echo "  MISSING game_compatibility_profiles.json; launch Forge once to seed profiles"
fi

echo

echo "Running processes:"
ps -axo pid,etime,%cpu,%mem,command | egrep 'Forge\.app|ForgeNative|steam.exe|PEAK.exe|wineserver|winedevice' | grep -v egrep || echo "  none"

echo

echo "Latest Forge launch logs:"
latest_logs=$(find "$LOGDIR" -maxdepth 1 -name 'swiftui-launch-*.log' -type f 2>/dev/null | sort -r | head -5 || true)
if [[ -n "$latest_logs" ]]; then
  printf '%s\n' "$latest_logs"
else
  echo "  none"
fi

echo

echo "Done."
