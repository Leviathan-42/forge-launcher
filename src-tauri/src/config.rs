//! config.rs — Persistent configuration for the launcher.
//!
//! Two JSON files live under `$HOME/Library/Application Support/<bundle-id>/`:
//!
//! | File          | Purpose                                              |
//! |---------------|------------------------------------------------------|
//! | `config.json` | Global launcher settings (paths, defaults, theme)    |
//! | `games.json`  | User's game library                                  |
//!
//! Both files are created with safe defaults on first run.

use serde::{Deserialize, Serialize};
use std::collections::HashMap;
use std::path::PathBuf;
use tauri::{AppHandle, Manager};

pub const DEFAULT_RUNTIME_PROFILE_ID: &str = "wine-vulkan";
pub const DEFAULT_RUNTIME_PROFILE_NAME: &str = "Forge Wine 11 + MoltenVK";
pub const LEGACY_GPTK_RUNTIME_PROFILE_ID: &str = "gptk-d3dmetal";

// ---------------------------------------------------------------------------
// Game — one entry in the library
// ---------------------------------------------------------------------------

/// Translation backend to use for a specific game.
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
#[serde(rename_all = "lowercase")]
pub enum TranslationBackend {
    /// Apple's D3DMetal (best for DX12, requires GPTK).
    D3DMetal,
    /// DXVK (Vulkan-based; use MoltenVK on macOS, better DX9/10/11 compat).
    Dxvk,
    /// Vanilla Wine translation — no D3D override at all.
    None,
}

impl Default for TranslationBackend {
    fn default() -> Self {
        TranslationBackend::D3DMetal
    }
}

/// Source of the game entry so the UI can show the right badge/icon.
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
#[serde(rename_all = "lowercase")]
pub enum GameSource {
    /// Manually added .exe
    Manual,
    /// Imported from the local Steam library
    Steam,
}

impl Default for GameSource {
    fn default() -> Self {
        GameSource::Manual
    }
}

/// A single game in the user's library.
///
/// All fields use `#[serde(default)]` so that older `games.json` files without
/// newer optional fields still deserialise cleanly.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Game {
    /// UUID v4 — stable primary key used as the process map key.
    pub id: String,

    /// Human-readable display name.
    pub name: String,

    /// Absolute path to the Windows .exe on disk.
    pub exe_path: String,

    /// Working directory passed to Wine. Defaults to the .exe's parent dir.
    #[serde(default)]
    pub working_dir: Option<String>,

    /// Optional path to a cover art image (PNG/JPG). Shown in the library.
    #[serde(default)]
    pub cover_art: Option<String>,

    /// Wine prefix (bottle) this game uses.
    /// Falls back to `AppConfig::default_prefix` when `None`.
    #[serde(default)]
    pub wine_prefix: Option<String>,

    /// Additional CLI arguments forwarded to the .exe after `wine64 <exe>`.
    #[serde(default)]
    pub extra_args: Vec<String>,

    /// Which D3D translation layer to use.
    #[serde(default)]
    pub translation_backend: TranslationBackend,

    /// Show the Metal Performance Shader HUD overlay while the game runs.
    #[serde(default)]
    pub show_hud: bool,

    /// Enable ESYNC (eventfd-based synchronisation). Usually improves perf.
    #[serde(default = "default_true")]
    pub esync: bool,

    /// Enable MSYNC (mach semaphore sync). macOS-specific; try if esync fails.
    #[serde(default)]
    pub msync: bool,

    /// Advertise AVX support to the game via Rosetta (macOS 15+).
    #[serde(default)]
    pub advertise_avx: bool,

    /// Enable DirectX Raytracing via D3DMetal (M3 Macs only).
    #[serde(default)]
    pub enable_dxr: bool,

    /// Where this game came from (manual or Steam import).
    #[serde(default)]
    pub source: GameSource,

    /// Steam AppID — populated when `source == GameSource::Steam`.
    #[serde(default)]
    pub steam_app_id: Option<u64>,

    /// Freeform user notes shown in the detail panel.
    #[serde(default)]
    pub notes: String,

    /// Total seconds played (updated when the child process exits).
    #[serde(default)]
    pub playtime_secs: u64,

    /// Save file mappings for syncing between macOS and the Wine prefix.
    /// Each entry maps a macOS-side save directory to its Wine-prefix location.
    /// Saves are synced TO the prefix before launch and FROM the prefix after exit.
    #[serde(default)]
    pub save_mappings: Vec<crate::saves::SaveMapping>,

    /// Enable MangoHud performance overlay (FPS, CPU, GPU, RAM, VRAM).
    /// Only effective when using DXVK + MoltenVK (Vulkan pipeline).
    /// Requires `brew install mangohud`.
    /// For D3DMetal games, use `show_hud` (MTL_HUD_ENABLED) instead.
    #[serde(default)]
    pub mangohud_enabled: bool,

    /// Optional per-app environment overrides applied last at launch time.
    #[serde(default)]
    pub env_overrides: HashMap<String, String>,
}

