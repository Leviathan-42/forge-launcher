#!/usr/bin/env bash
set -euo pipefail

# Launch Steam with Forge's current Steam compatibility checks, capture logs,
# capture a screenshot, and estimate whether the result looks black-screened.
#
# Usage:
#   scripts/test-steam-launch.sh
#   WAIT_SECONDS=20 scripts/test-steam-launch.sh
#   KEEP_RUNNING=1 scripts/test-steam-launch.sh
#   WINE="$HOME/Wine/Runtimes/forge-wine-11/bin/wine" scripts/test-steam-launch.sh
#   STEAM_CEF_MODE=software scripts/test-steam-launch.sh

WAIT_SECONDS="${WAIT_SECONDS:-18}"
KEEP_RUNNING="${KEEP_RUNNING:-0}"
STEAM_CEF_MODE="${STEAM_CEF_MODE:-minimal}"
STEAM_GRAPHICS_MODE="${STEAM_GRAPHICS_MODE:-builtin}"
WINE_D3D_RENDERER="${WINE_D3D_RENDERER:-gl}"
GPTK_WINE_LIB="${GPTK_WINE_LIB:-/Applications/Game Porting Toolkit.app/Contents/Resources/wine/lib}"
PREFIX="${PREFIX:-$HOME/Wine/Bottles/default}"
WINE="${WINE:-/Applications/Wine Devel.app/Contents/Resources/wine/bin/wine}"
STEAM_EXE="${STEAM_EXE:-$PREFIX/drive_c/Program Files (x86)/Steam/steam.exe}"
OUT_DIR="${OUT_DIR:-artifacts/steam-launch-test-$(date +%Y%m%d-%H%M%S)}"
LOG="$OUT_DIR/steam.log"
SCREENSHOT="$OUT_DIR/screenshot.png"
REPORT="$OUT_DIR/report.md"

mkdir -p "$OUT_DIR"

if [[ ! -x "$WINE" ]]; then
  echo "Wine not found/executable: $WINE" >&2
  exit 1
fi

if [[ ! -f "$STEAM_EXE" ]]; then
  echo "Steam not found: $STEAM_EXE" >&2
  exit 1
fi

WINE_ROOT="$(cd "$(dirname "$WINE")/.." && pwd)"
WINE_RUNTIME_LIB="$WINE_ROOT/lib"
if [[ -d "$WINE_RUNTIME_LIB" ]]; then
  export DYLD_LIBRARY_PATH="$WINE_RUNTIME_LIB${DYLD_LIBRARY_PATH:+:$DYLD_LIBRARY_PATH}"
  export DYLD_FALLBACK_LIBRARY_PATH="$WINE_RUNTIME_LIB:/opt/homebrew/lib:/usr/local/lib${DYLD_FALLBACK_LIBRARY_PATH:+:$DYLD_FALLBACK_LIBRARY_PATH}"
fi

WINE_VERSION="$($WINE --version 2>/dev/null || true)"

# Start clean enough for a useful test. This targets this prefix and also
# clears detached Wine/Steam helpers from prior test runs. Disable Mono/Gecko
# prompts here because a runtime switch can trigger a prefix update.
WINEPREFIX="$PREFIX" WINEDLLOVERRIDES="mscoree,mshtml=" "$WINE" wineserver -k >/dev/null 2>&1 || true
pkill -9 -f 'steam.exe|steamwebhelper|steamerrorreporter|wine64-preloader|winedevice.exe|wineserver' >/dev/null 2>&1 || true
sleep 1

cat > "$REPORT" <<EOF
# Forge Steam Launch Test

Started: $(date)

## Inputs

