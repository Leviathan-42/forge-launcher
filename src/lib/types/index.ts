export type GraphicsBackend =
  | "d3dmetal"
  | "dxvk"
  | "vkd3d"
  | "dxvk_vkd3d"
  | "wine_builtin"
  | "none";

export type Bottle = {
  id: string;
  name: string;
  prefix_path: string;
  runtime_profile_id: string;
  graphics_backend?: GraphicsBackend | null;
  env_overrides?: Record<string, string>;
  exists: boolean;
  steam_installed: boolean;
  app_count: number;
};

export type LauncherStatus = {
  prefix_path: string;
  prefix_exists: boolean;
  steam_installed: boolean;
  steam_path: string | null;
};

export type BottleApp = {
  id: string;
  name: string;
  path: string;
  kind: "launcher" | "app" | "setup" | "tool" | string;
};

export type AppConfig = {
  wine64_path: string;
  gptk_lib_path: string;
  default_prefix: string;
  suppress_wine_debug: boolean;
  theme: "dark" | "light" | "system" | string;
  global_hud: boolean;
  metalfx_enabled: boolean;
  env?: Record<string, string>;
};

export type WineStatus = {
  installed: boolean;
  path: string | null;
  gptk_lib: string | null;
  message: string | null;
};

export type Game = {
  id: string;
  name: string;
  exe_path: string;
  working_dir?: string | null;
  wine_prefix?: string | null;
  source?: "manual" | "steam" | string;
  steam_app_id?: number | null;
  env_overrides?: Record<string, string>;
};