fn default_true() -> bool {
    true
}

// ---------------------------------------------------------------------------
// AppConfig — global launcher settings
// ---------------------------------------------------------------------------

/// Global launcher settings persisted to `config.json`.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct AppConfig {
    /// Absolute path to the `wine64` binary from GPTK/Homebrew.
    ///
    /// Default: `/usr/local/bin/wine64`
    /// (x86_64 Homebrew; adjust to your GPTK install location)
    #[serde(default = "default_wine64_path")]
    pub wine64_path: String,

    /// GPTK external libraries directory containing:
    /// - `D3DMetal.framework/`
    /// - `libd3dshared.dylib`
    ///
    /// Default: `/usr/local/lib/external` (standard GPTK Homebrew install)
    #[serde(default = "default_gptk_lib_path")]
    pub gptk_lib_path: String,

    /// Default Wine prefix used when a game does not specify one.
    #[serde(default = "default_wine_prefix")]
    pub default_prefix: String,

    /// Suppress all Wine debug output (WINEDEBUG=-all).
    /// Set to false to get verbose output during troubleshooting.
    #[serde(default = "default_true")]
    pub suppress_wine_debug: bool,

    /// UI theme: "dark" | "light" | "system"
    #[serde(default = "default_theme")]
    pub theme: String,

    /// Show the Metal HUD globally for all games (can be overridden per-game).
    #[serde(default)]
    pub global_hud: bool,

    /// Enable MetalFX upscaling globally (GPTK 3.0+).
    #[serde(default)]
    pub metalfx_enabled: bool,

    /// Global launch environment variables. Applied before runtime/bottle/app env.
    #[serde(default)]
    pub env: HashMap<String, String>,
}