- Wine: \`$WINE\`
- Wine version: \`$WINE_VERSION\`
- Prefix: \`$PREFIX\`
- Steam: \`$STEAM_EXE\`
- Wait seconds: \`$WAIT_SECONDS\`
- Keep running: \`$KEEP_RUNNING\`

## Compatibility mode

This test applies Forge's current Steam-specific workaround:

- \`WINEMSYNC=1\`
- \`WINEESYNC=1\`
- Steam graphics mode: \`$STEAM_GRAPHICS_MODE\`
- Steam CEF mode: \`$STEAM_CEF_MODE\`
- Wined3D renderer: \`$WINE_D3D_RENDERER\`
- Extra args: \`${EXTRA_STEAM_ARGS:-}\`
- Runtime lib path: \`$WINE_RUNTIME_LIB\`

EOF

export WINEPREFIX="$PREFIX"
export WINEDEBUG="fixme-all"
export GST_DEBUG="1"
export WINEMSYNC="1"
export WINEESYNC="1"
export MOLTENVK_CONFIG_LOG_LEVEL="0"
export FORGE_SKIP_DESKTOP_WINDOW_BOOTSTRAP="${FORGE_SKIP_DESKTOP_WINDOW_BOOTSTRAP:-steamwebhelper.exe}"

case "$STEAM_GRAPHICS_MODE" in
  builtin)
    export WINEDLLOVERRIDES="*dxgi,*d3d8,*d3d9,*d3d10core,*d3d11,*d3d12,*d3d12core=b;user32=n,b;mscoree,mshtml="
    export LIBGL_ALWAYS_SOFTWARE="1"
    export VK_ICD_FILENAMES="/dev/null"
    export VK_DRIVER_FILES="/dev/null"
    export DXVK_FILTER_DEVICE_NAME="__forge_disable_dxvk_for_steam__"
    export WINE_D3D_CONFIG="renderer=$WINE_D3D_RENDERER"
    ;;
  d3d11)
    # Let the prefix choose native/builtin D3D11. Useful for proving whether
    # installed DXVK is the thing breaking Steam CEF.
    export WINEDLLOVERRIDES="user32=n,b;mscoree,mshtml="
    unset VK_ICD_FILENAMES VK_DRIVER_FILES DXVK_FILTER_DEVICE_NAME LIBGL_ALWAYS_SOFTWARE
    if [[ -n "${WINE_D3D_RENDERER:-}" ]]; then
      export WINE_D3D_CONFIG="renderer=$WINE_D3D_RENDERER"
    fi
    ;;
  wined3d)
    # Try Wine builtin D3D11/wined3d without disabling Chromium GPU
    # acceleration or Vulkan.
    export WINEDLLOVERRIDES="dxgi,d3d9,d3d10core,d3d11=b;user32=n,b;mscoree,mshtml="
    unset VK_ICD_FILENAMES VK_DRIVER_FILES DXVK_FILTER_DEVICE_NAME LIBGL_ALWAYS_SOFTWARE
    if [[ -n "${WINE_D3D_RENDERER:-}" ]]; then
      export WINE_D3D_CONFIG="renderer=$WINE_D3D_RENDERER"
    fi
    ;;
  gptk)
    # Free Apple Game Porting Toolkit / D3DMetal path.
    # It lets Forge-owned Wine 11 try an ANGLE_D3D11-style path using Apple's
    # free GPTK libs.
    if [[ ! -d "$GPTK_WINE_LIB/external" ]]; then
      echo "GPTK external libs not found: $GPTK_WINE_LIB/external" >&2
      exit 1
    fi
    export WINEDLLPATH="$GPTK_WINE_LIB/wine/x86_64-windows${WINEDLLPATH:+:$WINEDLLPATH}"
    export DYLD_LIBRARY_PATH="$GPTK_WINE_LIB/external:$GPTK_WINE_LIB/external/external:${DYLD_LIBRARY_PATH:-}"
    export WINEDLLOVERRIDES="dxgi,d3d9,d3d10core,d3d11,d3d12=b;user32=n,b;mscoree,mshtml="
    unset VK_ICD_FILENAMES VK_DRIVER_FILES DXVK_FILTER_DEVICE_NAME LIBGL_ALWAYS_SOFTWARE WINE_D3D_CONFIG
    ;;
  *)
    echo "Unknown STEAM_GRAPHICS_MODE='$STEAM_GRAPHICS_MODE' (expected builtin, d3d11, wined3d, or gptk)" >&2
    exit 1
    ;;
esac

ARGS=(
  start /unix "$STEAM_EXE"
  -no-cef-sandbox
  -cef-disable-sandbox
)

if [[ "$STEAM_CEF_MODE" == "software" ]]; then
  ARGS+=(
    -cef-disable-gpu
    -cef-disable-gpu-compositing
    -cef-disable-d3d11
    -cef-disable-angle
    -disable-gpu
    -disable-gpu-compositing
  )
elif [[ "$STEAM_CEF_MODE" != "minimal" ]]; then
  echo "Unknown STEAM_CEF_MODE='$STEAM_CEF_MODE' (expected minimal or software)" >&2
  exit 1
fi
if [[ -n "${EXTRA_STEAM_ARGS:-}" ]]; then
  # shellcheck disable=SC2206
  EXTRA_ARGS=( ${EXTRA_STEAM_ARGS} )
  ARGS+=("${EXTRA_ARGS[@]}")
fi

{
  echo "[$(date)] Launch command:"
  printf '%q ' "$WINE" "${ARGS[@]}"
  echo
  echo
  "$WINE" "${ARGS[@]}"
} > "$LOG" 2>&1 &
LAUNCH_PID=$!

echo "$LAUNCH_PID" > "$OUT_DIR/launcher.pid"

sleep "$WAIT_SECONDS"

# Capture the Steam/Wine window only, so the terminal does not affect the
# black-screen analysis. Falls back to full-screen only if macOS cannot find
# a Steam/Wine window.
WINDOW_INFO="$OUT_DIR/window-info.txt"
WINDOW_ID=""
swift scripts/steam-window-shot.swift > "$WINDOW_INFO" 2>&1 || true
WINDOW_ID="$(awk -F= '/SELECTED_WINDOW_ID=/{print $2; exit}' "$WINDOW_INFO")"
if [[ -n "$WINDOW_ID" ]]; then
  screencapture -x -l "$WINDOW_ID" "$SCREENSHOT" || screencapture -x "$SCREENSHOT" || true
else
  echo "No Steam/Wine window id found; falling back to full-screen screenshot." >> "$WINDOW_INFO"
  screencapture -x "$SCREENSHOT" || true
fi

# Collect process state.
{
  echo "## Wine/Steam processes"
  pgrep -af 'steam|Steam|wine|wineserver|steamwebhelper' || true
  echo
  echo "## Recent log tail"
  tail -220 "$LOG" || true
} > "$OUT_DIR/process-and-log-tail.txt"

# Analyze the screenshot with a tiny stdlib PNG decoder. It computes how much
# of the screenshot is very dark. This is a heuristic, not a perfect UI test.
python3 - "$SCREENSHOT" > "$OUT_DIR/screenshot-analysis.txt" <<'PY' || true
import sys, struct, zlib
path=sys.argv[1]
raw=open(path,'rb').read()
if raw[:8] != b'\x89PNG\r\n\x1a\n':
    print('not_png=true')
    raise SystemExit
pos=8; w=h=ct=bd=None; data=b''
while pos < len(raw):
    n=struct.unpack('>I', raw[pos:pos+4])[0]; pos+=4
    typ=raw[pos:pos+4]; pos+=4
    chunk=raw[pos:pos+n]; pos+=n+4
    if typ==b'IHDR':
        w,h,bd,ct,comp,flt,inter=struct.unpack('>IIBBBBB', chunk)
        if bd != 8 or inter != 0 or ct not in (2,6):
            print(f'unsupported_png bit_depth={bd} color_type={ct} interlace={inter}')
            raise SystemExit
    elif typ==b'IDAT':
        data += chunk
    elif typ==b'IEND':
        break
channels = 4 if ct == 6 else 3
stride = w * channels
img = zlib.decompress(data)
rows=[]; i=0; prev=bytearray(stride)
for y in range(h):
    f=img[i]; i+=1
    cur=bytearray(img[i:i+stride]); i+=stride
    for x in range(stride):
        left = cur[x-channels] if x >= channels else 0
        up = prev[x]
        ul = prev[x-channels] if x >= channels else 0
        if f == 1: cur[x] = (cur[x] + left) & 255
        elif f == 2: cur[x] = (cur[x] + up) & 255
        elif f == 3: cur[x] = (cur[x] + ((left + up)//2)) & 255
        elif f == 4:
            p = left + up - ul
            pa, pb, pc = abs(p-left), abs(p-up), abs(p-ul)
            pr = left if pa <= pb and pa <= pc else (up if pb <= pc else ul)
            cur[x] = (cur[x] + pr) & 255
    rows.append(cur); prev=cur
# sample every N pixels to keep it fast
step=max(1, (w*h)//300000)
dark=very_dark=bright=count=0
r_sum=g_sum=b_sum=0
idx=0
for row in rows:
    for x in range(0, w, step):
        off=x*channels
        r,g,b=row[off],row[off+1],row[off+2]
        lum=(r*299+g*587+b*114)//1000
        count+=1; r_sum+=r; g_sum+=g; b_sum+=b
        if lum < 20: very_dark += 1
        if lum < 45: dark += 1
        if lum > 120: bright += 1
print(f'width={w}')
print(f'height={h}')
print(f'samples={count}')
print(f'avg_rgb={r_sum//count},{g_sum//count},{b_sum//count}')
print(f'dark_percent={dark*100/count:.2f}')
print(f'very_dark_percent={very_dark*100/count:.2f}')
print(f'bright_percent={bright*100/count:.2f}')
print('likely_black_screen=' + ('true' if dark*100/count > 75 and bright*100/count < 8 else 'false'))
PY

# Extract likely important errors from the full log.
grep -Eina 'black|DXVK|No adapters|geometryShader|Failed to initialize|steamwebhelper|cef|angle|gpu|vulkan|molten|err:|wine: Call|unimplemented|exception|fatal' "$LOG" \
  > "$OUT_DIR/log-highlights.txt" || true

{
  echo
  echo "## Window capture"
  echo '```'
  cat "$WINDOW_INFO" 2>/dev/null || true
  echo '```'
  echo
  echo "## Screenshot analysis"
  echo '```'
  cat "$OUT_DIR/screenshot-analysis.txt" 2>/dev/null || true
  echo '```'
  echo
  echo "## Log highlights"
  echo '```'
  sed -n '1,260p' "$OUT_DIR/log-highlights.txt" 2>/dev/null || true
  echo '```'
  echo
  echo "## Files"
  echo
  echo "- Steam window screenshot: \`$SCREENSHOT\`"
  echo "- Window info: \`$WINDOW_INFO\`"
  echo "- Full log: \`$LOG\`"
  echo "- Log highlights: \`$OUT_DIR/log-highlights.txt\`"
  echo "- Process/log tail: \`$OUT_DIR/process-and-log-tail.txt\`"
} >> "$REPORT"

if [[ "$KEEP_RUNNING" != "1" ]]; then
  WINEPREFIX="$PREFIX" WINEDLLOVERRIDES="mscoree,mshtml=" "$WINE" wineserver -k >/dev/null 2>&1 || true
fi

cat <<EOF
Wrote: $REPORT
Screenshot: $SCREENSHOT
Log: $LOG
EOF
