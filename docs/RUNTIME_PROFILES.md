# Runtime Profiles

Forge supports per-bottle runtime profiles so newer Wine runners can be tested without changing existing GPTK bottles.

## Model

```text
RuntimeProfile
  -> Wine runner paths
  -> graphics resource paths
  -> default graphics backend
  -> profile env

Bottle
  -> runtime_profile_id
  -> optional graphics_backend override
  -> optional env_overrides

Launch
  -> resolved LaunchOptions generated at launch time
```

Resolved launch options are not persisted.

## Default profiles

- `gptk-d3dmetal` — current GPTK Wine + D3DMetal compatibility path.
- `wine-vulkan` — intended for Wine 10/11+ with DXVK/VKD3D-Proton/MoltenVK.

If no Wine 10/11 runner is detected, `wine-vulkan` points at the expected Forge/Wine path and launch will fail with a clear missing-wine error until configured.

## Backends

```ts
type GraphicsBackend =
  | "d3dmetal"
  | "dxvk"
  | "vkd3d"
  | "dxvk_vkd3d"
  | "wine_builtin"
  | "none";
```

Backend handling currently resolves env/DLL overrides only. It does not install DXVK, VKD3D-Proton, or MoltenVK into prefixes yet.

## Env merge order

```text
global AppConfig env
runtime profile env
bottle env_overrides
app/game env_overrides
```

Later entries override earlier entries.

## Prefix safety

Forge prevents changing an existing GPTK/D3DMetal bottle to another runtime unless `force=true` is passed to the backend command. Prefer creating a cloned/test bottle for Wine 10/11 experiments.

For PEAK:

```text
Bottle: PEAK Test
Profile: wine-vulkan
Backend: dxvk_vkd3d
```

Existing GPTK/D3DMetal bottles should stay unchanged.