impl Default for AppConfig {
    fn default() -> Self {
        AppConfig {
            wine64_path: default_wine64_path(),
            gptk_lib_path: default_gptk_lib_path(),
            default_prefix: default_wine_prefix(),
            suppress_wine_debug: true,
            theme: default_theme(),
            global_hud: false,
            metalfx_enabled: false,
            env: HashMap::new(),
        }
    }
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
pub enum GraphicsBackend {
    #[serde(rename = "d3dmetal")]
    D3DMetal,
    #[serde(rename = "dxvk")]
    Dxvk,
    #[serde(rename = "vkd3d")]
    Vkd3d,
    #[serde(rename = "dxvk_vkd3d")]
    DxvkVkd3d,
    #[serde(rename = "wine_builtin")]
    WineBuiltin,
    #[serde(rename = "none")]
    None,
}

impl Default for GraphicsBackend {
    fn default() -> Self {
        GraphicsBackend::D3DMetal
    }
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct RuntimeProfile {
    pub id: String,
    pub name: String,
    pub wine64_path: String,
    #[serde(default)]
    pub wineserver_path: Option<String>,
    #[serde(default)]
    pub gptk_lib_path: Option<String>,
    #[serde(default)]
    pub dxvk_path: Option<String>,
    #[serde(default)]
    pub vkd3d_path: Option<String>,
    #[serde(default)]
    pub moltenvk_path: Option<String>,
    #[serde(default)]
    pub default_backend: GraphicsBackend,
    #[serde(default)]
    pub env: HashMap<String, String>,
}

pub fn detect_wine64() -> Option<String> {
    let home = std::env::var("HOME").unwrap_or_default();

    let candidates = [
        // ARM Homebrew (GPTK 3.0 cask from Gcenx or Apple's tap)
        "/opt/homebrew/bin/wine64".to_string(),
        // Intel Homebrew
        "/usr/local/bin/wine64".to_string(),
        // WhiskyWine (bundled with old Whisky installs)
        format!(
            "{}/Library/Application Support/com.isaacmarovitz.Whisky/Libraries/Wine/bin/wine64",
            home
        ),
        format!(
            "{}/Library/Application Support/Whisky/Libraries/Wine/bin/wine64",
            home
        ),
    ];

    for path in &candidates {
        if std::path::Path::new(path).exists() {
            return Some(path.clone());
        }
    }

    // Last resort: check PATH
    if let Ok(out) = std::process::Command::new("which").arg("wine64").output() {
        if out.status.success() {
            let p = String::from_utf8_lossy(&out.stdout).trim().to_string();
            if !p.is_empty() && std::path::Path::new(&p).exists() {
                return Some(p);
            }
        }
    }

    None
}

/// Detect the GPTK external lib directory for D3DMetal / libd3dshared.
/// Returns None if GPTK is not installed.
pub fn detect_gptk_lib_path() -> Option<String> {
    let candidates = [
        // Gcenx GPTK cask app bundle
        "/Applications/Game Porting Toolkit.app/Contents/Resources/wine/lib/external",
        // ARM Homebrew GPTK installs
        "/opt/homebrew/lib/external",
        "/opt/homebrew/opt/game-porting-toolkit/lib/external",
        // Intel Homebrew GPTK installs
        "/usr/local/lib/external",
        "/usr/local/opt/game-porting-toolkit/lib/external",
    ];

    for path in &candidates {
        if std::path::Path::new(path).exists() {
            return Some(path.to_string());
        }
    }

    None
}

fn default_wine64_path() -> String {
    detect_wine10_plus()
        .or_else(detect_wine64)
        .unwrap_or_else(|| {
            "/Applications/Wine Devel.app/Contents/Resources/wine/bin/wine".to_string()
        })
}

fn default_gptk_lib_path() -> String {
    detect_gptk_lib_path().unwrap_or_else(|| "/opt/homebrew/lib/external".to_string())
}

fn default_wine_prefix() -> String {
    let home = std::env::var("HOME").unwrap_or_else(|_| "/tmp".to_string());
    format!("{}/Wine/Bottles/default", home)
}

fn default_theme() -> String {
    "system".to_string()
}

// ---------------------------------------------------------------------------
// Helpers — file paths
// ---------------------------------------------------------------------------

fn app_data_dir(app: &AppHandle) -> Result<PathBuf, String> {
    let dir = app
        .path()
        .app_data_dir()
        .map_err(|e| format!("Cannot resolve app data dir: {}", e))?;
    std::fs::create_dir_all(&dir).map_err(|e| format!("Cannot create app data dir: {}", e))?;
    Ok(dir)
}

fn games_path(app: &AppHandle) -> Result<PathBuf, String> {
    Ok(app_data_dir(app)?.join("games.json"))
}

fn config_path(app: &AppHandle) -> Result<PathBuf, String> {
    Ok(app_data_dir(app)?.join("config.json"))
}

fn runtime_profiles_path(app: &AppHandle) -> Result<PathBuf, String> {
    Ok(app_data_dir(app)?.join("runtime_profiles.json"))
}

// ---------------------------------------------------------------------------
// Public API
// ---------------------------------------------------------------------------

/// Load games from disk. Returns an empty Vec on first run (no file yet).
pub fn load_games(app: &AppHandle) -> Result<Vec<Game>, String> {
    let path = games_path(app)?;
    if !path.exists() {
        return Ok(Vec::new());
    }
    let raw = std::fs::read_to_string(&path).map_err(|e| format!("Read games.json: {}", e))?;
    serde_json::from_str(&raw).map_err(|e| format!("Parse games.json: {}", e))
}

/// Persist the full game list, pretty-printed for human readability.
pub fn save_games(app: &AppHandle, games: &[Game]) -> Result<(), String> {
    let path = games_path(app)?;
    let json =
        serde_json::to_string_pretty(games).map_err(|e| format!("Serialise games: {}", e))?;
    std::fs::write(&path, json).map_err(|e| format!("Write games.json: {}", e))
}

/// Load global config. Returns safe defaults when no file exists.
///
/// On first run (no config.json), auto-detects the wine64 and GPTK paths,
/// persists them immediately, and returns the populated config.
pub fn load_config(app: &AppHandle) -> Result<AppConfig, String> {
    let path = config_path(app)?;
    if !path.exists() {
        // First run — build defaults with auto-detected paths and save them
        let cfg = AppConfig::default(); // default() already calls detect_wine64()
                                        // Save immediately so the user can see and edit the detected paths
        let _ = save_config(app, &cfg);
        return Ok(cfg);
    }
    let raw = std::fs::read_to_string(&path).map_err(|e| format!("Read config.json: {}", e))?;
    let mut cfg: AppConfig =
        serde_json::from_str(&raw).map_err(|e| format!("Parse config.json: {}", e))?;

    // Keep Forge-owned runtimes on the newest installed Forge build, while
    // leaving explicit custom/Wine Devel paths alone.
    if let Some(default_wine) = detect_wine10_plus() {
        let default_is_forge_runtime = default_wine.contains("/Wine/Runtimes/forge-wine-11");
        let cfg_is_forge_runtime = cfg.wine64_path.contains("/Wine/Runtimes/forge-wine-11");
        if default_is_forge_runtime
            && (cfg_is_forge_runtime || !std::path::Path::new(&cfg.wine64_path).exists())
            && cfg.wine64_path != default_wine
        {
            cfg.wine64_path = default_wine;
            let _ = save_config(app, &cfg);
        }
    }

    Ok(cfg)
}

/// Persist global config.
pub fn save_config(app: &AppHandle, cfg: &AppConfig) -> Result<(), String> {
    let path = config_path(app)?;
    let json = serde_json::to_string_pretty(cfg).map_err(|e| format!("Serialise config: {}", e))?;
    std::fs::write(&path, json).map_err(|e| format!("Write config.json: {}", e))
}

pub fn default_runtime_profiles(_cfg: &AppConfig) -> Vec<RuntimeProfile> {
    let moltenvk_path = detect_moltenvk_path();
    let mut env = HashMap::new();
    if let Some(icd) = detect_moltenvk_icd_path() {
        env.insert("VK_ICD_FILENAMES".to_string(), icd);
    }

    let profiles = vec![RuntimeProfile {
        id: DEFAULT_RUNTIME_PROFILE_ID.to_string(),
        name: DEFAULT_RUNTIME_PROFILE_NAME.to_string(),
        wine64_path: detect_wine10_plus().unwrap_or_else(|| {
            "/Applications/Wine Devel.app/Contents/Resources/wine/bin/wine".to_string()
        }),
        wineserver_path: None,
        gptk_lib_path: None,
        dxvk_path: None,
        vkd3d_path: None,
        moltenvk_path: moltenvk_path.clone(),
        default_backend: GraphicsBackend::DxvkVkd3d,
        env: env.clone(),
    }];

    profiles
}

pub fn load_runtime_profiles(app: &AppHandle) -> Result<Vec<RuntimeProfile>, String> {
    let path = runtime_profiles_path(app)?;
    if !path.exists() {
        let profiles = default_runtime_profiles(&load_config(app)?);
        save_runtime_profiles(app, &profiles)?;
        return Ok(profiles);
    }

    let raw =
        std::fs::read_to_string(&path).map_err(|e| format!("Read runtime_profiles.json: {}", e))?;
    let mut profiles: Vec<RuntimeProfile> =
        serde_json::from_str(&raw).map_err(|e| format!("Parse runtime_profiles.json: {}", e))?;

    let defaults = default_runtime_profiles(&load_config(app)?);
    profiles.retain(|profile| profile.id == DEFAULT_RUNTIME_PROFILE_ID);
    for default in defaults {
        if let Some(existing) = profiles.iter_mut().find(|profile| profile.id == default.id) {
            let default_is_forge_runtime =
                default.wine64_path.contains("/Wine/Runtimes/forge-wine-11");
            if !std::path::Path::new(&existing.wine64_path).exists()
                || existing.name == "Wine Vulkan"
                || existing.name.contains("Wine 10")
                || (default_is_forge_runtime && existing.wine64_path != default.wine64_path)
            {
                existing.name = default.name.clone();
                existing.wine64_path = default.wine64_path.clone();
            }
            existing.default_backend = GraphicsBackend::DxvkVkd3d;
            existing.moltenvk_path = existing.moltenvk_path.clone().or(default.moltenvk_path);
            for (key, value) in default.env {
                existing.env.entry(key).or_insert(value);
            }
        } else {
            profiles.push(default);
        }
    }
    save_runtime_profiles(app, &profiles)?;
    Ok(profiles)
}

pub fn save_runtime_profiles(app: &AppHandle, profiles: &[RuntimeProfile]) -> Result<(), String> {
    let path = runtime_profiles_path(app)?;
    let json = serde_json::to_string_pretty(profiles)
        .map_err(|e| format!("Serialise runtime profiles: {}", e))?;
    std::fs::write(&path, json).map_err(|e| format!("Write runtime_profiles.json: {}", e))
}

pub fn runtime_profile_by_id(app: &AppHandle, id: &str) -> Result<RuntimeProfile, String> {
    load_runtime_profiles(app)?
        .into_iter()
        .find(|profile| profile.id == id)
        .ok_or_else(|| format!("Runtime profile '{}' not found", id))
}

fn detect_wine10_plus() -> Option<String> {
    let home = std::env::var("HOME").unwrap_or_default();
    let candidates = [
        // Forge-owned Wine 11 runtime. This must stay independent of any paid app runtime.
        format!("{}/Wine/Runtimes/forge-wine-11-full/bin/wine", home),
        format!("{}/Wine/Runtimes/forge-wine-11/bin/wine", home),
        "/Applications/Wine Devel.app/Contents/Resources/wine/bin/wine".to_string(),
        "/Applications/Wine Stable.app/Contents/Resources/wine/bin/wine".to_string(),
        "/Applications/Wine Staging.app/Contents/Resources/wine/bin/wine".to_string(),
    ];

    candidates
        .into_iter()
        .find(|path| std::path::Path::new(path).exists())
}

fn detect_moltenvk_path() -> Option<String> {
    [
        "/opt/homebrew/lib/libMoltenVK.dylib",
        "/usr/local/lib/libMoltenVK.dylib",
        "/opt/homebrew/opt/molten-vk/lib/libMoltenVK.dylib",
        "/usr/local/opt/molten-vk/lib/libMoltenVK.dylib",
    ]
    .into_iter()
    .find(|path| std::path::Path::new(path).exists())
    .map(|path| path.to_string())
}

fn detect_moltenvk_icd_path() -> Option<String> {
    [
        "/opt/homebrew/opt/molten-vk/etc/vulkan/icd.d/MoltenVK_icd.json",
        "/usr/local/opt/molten-vk/etc/vulkan/icd.d/MoltenVK_icd.json",
        "/opt/homebrew/etc/vulkan/icd.d/MoltenVK_icd.json",
        "/usr/local/etc/vulkan/icd.d/MoltenVK_icd.json",
    ]
    .into_iter()
    .find(|path| std::path::Path::new(path).exists())
    .map(|path| path.to_string())
}
