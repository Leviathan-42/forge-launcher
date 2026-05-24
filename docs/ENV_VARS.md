# Wine & GPTK Environment Variable Reference

This document is a complete reference for every environment variable Forge
Launcher can inject when launching a game. All of these map to fields in the
`Game` or `AppConfig` structs and can be toggled in the UI or by editing
`config.json` / `games.json` directly.

---

## Core Wine variables

### `WINEPREFIX`

**Required.** Absolute path to the Wine bottle (virtual Windows C: drive).

```sh
WINEPREFIX=~/Wine/Bottles/default
```

- Each bottle is isolated — registry, DLLs, and installed software are separate.
- You can share one bottle across multiple games or create one per game.
- Must be initialised with `wineboot --init` before first use.

---

### `WINEDEBUG`

Controls Wine's debug output to stderr.

| Value | Meaning |
|---|---|
| `-all` | Suppress everything (default in Forge Launcher release mode) |
| `` (empty) | Default Wine verbosity |
| `+d3d11,+vulkan` | Enable specific debug channels |
| `warn+all` | Show only warnings |

Set `suppress_wine_debug: false` in AppConfig to leave this empty and see
Wine's raw output — useful when diagnosing crashes.

---

### `WINEESYNC`

```sh
WINEESYNC=1
```

Enables Wine's **eventfd-based synchronisation** (ESYNC). This replaces Wine's
default wineserver-based mutex/semaphore synchronisation with Linux/macOS
eventfd primitives.

- **Usually improves performance significantly** for CPU-heavy games.
- Default: enabled (`esync: true` in the Game struct).
- If a game crashes immediately with ESYNC on, try disabling it.

---

### `WINEMSYNC`

```sh
WINEMSYNC=1
```

Enables Wine's **mach-port semaphore synchronisation** (MSYNC). macOS-specific
alternative to ESYNC.

- Mutually exclusive with ESYNC in most Wine builds — don't enable both.
- Try MSYNC if ESYNC causes issues on your specific macOS version.
- Default: disabled.

---

### `WINEDLLOVERRIDES`

Overrides which DLL implementation Wine uses for specific libraries.

Format: `dll_name=override_type[;dll2=type2...]`

| Override type | Meaning |
|---|---|
| `n` | Native (use the DLL from the Wine prefix / system) |
| `b` | Builtin (use Wine's built-in implementation) |
| `n,b` | Try native first, fall back to builtin |

**DXVK override** (set when `translation_backend = "dxvk"`):
```sh
WINEDLLOVERRIDES="d3d11=n,b;d3d10core=n,b"
```

This tells Wine to use DXVK's `d3d11.dll` (native) instead of Wine's built-in
D3D11 implementation, routing all D3D11 calls through DXVK's Vulkan backend.

---

## GPTK / D3DMetal variables

### `DYLD_LIBRARY_PATH`

Tells the dynamic linker where to find GPTK's shared libraries.

```sh
DYLD_LIBRARY_PATH=/usr/local/lib/external:/usr/local/lib/external:...
```

Forge Launcher builds this path as:
```
<gptk_lib_path>:<gptk_lib_path>/external:<existing DYLD_LIBRARY_PATH>
```

The `external/` subdirectory contains:
- `D3DMetal.framework/` — Apple's DirectX 12 → Metal translation layer
- `libd3dshared.dylib` — shared D3D support library

---

### `D3DM_SUPPORT_DXR`

```sh
D3DM_SUPPORT_DXR=1
```

Enables **DirectX Raytracing (DXR)** support in D3DMetal.

- Only effective on **M3 and later** Macs (hardware ray tracing support).
- Set `enable_dxr: true` in the Game struct to enable.
- Default: off (most games don't require DXR).

---

### `D3DM_ENABLE_METALFX`

```sh
D3DM_ENABLE_METALFX=1
```

Enables **MetalFX** upscaling (Apple's equivalent of DLSS/FSR).
Requires **GPTK 3.0+**.

When enabled, games that support NVIDIA DLSS will have their DLSS calls
intercepted and redirected to MetalFX.

- Set globally via `metalfx_enabled: true` in AppConfig.
- Requires `nvngx.dll` and `nvapi64.dll` to be placed in the Wine prefix's
  `windows/system32/` folder (see SETUP.md).

---

## Rosetta 2 variables

### `ROSETTA_ADVERTISE_AVX`

```sh
ROSETTA_ADVERTISE_AVX=1
```

Tells Rosetta 2 to **advertise AVX instruction set support** to translated
x86_64 code.

- Only effective on **macOS 15 Sequoia** or later.
- Some games query `cpuid` at startup and refuse to run if AVX is not
  advertised — even if they never actually use AVX instructions.
- Set `advertise_avx: true` per-game if you get a CPU compatibility error.
- **Does not make Rosetta execute AVX instructions** — it only changes what
  is reported to the game's CPU feature detection code.

---

## Metal / GPU variables

### `MTL_HUD_ENABLED`

```sh
MTL_HUD_ENABLED=1
```

Shows the **Metal Performance HUD** overlay while the game runs.

Displays:
- GPU utilisation
- Frame time
- Memory usage
- API call count

Useful for performance profiling. Set `show_hud: true` per-game or
`global_hud: true` in AppConfig.

---

## The `arch -x86_64` flag

This is not an environment variable but a critical part of the launch command.

```sh
arch -x86_64 wine64 game.exe
```

On Apple Silicon, macOS will try to run binaries with their native ARM64 slice
if available. `arch -x86_64` forces the OS to use the **x86_64 slice** and run
it through **Rosetta 2**.

This is required because:
1. GPTK's `wine64` is compiled for x86_64 only
2. Rosetta 2 provides the x86_64 → ARM64 instruction translation layer that
   GPTK's CPU emulation builds upon

Without this flag, `wine64` would fail to launch on ARM64 Macs.
