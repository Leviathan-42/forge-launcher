#!/usr/bin/env bash
set -euo pipefail

# Bounded Overwatch experiment helper. It kills stale Wine/Steam processes before
# launch and kills them again when the observation window ends, so a failed test
# cannot leave hundreds of Wine/conhost processes eating RAM.
#
# Usage:
#   scripts/overwatch-test-once.sh [dxvk|wined3d-vulkan|wined3d-gl|steam-dxvk] [seconds]
#   WINEDEBUG='fixme-all,+seh,+loaddll,+virtual,+syscall' scripts/overwatch-test-once.sh dxvk 12

MODE="${1:-dxvk}"
SECONDS_TO_RUN="${2:-30}"
# Overwatch_loader uses a deep VEH/stack-overflow recovery path while the loader
# lock is held. Forge's Wine runtime can reserve a larger guaranteed stack band
# for the second-chance exception dispatch with this variable.
FORGE_STACK_GUARANTEE_BYTES="${FORGE_STACK_GUARANTEE_BYTES:-262144}"
WINEDEBUG_VALUE="${WINEDEBUG:-fixme-all,+seh,+loaddll,+virtual}"
PREFIX="$HOME/Wine/Bottles/default"
RUNTIME="$HOME/Wine/Runtimes/forge-cx-wine-11-open-wow64"
GAME_DIR="$PREFIX/drive_c/Program Files (x86)/Steam/steamapps/common/Overwatch"
GAME="$GAME_DIR/Overwatch.exe"
STEAM="$PREFIX/drive_c/Program Files (x86)/Steam/steam.exe"
DXVK="$HOME/Wine/Runtimes/dxvk-2.7.1/dxvk-2.7.1/x64"
LOGDIR="$HOME/Library/Application Support/com.forgelauncher.app/Logs"
mkdir -p "$LOGDIR"

kill_wine_tree() {
  pkill -f 'Overwatch\.exe|steam\.exe|steamwebhelper\.exe|steamservice\.exe|wineserver|winedevice\.exe|explorer\.exe|wine-preloader|wine64-preloader|(^|/)wine( |$)|(^|/)wine64( |$)' >/dev/null 2>&1 || true
  if [[ -x "$RUNTIME/bin/wineserver" ]]; then
    WINEPREFIX="$PREFIX" "$RUNTIME/bin/wineserver" -k >/dev/null 2>&1 || true
  fi
  python3 - <<'PY'
import os, signal, subprocess
out = subprocess.check_output(['ps', '-axo', 'pid,args'], text=True)
for line in out.splitlines()[1:]:
    parts = line.strip().split(None, 1)
    if len(parts) == 2 and (parts[1].startswith(('C:\\', 'Z:\\', 'Y:\\')) or parts[1] == '(wine)'):
        try: os.kill(int(parts[0]), signal.SIGKILL)
        except Exception: pass
PY
}

restore_overwatch_originals() {
  local backup
  backup=$(ls -td "$HOME/Library/Application Support/com.forgelauncher.app/Backups"/overwatch-pe-stack-* 2>/dev/null | head -1 || true)
  if [[ -n "$backup" ]]; then
    cp -p "$backup/Overwatch.exe" "$backup/Overwatch_loader.dll" "$GAME_DIR"/ 2>/dev/null || true
  fi
}

stage_dxvk() {
  cp -f "$DXVK/dxgi.dll" "$DXVK/d3d11.dll" "$DXVK/d3d10core.dll" "$DXVK/d3d9.dll" "$GAME_DIR"/
}

clear_d3d() {
  rm -f "$GAME_DIR"/{dxgi.dll,d3d11.dll,d3d10core.dll,d3d10.dll,d3d10_1.dll,d3d9.dll,d3d12.dll}
}

kill_wine_tree
restore_overwatch_originals

case "$MODE" in
  dxvk|steam-dxvk)
    stage_dxvk
    DLL_OVERRIDES='dxgi,d3d9,d3d10core,d3d11=n,b;user32=n,b;mscoree,mshtml='
    WINE_D3D=''
    ;;
  wined3d-vulkan)
    clear_d3d
    DLL_OVERRIDES='*dxgi,*d3d8,*d3d9,*d3d10core,*d3d11,*d3d12,*d3d12core=b;vulkan-1,winevulkan=b;user32=n,b;mscoree,mshtml='
    WINE_D3D='renderer=vulkan'
    ;;
  wined3d-gl)
    clear_d3d
    DLL_OVERRIDES='*dxgi,*d3d8,*d3d9,*d3d10core,*d3d11,*d3d12,*d3d12core=b;user32=n,b;mscoree,mshtml='
    WINE_D3D='renderer=gl'
    ;;
  *)
    echo "Unknown mode: $MODE" >&2
    exit 2
    ;;
