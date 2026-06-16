#!/usr/bin/env bash
set -euo pipefail

# Kill Forge Launcher test processes, Wine sessions, Steam-in-Wine, and common game crash handlers.
# Leaves native macOS Steam alone except for Wine-launched Steam children.

PREFIXES=(
  "$HOME/Wine/Bottles/default"
  "$HOME/Wine/Bottles/peak-gptk4-direct"
)

WINE_SERVERS=(
  "$HOME/Wine/Runtimes/forge-cx-wine-11-open-wow64/bin/wineserver"
  "$HOME/Wine/Runtimes/forge-cx-wine-11-open/bin/wineserver"
  "$HOME/Wine/Runtimes/forge-wine-11-full/bin/wineserver"
  "$HOME/Wine/Runtimes/forge-wine-11/bin/wineserver"
  "/Applications/Wine Devel.app/Contents/Resources/wine/bin/wineserver"
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
pkill -f '(^|/)wine( |$)|(^|/)wine64( |$)|wine-preloader|wine64-preloader|wineserver|winedevice\.exe|wineboot\.exe|winedbg|rundll32\.exe' 2>/dev/null || true
pkill -f 'Overwatch\.exe|PEAK\.exe|SlimeRancher\.exe|ULTRAKILL\.exe|UnityCrashHandler|steamwebhelper|steamservice\.exe|Steam\\steam\.exe|steam\.exe|C:\\Program Files.*Steam' 2>/dev/null || true

# Wine may leave hundreds of Windows-looking child processes whose argv starts
# with C:\... (for example conhost.exe). Activity Monitor shows these as "wine"
# even when pkill cannot match a normal Wine executable name, so remove them by
# argv prefix too. This is intentionally scoped to Windows path-shaped commands.
python3 - <<'PY'
import os
import signal
import subprocess

out = subprocess.check_output(['ps', '-axo', 'pid,args'], text=True)
for line in out.splitlines()[1:]:
    parts = line.strip().split(None, 1)
    if len(parts) != 2:
        continue
    pid_s, args = parts
    if args.startswith(('C:\\', 'Z:\\', 'Y:\\')) or args == '(wine)':
        try:
            os.kill(int(pid_s), signal.SIGKILL)
        except (ProcessLookupError, PermissionError, ValueError):
            pass
PY

sleep 1
ps -axo pid,ppid,stat,etime,rss,command \
  | egrep -i 'ForgeNative|Forge\.app|wine|wineserver|winedevice|wineboot|rundll32|Overwatch|PEAK\.exe|UnityCrashHandler|steamwebhelper|Steam\\steam\.exe|steam\.exe|^ *[0-9]+.*C:\\' \
  | grep -v egrep || true
