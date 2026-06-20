# Launch Args and Graphics Backend Notes

Forge is experimental. Launch args are compatibility hints, not guaranteed fixes. The
right settings depend on what renderers the game actually ships and what translation
backend works best on macOS.

## Quick rule of thumb

| Game type | Try backend | Try launch args | Why |
| --- | --- | --- | --- |
| Unity game with native Vulkan support | DXVK/VKD3D or backend that leaves Vulkan available | `-force-vulkan` | Uses the game's own Vulkan renderer, which can go through MoltenVK on macOS. This bypasses D3D11 translation. |
| Unity D3D11-only game | D3DMetal or future DXMT | Usually no renderer-force arg | The game needs Direct3D 11 translated to Metal. Forcing Vulkan/OpenGL will fail if those renderers were not built into the game. |
| D3D9/D3D10/D3D11 game | DXVK | Usually none | DXVK translates Direct3D to Vulkan. On macOS this then goes through MoltenVK. |
| D3D12 game | VKD3D or D3DMetal | Usually none | VKD3D translates D3D12 to Vulkan; D3DMetal translates D3D to Metal. |
| Old/simple DirectX game | WineD3D | Usually none | Wine's builtin Direct3D path can be useful for older games or launchers. |
| Steam game | Launch through Steam if possible | `steam.exe -applaunch <appid>` plus game args | Steamworks/DRM/session APIs often require Steam to launch the game. |

## Important distinction: Vulkan vs DXVK

These are not the same thing.

### Native Vulkan

A game with a native Vulkan renderer can be launched with something like:

```text
-force-vulkan
```

That means:

```text
Game Vulkan renderer -> MoltenVK -> Metal
```

This does **not** use DXVK for the game's graphics API, because the game is not using Direct3D in that mode.

### DXVK

DXVK is for games using Direct3D 9/10/11:

```text
Game D3D11 renderer -> DXVK -> Vulkan -> MoltenVK -> Metal
```

So if a game supports native Vulkan well, forcing Vulkan can avoid DXVK entirely. If a
game is D3D11-only, DXVK may help, but on macOS it depends on whether MoltenVK supports
the Vulkan features DXVK needs for that game.

## Common Unity launch args

### `-force-vulkan`

Use when:

- The game is Unity.
- The game actually ships a working Vulkan renderer.
- D3D11 translation has rendering bugs or fails.

Avoid when:

- The log says Vulkan was not built from the editor.
- Shaders are missing.
- The game crashes immediately after forcing Vulkan.

Known Forge example:

```text
PEAK
-force-vulkan -force-gfx-st -disable-gpu-skinning -screen-fullscreen 1
```

### `-force-d3d11`

Use when:

- A Unity game supports multiple renderers and you specifically want Direct3D 11.
- You are testing D3D11 translation layers such as DXVK, D3DMetal, or DXMT.

Avoid when:

- The game already defaults to D3D11 and the issue is D3D11 device creation.
- You are trying to bypass Direct3D translation entirely.

### `-force-glcore`

Use rarely.

Use when:

- You know the Unity game shipped an OpenGL Core renderer.
- Vulkan/D3D paths are broken.

Avoid when:

- The log says OpenGL Core was not built from the editor.
- The game is modern and likely Windows D3D-only.

### `-force-gfx-st`

Forces single-threaded graphics in Unity.

Use when:

- There are rendering race bugs.
- Character meshes or materials corrupt.
- The game behaves differently frame-to-frame.

Cost:

- Can reduce performance.

### `-disable-gpu-skinning`

Disables Unity GPU skinning.

Use when:

- Animated characters or avatars are corrupted.
- Meshes stretch, explode, or render incorrectly.

Cost:

- Can reduce performance on character-heavy scenes.

Known Forge example:

```text
PEAK avatar corruption was fixed by -disable-gpu-skinning.
```

### `-screen-fullscreen 1`

Starts fullscreen.

Use when:

- The game behaves better in fullscreen.
- Window sizing causes graphics issues.

### `-screen-fullscreen 0`

Starts windowed.

Use when:

- Fullscreen fails.
- You are debugging startup.
- The game opens offscreen or with a broken swapchain.

### `-popupwindow`

Borderless window mode for Unity.

Use with:

```text
-screen-fullscreen 0 -popupwindow
```

Useful when fullscreen swapchains are problematic.

## Backend notes

### DXVK/VKD3D

Good default for many games.

Use for:

- D3D9/D3D10/D3D11 through DXVK.
- D3D12 through VKD3D.

Caveat on macOS:

- DXVK depends on MoltenVK.
- Some D3D11 games require Vulkan features MoltenVK does not expose.

### D3DMetal

Use for:

- D3D11/D3D12 games where Vulkan/DXVK is not viable.
- Games that need a Metal-native translation path.

Caveat:

- GPTK/D3DMetal can be sensitive to Wine runtime/prefix state.
- Mixing different Wine builds in one active prefix can cause wineserver mismatch errors.

### WineD3D

Use for:

- Older games.
- Launchers.
- Debugging when DXVK/D3DMetal fails early.

Caveat:

- Usually slower and less compatible for modern D3D11/D3D12 games.

### None

Use for:

- Apps that do not need Direct3D overrides.
- Debugging native/builtin behavior.

## How to choose settings for a new game

1. Launch with the bottle default backend and no special args.
2. Check the game log.
3. If Unity and D3D11 fails, test whether native Vulkan exists:
   ```text
   -force-vulkan
   ```
4. If the log says Vulkan was not built, stop trying Vulkan for that game.
5. If D3D11 is required, try a D3D11 translation backend:
   ```text
   DXVK -> D3DMetal -> future DXMT
   ```
6. If characters/meshes corrupt, try:
   ```text
   -force-gfx-st -disable-gpu-skinning
   ```
7. If fullscreen fails, try:
   ```text
   -screen-fullscreen 0 -popupwindow
   ```

## Known Forge profiles

### PEAK

Status: working.

Backend:

```text
DXVK/VKD3D
```

Args:

```text
-force-vulkan -force-gfx-st -disable-gpu-skinning -screen-fullscreen 1
```

Why:

- Vulkan path works.
- GPU skinning caused avatar corruption.

### Against the Storm

Status: working through DXMT.

Backend:

```text
DXMT
```

Args:

```text
-screen-fullscreen 1
```

Known facts:

- Against the Storm is a 64-bit Unity D3D11 title.
- Native Vulkan renderer is not usable in this build.
- OpenGL Core renderer is not usable in this build.
- DXVK loads but MoltenVK lacks a required feature for this title.
- DXMT provides the working D3D11 -> Metal path in Forge's own Wine runtime.
- Keep the `dd3d11.dll` alias staged with DXMT; this Unity build probes that DLL name.

Do not use:

```text
-force-vulkan
-force-glcore
```

## Future Forge UI idea

Each game should have its own compatibility profile:

```text
Backend: DXVK/VKD3D, DXVK, VKD3D, DXMT, D3DMetal, WineD3D, None
Launch args: editable text field
Environment overrides: advanced section
Notes: why this profile exists
```

The bottle backend should be only the default. Individual games should be able to override it.