esac

LOG="$LOGDIR/manual-overwatch-${MODE}-bounded-$(date -u +%Y%m%dT%H%M%SZ).log"
cd "$GAME_DIR"

if [[ "$MODE" == "steam-dxvk" ]]; then
  EXE="$STEAM"
  ARGS=(-no-cef-sandbox -cef-disable-sandbox -applaunch 2357570 -tank_WorkerThreadCount 2)
else
  EXE="$GAME"
  ARGS=(-tank_WorkerThreadCount 2)
fi

ENV_VARS=(
  WINEPREFIX="$PREFIX"
  WINEDEBUG="$WINEDEBUG_VALUE"
  WINEDBG="-all"
  WINEESYNC=1
  WINEMSYNC=1
  FORGE_STACK_GUARANTEE_BYTES="$FORGE_STACK_GUARANTEE_BYTES"
  SteamAppId=2357570
  SteamGameId=2357570
  DYLD_LIBRARY_PATH="$RUNTIME/lib:/opt/homebrew/lib"
  DYLD_FALLBACK_LIBRARY_PATH="$RUNTIME/lib:/opt/homebrew/lib:/usr/local/lib"
)

if [[ "$MODE" == "steam-dxvk" ]]; then
  # Keep Steam's Chromium UI on a safe builtin path, and let the patched
  # kernelbase hand the intended DXVK env back to non-Steam child game EXEs.
  ENV_VARS+=(
    FORGE_STEAM_SAFE_MODE=1
    FORGE_SKIP_DESKTOP_WINDOW_BOOTSTRAP=steamwebhelper.exe
    FORGE_GAME_WINEDLLOVERRIDES="$DLL_OVERRIDES"
    FORGE_GAME_WINE_D3D_CONFIG="$WINE_D3D"
    FORGE_GAME_VK_ICD_FILENAMES="/opt/homebrew/share/vulkan/icd.d/MoltenVK_icd.json"
    FORGE_GAME_VK_DRIVER_FILES="/opt/homebrew/share/vulkan/icd.d/MoltenVK_icd.json"
    FORGE_GAME_DXVK_ASYNC=1
    FORGE_GAME_DYLD_LIBRARY_PATH="$RUNTIME/lib:/opt/homebrew/lib"
    # Do not put D3D/Vulkan-disabling overrides in the Unix environment here:
    # Steam-launched games inherit that Unix env before Wine's Windows env block
    # exists. Steam UI safety is handled with Wine AppDefaults/CEF flags.
    WINEDLLOVERRIDES="user32=n,b;mscoree,mshtml="
    VK_ICD_FILENAMES="/opt/homebrew/share/vulkan/icd.d/MoltenVK_icd.json"
    VK_DRIVER_FILES="/opt/homebrew/share/vulkan/icd.d/MoltenVK_icd.json"
    DXVK_ASYNC=1
    MOLTENVK_CONFIG_LOG_LEVEL=0
  )
else
  ENV_VARS+=(
    WINEDLLOVERRIDES="$DLL_OVERRIDES"
    WINE_D3D_CONFIG="$WINE_D3D"
    VK_ICD_FILENAMES="/opt/homebrew/share/vulkan/icd.d/MoltenVK_icd.json"
    VK_DRIVER_FILES="/opt/homebrew/share/vulkan/icd.d/MoltenVK_icd.json"
  )
fi

(
  env "${ENV_VARS[@]}" "$RUNTIME/bin/wine" "$EXE" "${ARGS[@]}"
) >"$LOG" 2>&1 &

sleep "$SECONDS_TO_RUN"

echo "LOG=$LOG"
ps -axo pid,etime,%cpu,%mem,rss,command \
  | egrep -i 'Overwatch|steam\.exe|steamwebhelper|wineserver|winedevice|^ *[0-9]+.*C:\\' \
  | grep -v egrep || true

echo "-- highlights --"
grep -Ei 'stack overflow|Overwatch_loader|handle_syscall_fault|NtUserCallNoParam|NtUserEndPaint|Unhandled|exception|err:|failed|DXVK|vulkan|d3d11|dxgi|window|graphics|steam' "$LOG" | tail -120 || true

kill_wine_tree

echo "-- after cleanup --"
ps -axo pid,etime,%cpu,%mem,rss,command \
  | egrep -i 'Overwatch|steam\.exe|steamwebhelper|wineserver|winedevice|^ *[0-9]+.*C:\\|\(wine\)' \
  | grep -v egrep || true
