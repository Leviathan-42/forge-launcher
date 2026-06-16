#!/usr/bin/env bash
set -euo pipefail

# Kill Forge Launcher test processes, Wine sessions, Steam-in-Wine, and common game crash handlers.
# Leaves native macOS Steam alone except for Wine-launched Steam children.

PREFIXES=(
  "$HOME/Wine/Bottles/default"
  "$HOME/Wine/Bottles/peak-gptk4-direct"
)

WINE_SERVERS=(
  "$HOME/Wine/Runtimes/forge-wine-11-full/bin/wineserver"
  "$HOME/Wine/Runtimes/forge-wine-11/bin/wineserver"
  "/Applications/Game Porting Toolkit.app/Contents/Resources/wine/bin/wineserver"
)

for prefix in "${PREFIXES[@]}"; do
  for server in "${WINE_SERVERS[@]}"; do
    if [[ -x "$server" ]]; then
      WINEPREFIX="$prefix" "$server" -k >/dev/null 2>&1 || true
    fi
  done
done

pkill -f 'ForgeNative|Forge\.app|scripts/run-native-app\.sh' 2>/dev/null || true
pkill -f 'wine64-preloader|wineserver|winedevice\.exe|wineboot\.exe|rundll32\.exe' 2>/dev/null || true
pkill -f 'PEAK\.exe|UnityCrashHandler|steamwebhelper|Steam\\steam\.exe|C:\\Program Files.*Steam' 2>/dev/null || true

sleep 1
ps -axo pid,ppid,stat,etime,command \
  | egrep -i 'ForgeNative|Forge\.app|wine64-preloader|wineserver|winedevice|wineboot|rundll32|PEAK\.exe|UnityCrashHandler|steamwebhelper|Steam\\steam\.exe' \
  | grep -v egrep || true
