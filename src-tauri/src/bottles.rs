use serde::{Deserialize, Serialize};
use std::collections::{HashMap, HashSet};
use std::path::{Path, PathBuf};
use std::process::Command;
use tauri::{AppHandle, Manager};

use crate::config::{
    self, GraphicsBackend, DEFAULT_RUNTIME_PROFILE_ID, LEGACY_GPTK_RUNTIME_PROFILE_ID,
};
use crate::launcher::{self, LaunchOptions};

const STEAM_SAFE_CEF_ARGS: [&str; 2] = ["-no-cef-sandbox", "-cef-disable-sandbox"];

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Bottle {
    pub id: String,
    pub name: String,
    pub prefix_path: String,
    pub runtime_profile_id: String,
    pub graphics_backend: Option<GraphicsBackend>,
    pub env_overrides: HashMap<String, String>,
    pub exists: bool,
    pub steam_installed: bool,
    pub app_count: usize,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct BottleRegistryEntry {
    pub name: String,
    pub prefix_path: String,
    #[serde(default = "default_runtime_profile_id")]
    pub runtime_profile_id: String,
    #[serde(default)]
    pub graphics_backend: Option<GraphicsBackend>,
    #[serde(default)]
    pub env_overrides: HashMap<String, String>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct LauncherStatus {
    pub prefix_path: String,
    pub prefix_exists: bool,
    pub steam_installed: bool,
    pub steam_path: Option<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct BottleApp {
    pub id: String,
    pub name: String,
    pub path: String,
    pub kind: String,
}

pub fn list_bottles(app: &AppHandle) -> Result<Vec<Bottle>, String> {
    let cfg = config::load_config(app)?;
    let games = config::load_games(app).unwrap_or_default();
    let mut registry = load_registry(app)?;

    if registry.is_empty() {
        registry.push(BottleRegistryEntry {
            name: "Default".to_string(),
            prefix_path: cfg.default_prefix.clone(),
            runtime_profile_id: default_runtime_profile_id(),
            graphics_backend: None,
            env_overrides: HashMap::new(),
        });
        save_registry(app, &registry)?;
    }

    let mut seen = HashSet::new();
    let mut entries = Vec::new();

    for entry in registry {
        let normalized = normalize_path(&entry.prefix_path);
        if seen.insert(normalized.clone()) {
            entries.push(BottleRegistryEntry {
                name: entry.name,
                prefix_path: normalized,
                runtime_profile_id: entry.runtime_profile_id,
                graphics_backend: entry.graphics_backend,
                env_overrides: entry.env_overrides,
            });
        }
    }

    for game in games {
        if let Some(prefix) = game.wine_prefix {
            let normalized = normalize_path(&prefix);
            if seen.insert(normalized.clone()) {
                entries.push(BottleRegistryEntry {
                    name: bottle_name_from_path(&normalized),
                    prefix_path: normalized,
                    runtime_profile_id: default_runtime_profile_id(),
                    graphics_backend: None,
                    env_overrides: HashMap::new(),
                });
            }
        }
    }

    if !seen.contains(&normalize_path(&cfg.default_prefix)) {
        entries.insert(
            0,
            BottleRegistryEntry {
                name: "Default".to_string(),
                prefix_path: normalize_path(&cfg.default_prefix),
                runtime_profile_id: default_runtime_profile_id(),
                graphics_backend: None,
                env_overrides: HashMap::new(),
            },
        );
    }

    Ok(entries.into_iter().map(to_bottle).collect())
}

pub fn create_bottle(
    app: &AppHandle,
    name: String,
    prefix_path: Option<String>,
) -> Result<Vec<Bottle>, String> {
    let cfg = config::load_config(app)?;
    let clean_name = if name.trim().is_empty() {
        "New Bottle".to_string()
    } else {
        name.trim().to_string()
    };

    let prefix = prefix_path
        .filter(|p| !p.trim().is_empty())
        .unwrap_or_else(|| default_prefix_for_name(&cfg.default_prefix, &clean_name));
    let prefix = normalize_path(&prefix);

    launcher::init_wine_prefix(&prefix, &cfg.wine64_path)?;

    let mut registry = load_registry(app)?;
    if let Some(existing) = registry
        .iter_mut()
        .find(|entry| normalize_path(&entry.prefix_path) == prefix)
    {
        existing.name = clean_name;
    } else {
        registry.push(BottleRegistryEntry {
            name: clean_name,
            prefix_path: prefix,
            runtime_profile_id: default_runtime_profile_id(),
            graphics_backend: None,
            env_overrides: HashMap::new(),
        });
    }
    save_registry(app, &registry)?;

    list_bottles(app)
}

pub fn update_bottle_runtime(
    app: &AppHandle,
    prefix_path: String,
    runtime_profile_id: String,
    graphics_backend: Option<GraphicsBackend>,
    env_overrides: Option<HashMap<String, String>>,
    force: bool,
) -> Result<Vec<Bottle>, String> {
    let prefix = normalize_path(&prefix_path);
    let new_profile = config::runtime_profile_by_id(app, &runtime_profile_id)?;
    let mut registry = load_registry(app)?;
    let entry = registry
        .iter_mut()
        .find(|entry| normalize_path(&entry.prefix_path) == prefix)
        .ok_or_else(|| format!("Bottle not registered: {}", prefix))?;

    if !force && Path::new(&prefix).join("drive_c").exists() {
        let old_profile = config::runtime_profile_by_id(app, &entry.runtime_profile_id).ok();
        if old_profile.as_ref().map(|p| p.id.as_str()) == Some(LEGACY_GPTK_RUNTIME_PROFILE_ID)
            && new_profile.id != LEGACY_GPTK_RUNTIME_PROFILE_ID
        {
            return Err(
                "Safety warning: this bottle already exists and was using GPTK/D3DMetal. \
                 Switching it to the Wine 11 + MoltenVK profile may modify the prefix. \
                 Create a cloned/test bottle instead, or retry with force=true."
                    .to_string(),
            );
        }
    }

    entry.runtime_profile_id = runtime_profile_id;
    entry.graphics_backend = graphics_backend;
    if let Some(env) = env_overrides {
        entry.env_overrides = env;
    }
    save_registry(app, &registry)?;
    list_bottles(app)
}

pub fn create_peak_test_bottle(app: &AppHandle) -> Result<Vec<Bottle>, String> {
    let cfg = config::load_config(app)?;
    let prefix = default_prefix_for_name(&cfg.default_prefix, "PEAK Test");
    let profile = config::runtime_profile_by_id(app, DEFAULT_RUNTIME_PROFILE_ID)?;
    launcher::init_wine_prefix(&prefix, &profile.wine64_path)?;

    let mut registry = load_registry(app)?;
    if let Some(existing) = registry
        .iter_mut()
        .find(|entry| normalize_path(&entry.prefix_path) == normalize_path(&prefix))
    {
        existing.name = "PEAK Test".to_string();
        existing.runtime_profile_id = DEFAULT_RUNTIME_PROFILE_ID.to_string();
        existing.graphics_backend = Some(GraphicsBackend::DxvkVkd3d);
    } else {
        registry.push(BottleRegistryEntry {
            name: "PEAK Test".to_string(),
            prefix_path: prefix,
            runtime_profile_id: DEFAULT_RUNTIME_PROFILE_ID.to_string(),
            graphics_backend: Some(GraphicsBackend::DxvkVkd3d),
            env_overrides: HashMap::new(),
        });
    }
    save_registry(app, &registry)?;
    list_bottles(app)
}

pub fn launcher_status(prefix_path: &str) -> LauncherStatus {
    let prefix = normalize_path(prefix_path);
    let steam_path = find_steam_exe(&prefix);
    LauncherStatus {
        prefix_exists: Path::new(&prefix).is_dir(),
        prefix_path: prefix,
        steam_installed: steam_path.is_some(),
        steam_path,
    }
}

pub fn list_apps(prefix_path: &str) -> Vec<BottleApp> {
    let prefix = normalize_path(prefix_path);
    let mut apps = Vec::new();
    let mut seen = HashSet::new();

    for path in known_launcher_paths(&prefix) {
        if path.is_file() {
            push_app(&mut apps, &mut seen, path, "launcher");
        }
    }

    for root in program_roots(&prefix) {
        collect_exes(&root, 0, &mut apps, &mut seen);
        if apps.len() >= 120 {
            break;
        }
    }

    apps.sort_by(|a, b| {
        rank_kind(&a.kind)
            .cmp(&rank_kind(&b.kind))
            .then_with(|| a.name.to_lowercase().cmp(&b.name.to_lowercase()))
    });
    apps.truncate(120);
    apps
}

pub fn install_steam(app: &AppHandle, prefix_path: String) -> Result<(), String> {
    let installer = steam_installer_path(app)?;
    if !installer.is_file() {
        download_steam_installer(&installer)?;
    }
    run_exe(
        app,
        prefix_path,
        installer.to_string_lossy().to_string(),
        Vec::new(),
    )
}

fn steam_safe_args(extra: Vec<String>) -> Vec<String> {
    // Keep only the sandbox-safe args. Over-forcing CEF GPU flags can make
    // Chromium pick stranger paths under Wine.
    let mut args = STEAM_SAFE_CEF_ARGS.map(str::to_string).to_vec();
    args.extend(extra);
    args
}

pub fn open_steam(app: &AppHandle, prefix_path: String) -> Result<(), String> {
    let status = launcher_status(&prefix_path);
    let steam_path = status
        .steam_path
        .ok_or_else(|| "Windows Steam is not installed in this bottle yet.".to_string())?;
    run_exe(
        app,
        status.prefix_path,
        steam_path,
        steam_safe_args(Vec::new()),
    )
}

pub fn repair_steam(app: &AppHandle, prefix_path: String) -> Result<(), String> {
    let status = launcher_status(&prefix_path);
    let steam_path = status
        .steam_path
        .ok_or_else(|| "Windows Steam is not installed in this bottle yet.".to_string())?;
    run_exe(
        app,
        status.prefix_path,
        steam_path,
        steam_safe_args(vec!["-repair".to_string()]),
    )
}

pub fn run_exe(
    app: &AppHandle,
    prefix_path: String,
    exe_path: String,
    args: Vec<String>,
) -> Result<(), String> {
    let opts = resolve_launch_options(app, &prefix_path, &exe_path, args, &HashMap::new())?;
    let _process = launcher::spawn(opts)?;
    Ok(())
}

pub fn resolve_launch_options(
    app: &AppHandle,
    prefix_path: &str,
    exe_path: &str,
    args: Vec<String>,
    app_env_overrides: &HashMap<String, String>,
) -> Result<LaunchOptions, String> {
    let cfg = config::load_config(app)?;
    let prefix = normalize_path(prefix_path);
    let exe = normalize_path(exe_path);
    if !Path::new(&exe).is_file() {
        return Err(format!("Executable not found: {}", exe));
    }

    let entry = bottle_entry_for_prefix(app, &prefix)?;
    let profile = config::runtime_profile_by_id(app, &entry.runtime_profile_id)?;
    let backend = entry
        .graphics_backend
        .clone()
        .unwrap_or_else(|| profile.default_backend.clone());
    let is_steam_client = Path::new(&exe)
        .file_name()
        .and_then(|name| name.to_str())
        .map(|name| name.eq_ignore_ascii_case("steam.exe"))
        .unwrap_or(false);
    let gptk_lib_path = profile
        .gptk_lib_path
        .clone()
        .unwrap_or_else(|| cfg.gptk_lib_path.clone());
    let mut env = launcher::merge_env(
        &cfg.env,
        &profile.env,
        &entry.env_overrides,
        app_env_overrides,
    );
    let wine64_path = profile.wine64_path;
    let launch_exe = exe.clone();
    let launch_prefix = prefix;
    let working_dir = Path::new(&exe)
        .parent()
        .map(|path| path.to_string_lossy().to_string());

    if is_steam_client {
        // Steam should inherit the bottle's performance backend so games
        // launched from inside Steam can use GPU acceleration. The Steam UI
        // black-screen fix is handled inside Forge's Wine build by appending
        // safe CEF flags only to steamwebhelper.exe child processes; do not
        // globally hide Vulkan/DXVK from steam.exe here.
        env.insert("MOLTENVK_CONFIG_LOG_LEVEL".to_string(), "0".to_string());
    }

    Ok(LaunchOptions {
        wine64_path,
        exe_path: launch_exe,
        working_dir,
        wine_prefix: launch_prefix,
        gptk_lib_path,
        extra_args: if is_steam_client {
            steam_safe_args(args)
        } else {
            args
        },
        graphics_backend: backend,
        env,
        esync: true,
        msync: is_steam_client,
        show_hud: cfg.global_hud,
        metal_trace: false,
        advertise_avx: false,
        enable_dxr: false,
        metalfx_enabled: cfg.metalfx_enabled,
        dxvk_hud: Default::default(),
        mangohud_enabled: false,
        wine_debug: if cfg.suppress_wine_debug {
            "fixme-all".to_string()
        } else {
            String::new()
        },
    })
}

fn to_bottle(entry: BottleRegistryEntry) -> Bottle {
    let prefix_path = normalize_path(&entry.prefix_path);
    Bottle {
        id: format!("{}-{:x}", slug(&entry.name), stable_hash(&prefix_path)),
        name: entry.name,
        runtime_profile_id: entry.runtime_profile_id,
        graphics_backend: entry.graphics_backend,
        env_overrides: entry.env_overrides,
        exists: Path::new(&prefix_path).is_dir(),
        steam_installed: find_steam_exe(&prefix_path).is_some(),
        app_count: list_apps(&prefix_path).len(),
        prefix_path,
    }
}

fn app_data_dir(app: &AppHandle) -> Result<PathBuf, String> {
    let dir = app
        .path()
        .app_data_dir()
        .map_err(|e| format!("Cannot resolve app data dir: {}", e))?;
    std::fs::create_dir_all(&dir).map_err(|e| format!("Cannot create app data dir: {}", e))?;
    Ok(dir)
}

fn registry_path(app: &AppHandle) -> Result<PathBuf, String> {
    Ok(app_data_dir(app)?.join("bottles.json"))
}

fn load_registry(app: &AppHandle) -> Result<Vec<BottleRegistryEntry>, String> {
    let path = registry_path(app)?;
    if !path.exists() {
        return Ok(Vec::new());
    }

    let raw = std::fs::read_to_string(&path).map_err(|e| format!("Read bottles.json: {}", e))?;
    let mut entries: Vec<BottleRegistryEntry> =
        serde_json::from_str(&raw).map_err(|e| format!("Parse bottles.json: {}", e))?;

    // Forge is now Wine 11 + MoltenVK first. Migrate older GPTK/D3DMetal bottle
    // records to the Vulkan runtime so the UI cannot accidentally launch Steam
    // or games through the old Wine 7.7 GPTK stack.
    for entry in &mut entries {
        entry.runtime_profile_id = DEFAULT_RUNTIME_PROFILE_ID.to_string();
        if entry.graphics_backend == Some(GraphicsBackend::D3DMetal) {
            entry.graphics_backend = Some(GraphicsBackend::DxvkVkd3d);
        }
    }

    Ok(entries)
}

fn bottle_entry_for_prefix(
    app: &AppHandle,
    prefix_path: &str,
) -> Result<BottleRegistryEntry, String> {
    let prefix = normalize_path(prefix_path);
    let cfg = config::load_config(app)?;
    if let Some(entry) = load_registry(app)?
        .into_iter()
        .find(|entry| normalize_path(&entry.prefix_path) == prefix)
    {
        return Ok(entry);
    }

    if normalize_path(&cfg.default_prefix) == prefix {
        return Ok(BottleRegistryEntry {
            name: "Default".to_string(),
            prefix_path: prefix,
            runtime_profile_id: default_runtime_profile_id(),
            graphics_backend: None,
            env_overrides: HashMap::new(),
        });
    }

    Ok(BottleRegistryEntry {
        name: bottle_name_from_path(&prefix),
        prefix_path: prefix,
        runtime_profile_id: default_runtime_profile_id(),
        graphics_backend: None,
        env_overrides: HashMap::new(),
    })
}

fn default_runtime_profile_id() -> String {
    DEFAULT_RUNTIME_PROFILE_ID.to_string()
}

fn save_registry(app: &AppHandle, entries: &[BottleRegistryEntry]) -> Result<(), String> {
    let path = registry_path(app)?;
    let json =
        serde_json::to_string_pretty(entries).map_err(|e| format!("Serialise bottles: {}", e))?;
    std::fs::write(&path, json).map_err(|e| format!("Write bottles.json: {}", e))
}

fn steam_installer_path(app: &AppHandle) -> Result<PathBuf, String> {
    let dir = app
        .path()
        .app_cache_dir()
        .map_err(|e| format!("Cannot resolve app cache dir: {}", e))?
        .join("installers");
    std::fs::create_dir_all(&dir).map_err(|e| format!("Cannot create cache dir: {}", e))?;
    Ok(dir.join("SteamSetup.exe"))
}

fn download_steam_installer(target: &Path) -> Result<(), String> {
    let url = "https://cdn.akamai.steamstatic.com/client/installer/SteamSetup.exe";
    let output = Command::new("curl")
        .args(["-fL", "--max-time", "60", "-o"])
        .arg(target)
        .arg(url)
        .output()
        .map_err(|e| format!("Failed to run curl: {}", e))?;

    if output.status.success() {
        Ok(())
    } else {
        let stderr = String::from_utf8_lossy(&output.stderr);
        Err(format!(
            "Could not download Steam installer: {}",
            stderr.trim()
        ))
    }
}

fn find_steam_exe(prefix_path: &str) -> Option<String> {
    steam_candidates(prefix_path)
        .into_iter()
        .find(|path| path.is_file())
        .map(|path| path.to_string_lossy().to_string())
}

fn steam_candidates(prefix_path: &str) -> Vec<PathBuf> {
    let drive_c = Path::new(prefix_path).join("drive_c");
    vec![
        drive_c.join("Program Files (x86)/Steam/steam.exe"),
        drive_c.join("Program Files/Steam/steam.exe"),
    ]
}

fn known_launcher_paths(prefix_path: &str) -> Vec<PathBuf> {
    let drive_c = Path::new(prefix_path).join("drive_c");
    let mut paths = steam_candidates(prefix_path);
    paths.extend([
        drive_c.join(
            "Program Files (x86)/Epic Games/Launcher/Portal/Binaries/Win64/EpicGamesLauncher.exe",
        ),
        drive_c.join(
            "Program Files (x86)/Epic Games/Launcher/Portal/Binaries/Win32/EpicGamesLauncher.exe",
        ),
        drive_c.join("Program Files (x86)/Battle.net/Battle.net.exe"),
        drive_c.join("Program Files/Battle.net/Battle.net.exe"),
        drive_c.join("Program Files/Electronic Arts/EA Desktop/EA Desktop/EALauncher.exe"),
        drive_c.join("Program Files (x86)/Ubisoft/Ubisoft Game Launcher/UbisoftConnect.exe"),
        drive_c.join("Program Files/Rockstar Games/Launcher/Launcher.exe"),
    ]);
    paths
}

fn program_roots(prefix_path: &str) -> Vec<PathBuf> {
    let drive_c = Path::new(prefix_path).join("drive_c");
    vec![
        drive_c.join("Program Files"),
        drive_c.join("Program Files (x86)"),
        drive_c.join("users/Public/Desktop"),
    ]
}

fn collect_exes(dir: &Path, depth: usize, apps: &mut Vec<BottleApp>, seen: &mut HashSet<String>) {
    if depth > 5 || apps.len() >= 120 || !dir.is_dir() {
        return;
    }

    let Ok(entries) = std::fs::read_dir(dir) else {
        return;
    };

    for entry in entries.filter_map(|entry| entry.ok()) {
        if apps.len() >= 120 {
            break;
        }

        let path = entry.path();
        if path.is_dir() {
            if should_descend_for_user_apps(&path) {
                collect_exes(&path, depth + 1, apps, seen);
            }
        } else if path
            .extension()
            .and_then(|ext| ext.to_str())
            .map(|ext| ext.eq_ignore_ascii_case("exe"))
            .unwrap_or(false)
            && is_user_visible_exe(&path)
        {
            let kind = guess_app_kind(&path);
            push_app(apps, seen, path, &kind);
        }
    }
}

fn should_descend_for_user_apps(path: &Path) -> bool {
    let raw = path.to_string_lossy().replace('\\', "/").to_lowercase();
    !raw.contains("/program files/common files")
        && !raw.contains("/program files (x86)/common files")
        && !raw.contains("/internet explorer")
        && !raw.contains("/windows media player")
        && !raw.contains("/windows nt")
        && !raw.contains("/steam/bin")
}

fn is_user_visible_exe(path: &Path) -> bool {
    let raw = path.to_string_lossy().replace('\\', "/").to_lowercase();
    let file = path
        .file_name()
        .and_then(|name| name.to_str())
        .unwrap_or_default()
        .to_lowercase();

    if raw.contains("/internet explorer/")
        || raw.contains("/windows media player/")
        || raw.contains("/windows nt/")
        || raw.contains("/common files/")
        || raw.contains("/steam/bin/")
    {
        return false;
    }

    // Steam installs lots of helper .exe files beside steam.exe. Show the app
    // the user actually installed, not crash reporters, services, overlays, or
    // driver probes.
    let hidden_helpers = [
        "uninstall.exe",
        "writeminidump.exe",
        "gameoverlayui.exe",
        "gameoverlayui64.exe",
        "steamerrorreporter.exe",
        "steamerrorreporter64.exe",
        "streaming_client.exe",
        "steamsysinfo.exe",
        "steamservice.exe",
        "steamwebhelper.exe",
        "x64launcher.exe",
        "x86launcher.exe",
        "gldriverquery.exe",
        "gldriverquery64.exe",
        "vulkandriverquery.exe",
        "vulkandriverquery64.exe",
        "drivers.exe",
        "secure_desktop_capture.exe",
        "fossilize-replay.exe",
        "fossilize-replay64.exe",
        "steamxboxutil.exe",
        "steamxboxutil64.exe",
        "steam_monitor.exe",
        "hardwareupdater.exe",
    ];

    !hidden_helpers.contains(&file.as_str())
}

fn push_app(
    apps: &mut Vec<BottleApp>,
    seen: &mut HashSet<String>,
    path: PathBuf,
    forced_kind: &str,
) {
    let path_string = path.to_string_lossy().to_string();
    if !seen.insert(path_string.clone()) {
        return;
    }

    let name = app_name(&path);
    apps.push(BottleApp {
        id: format!("{}-{:x}", slug(&name), stable_hash(&path_string)),
        name,
        kind: forced_kind.to_string(),
        path: path_string,
    });
}

fn app_name(path: &Path) -> String {
    let stem = path
        .file_stem()
        .and_then(|stem| stem.to_str())
        .unwrap_or("App");
    match stem.to_lowercase().as_str() {
        "steam" => "Steam".to_string(),
        "epicgameslauncher" => "Epic Games Launcher".to_string(),
        "battle.net" => "Battle.net".to_string(),
        "ealauncher" => "EA App".to_string(),
        "ubisoftconnect" => "Ubisoft Connect".to_string(),
        "launcher" if path.to_string_lossy().contains("Rockstar Games") => {
            "Rockstar Launcher".to_string()
        }
        _ => humanize(stem),
    }
}

fn guess_app_kind(path: &Path) -> String {
    let raw = path.to_string_lossy().to_lowercase();
    if raw.contains("steam")
        || raw.contains("epic games")
        || raw.contains("battle.net")
        || raw.contains("ea desktop")
        || raw.contains("ubisoft")
        || raw.contains("rockstar")
    {
        "launcher".to_string()
    } else if raw.contains("setup") || raw.contains("install") || raw.contains("unins") {
        "setup".to_string()
    } else if raw.contains("redist") || raw.contains("vc_redist") {
        "tool".to_string()
    } else {
        "app".to_string()
    }
}

fn rank_kind(kind: &str) -> u8 {
    match kind {
        "launcher" => 0,
        "app" => 1,
        "setup" => 2,
        "tool" => 3,
        _ => 4,
    }
}

fn default_prefix_for_name(default_prefix: &str, name: &str) -> String {
    let normalized_default = normalize_path(default_prefix);
    let default = Path::new(&normalized_default);
    let base = default
        .parent()
        .map(|path| path.to_path_buf())
        .unwrap_or_else(|| {
            let home = std::env::var("HOME").unwrap_or_else(|_| "/tmp".to_string());
            PathBuf::from(home).join("Wine/Bottles")
        });

    base.join(slug(name)).to_string_lossy().to_string()
}

fn bottle_name_from_path(path: &str) -> String {
    Path::new(path)
        .file_name()
        .and_then(|name| name.to_str())
        .map(humanize)
        .unwrap_or_else(|| "Bottle".to_string())
}

fn normalize_path(path: &str) -> String {
    launcher::expand_tilde(path.trim())
}

fn slug(input: &str) -> String {
    let mut out = String::new();
    for c in input.chars() {
        if c.is_ascii_alphanumeric() {
            out.push(c.to_ascii_lowercase());
        } else if !out.ends_with('-') {
            out.push('-');
        }
    }
    let trimmed = out.trim_matches('-');
    if trimmed.is_empty() {
        "bottle".to_string()
    } else {
        trimmed.to_string()
    }
}

fn humanize(input: &str) -> String {
    let cleaned = input.replace(['_', '-'], " ");
    let mut out = String::new();
    let mut previous_was_lower = false;

    for c in cleaned.chars() {
        if previous_was_lower && c.is_ascii_uppercase() {
            out.push(' ');
        }
        out.push(c);
        previous_was_lower = c.is_ascii_lowercase();
    }

    let trimmed = out.trim();
    if trimmed.is_empty() {
        "App".to_string()
    } else {
        trimmed.to_string()
    }
}

fn stable_hash(input: &str) -> u64 {
    let mut hash = 0xcbf29ce484222325u64;
    for byte in input.as_bytes() {
        hash ^= *byte as u64;
        hash = hash.wrapping_mul(0x100000001b3);
    }
    hash
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn default_prefix_for_name_normalizes_configured_default_prefix() {
        assert_eq!(
            default_prefix_for_name("  /Users/levi/Wine/Bottles/default  ", "PEAK Test"),
            "/Users/levi/Wine/Bottles/peak-test"
        );
    }

    #[test]
    fn slug_falls_back_for_blank_names() {
        assert_eq!(slug("  ---  "), "bottle");
        assert_eq!(slug("Wine 11 + MoltenVK"), "wine-11-moltenvk");
    }
}
