//! launcher.rs — Wine process spawning, informed by Whisky's source.
//!
//! Key lessons from reading Whisky's Wine.swift + BottleSettings.swift:
//!
//! 1. DO NOT use `arch -x86_64` wrapper.
//!    Wine64 is already an x86_64 binary. Rosetta 2 kicks in automatically
//!    when macOS sees an x86_64 binary on Apple Silicon. The `arch` wrapper
//!    is unnecessary and can cause PATH / environment issues.
//!
//! 2. Use `wine64 start /unix <path>` NOT `wine64 <path>` directly.
//!    `start /unix` is the correct Wine invocation for running a Windows exe
//!    from a Unix path. It sets up the Windows environment properly.
//!
//! 3. MSYNC requires ESYNC=1 too (D3DMetal lie).
//!    D3DMetal detects WINEESYNC and changes its behaviour. When using MSYNC,
//!    you must also set WINEESYNC=1 to keep D3DMetal happy — even though the
//!    actual sync is handled by MSYNC. Values are hardcoded in libd3dshared.dylib.
//!    Source: Whisky BottleSettings.swift environmentVariables()
//!
//! 4. DXVK DLL override must include dxgi and d3d9.
//!    Correct: "dxgi,d3d9,d3d10core,d3d11=n,b"
//!    Wrong:   "d3d11=n,b;d3d10core=n,b"  ← what we had before
//!
//! 5. DXVK_ASYNC=1 should always be set with DXVK.
//!    Avoids shader compilation stutter on first render.
//!
//! 6. WINEDEBUG should be "fixme-all" not "-all".
//!    "-all" is too aggressive — it suppresses Wine errors you'd want to see.
//!    "fixme-all" only suppresses noisy Wine fixme diagnostics while keeping errors.
//!    Whisky also adds GST_DEBUG=1 for GStreamer media pipeline visibility.
//!
//! 7. METAL_CAPTURE_ENABLED for Metal GPU tracing (Whisky's "metal trace" mode).

use std::collections::HashMap;
use std::path::PathBuf;
use std::process::{Child, Command};

use crate::config::{AppConfig, GraphicsBackend};
use crate::steam::SteamGame;

// ---------------------------------------------------------------------------
// DXVK HUD level
// ---------------------------------------------------------------------------

#[derive(Debug, Clone, Default, serde::Serialize, serde::Deserialize, PartialEq)]
#[serde(rename_all = "lowercase")]
pub enum DxvkHud {
    /// No HUD
    #[default]
    Off,
    /// FPS counter only
    Fps,
    /// devinfo + fps + frametimes
    Partial,
    /// All DXVK stats
    Full,
}

// ---------------------------------------------------------------------------
// LaunchOptions
// ---------------------------------------------------------------------------

pub struct LaunchOptions {
    pub wine64_path: String,
    pub exe_path: String,
    pub working_dir: Option<String>,
    pub wine_prefix: String,
    pub gptk_lib_path: String,
    pub extra_args: Vec<String>,
    pub graphics_backend: GraphicsBackend,
    pub env: HashMap<String, String>,
    /// Enable WINEESYNC (eventfd threading).
    pub esync: bool,
    /// Enable WINEMSYNC (mach-port sync, macOS-specific).
    /// NOTE: also forces WINEESYNC=1 to satisfy D3DMetal — see module docs.
    pub msync: bool,
    /// MTL_HUD_ENABLED
    pub show_hud: bool,
    /// METAL_CAPTURE_ENABLED — Metal GPU frame capture for profiling
    pub metal_trace: bool,
    /// ROSETTA_ADVERTISE_AVX
    pub advertise_avx: bool,
    /// D3DM_SUPPORT_DXR (M3+ only)
    pub enable_dxr: bool,
    /// D3DM_ENABLE_METALFX (GPTK 3.0+)
    pub metalfx_enabled: bool,
    /// DXVK HUD level (only used for DXVK backends)
    pub dxvk_hud: DxvkHud,
    /// MANGOHUD=1 — shows FPS, CPU, GPU, RAM, frametimes when using DXVK+MoltenVK
    pub mangohud_enabled: bool,
    /// WINEDEBUG value — "fixme-all" suppresses noise, "" is verbose
    pub wine_debug: String,
}

impl LaunchOptions {
    pub fn from_steam_game(steam_game: &SteamGame, prefix_path: &str, cfg: &AppConfig) -> Self {
        let wine_debug = if cfg.suppress_wine_debug {
            "fixme-all".to_string()
        } else {
            String::new()
        };

        LaunchOptions {
            wine64_path: cfg.wine64_path.clone(),
            exe_path: steam_game.exe_path.clone(),
            working_dir: Some(steam_game.install_dir.clone()),
            wine_prefix: prefix_path.to_string(),
            gptk_lib_path: cfg.gptk_lib_path.clone(),
            extra_args: vec!["-steam".to_string()],
            graphics_backend: GraphicsBackend::D3DMetal,
            env: cfg.env.clone(),
            esync: true,
            msync: false,
            show_hud: cfg.global_hud,
            metal_trace: false,
            advertise_avx: false,
            enable_dxr: false,
            metalfx_enabled: cfg.metalfx_enabled,
            dxvk_hud: DxvkHud::Off,
            mangohud_enabled: false,
            wine_debug,
        }
    }
}

// ---------------------------------------------------------------------------
// GameProcess
// ---------------------------------------------------------------------------

pub struct GameProcess {
    child: Child,
    pub started_at: u64,
}

impl GameProcess {
    pub fn is_running(&mut self) -> bool {
        matches!(self.child.try_wait(), Ok(None))
    }

    pub fn kill(&mut self) -> std::io::Result<()> {
        self.child.kill()
    }

    pub fn pid(&self) -> u32 {
        self.child.id()
    }

    pub fn elapsed_secs(&self) -> u64 {
        let now = std::time::SystemTime::now()
            .duration_since(std::time::UNIX_EPOCH)
            .unwrap_or_default()
            .as_secs();
        now.saturating_sub(self.started_at)
    }
}

// ---------------------------------------------------------------------------
// spawn
// ---------------------------------------------------------------------------

/// Spawn a game through Wine.
///
/// Effective command (matching Whisky's approach):
/// ```sh
/// <wine64> start /unix <exe_path> [extra_args...]
/// ```
///
/// NO `arch -x86_64` wrapper — Rosetta 2 activates automatically because
/// wine64 is an x86_64 binary. The wrapper is redundant and causes issues.
pub fn spawn(opts: LaunchOptions) -> Result<GameProcess, String> {
    // DYLD_LIBRARY_PATH is only for D3DMetal/GPTK. DXVK/VKD3D should use
    // Forge/Homebrew MoltenVK so GPTK's older libMoltenVK cannot shadow it.
    let existing_dyld = std::env::var("DYLD_LIBRARY_PATH").unwrap_or_default();
    let dyld_path = build_dyld_path(&opts.gptk_lib_path, &existing_dyld);

    // Expand ~ in all paths
    let wine_prefix = expand_tilde(&opts.wine_prefix);
    let exe_path = expand_tilde(&opts.exe_path);
    let is_steam = std::path::Path::new(&exe_path)
        .file_name()
        .and_then(|name| name.to_str())
        .map(|name| name.eq_ignore_ascii_case("steam.exe"))
        .unwrap_or(false);
    let game_backend = opts.graphics_backend.clone();
    let launch_backend = if is_steam {
        GraphicsBackend::WineBuiltin
    } else {
        game_backend.clone()
    };

    // Auto-create the Wine prefix if it doesn't exist yet.
    // Wine's chdir error fires before the game even starts if the prefix dir
    // is missing. We create it here with wineboot --init so the first launch
    // always works without the user needing a separate setup step.
    if !std::path::Path::new(&wine_prefix).exists() {
        eprintln!(
            "[forge] Wine prefix '{}' not found — running wineboot --init",
            wine_prefix
        );

        // Ensure parent directories exist (e.g. ~/Wine/Bottles/)
        if let Some(parent) = std::path::Path::new(&wine_prefix).parent() {
            std::fs::create_dir_all(parent).map_err(|e| {
                format!(
                    "Cannot create prefix parent dir '{}': {}",
                    parent.display(),
                    e
                )
            })?;
        }

        let boot = Command::new(&opts.wine64_path)
            .args(["wineboot", "--init"])
            .env("WINEPREFIX", &wine_prefix)
            .env("WINEDEBUG", "fixme-all")
            .env("GST_DEBUG", "1")
            // Avoid first-run Mono/Gecko prompts blocking unattended bottle setup.
            .env("WINEDLLOVERRIDES", "mscoree,mshtml=")
            .status();

        match boot {
            Ok(s) if s.success() => {
                eprintln!("[forge] Wine prefix created at '{}'", wine_prefix);
            }
            Ok(s) => {
                return Err(format!(
                    "Failed to create Wine prefix at '{}'.\n\
                     wineboot exited with code {}.",
                    wine_prefix,
                    s.code().unwrap_or(-1)
                ));
            }
            Err(e) => {
                return Err(format!(
                    "Failed to run wineboot to create prefix at '{}':\n{}",
                    wine_prefix, e
                ));
            }
        }
    }

    // Working directory: explicit or parent of the exe
    let work_dir = resolve_work_dir(&opts.working_dir, &exe_path);

    // Build: wine64 start /unix <exe> [extra_args]
    let mut cmd = Command::new(&opts.wine64_path);
    cmd.arg("start")
        .arg("/unix")
        .arg(&exe_path)
        .args(&opts.extra_args)
        .current_dir(&work_dir)
        // Required Wine env
        .env("WINEPREFIX", &wine_prefix)
        // Whisky uses "fixme-all" not "-all" — keeps real errors visible
        .env("WINEDEBUG", &opts.wine_debug)
        // GStreamer verbosity (matches Whisky)
        .env("GST_DEBUG", "1")
        // Metal HUD
        .env("MTL_HUD_ENABLED", if opts.show_hud { "1" } else { "0" })
        // Mouse warp — helps cursor capture in games on macOS
        .env("WINE_MOUSE_WARP", "1");

    if launch_backend == GraphicsBackend::D3DMetal {
        cmd.env("DYLD_LIBRARY_PATH", &dyld_path);
    } else {
        cmd.env_remove("DYLD_LIBRARY_PATH");
    }

    // ── Sync mode ─────────────────────────────────────────────────────────
    // MSYNC trick from Whisky: D3DMetal checks for WINEESYNC internally,
    // so when using MSYNC we must lie and set WINEESYNC=1 too.
    if opts.msync {
        cmd.env("WINEMSYNC", "1");
        cmd.env("WINEESYNC", "1"); // D3DMetal lie — required even under MSYNC
    } else if opts.esync {
        cmd.env("WINEESYNC", "1");
    }

    // ── Graphics backend DLL overrides ───────────────────────────────────
    match &launch_backend {
        GraphicsBackend::D3DMetal => {
            // Prefer GPTK/D3DMetal's D3D/DXGI modules when a GPTK Wine lib
            // directory is configured. This keeps launcher-launched games on
            // the high-performance Metal path instead of WineD3D/DXVK.
            if let Some(gptk_base) = gptk_wine_lib_base(&opts.gptk_lib_path) {
                let gptk_dlls = gptk_base.join("wine/x86_64-windows");
                if gptk_dlls.is_dir() {
                    let existing = std::env::var("WINEDLLPATH").unwrap_or_default();
                    let mut dll_path = gptk_dlls.to_string_lossy().to_string();
                    if !existing.is_empty() {
                        dll_path.push(':');
                        dll_path.push_str(&existing);
                    }
                    cmd.env("WINEDLLPATH", dll_path);
                }
            }
            cmd.env(
                "WINEDLLOVERRIDES",
                "dxgi,d3d9,d3d10core,d3d11,d3d12=n,b;user32=n,b",
            );
        }
        GraphicsBackend::Dxvk => {
            cmd.env("WINEDLLOVERRIDES", "dxgi,d3d9,d3d10core,d3d11,user32=n,b");
            cmd.env("DXVK_ASYNC", "1");
        }
        GraphicsBackend::Vkd3d => {
            cmd.env("WINEDLLOVERRIDES", "d3d12,dxgi,user32=n,b");
        }
        GraphicsBackend::DxvkVkd3d => {
            cmd.env(
                "WINEDLLOVERRIDES",
                "dxgi,d3d9,d3d10core,d3d11,d3d12,user32=n,b",
            );
            cmd.env("DXVK_ASYNC", "1");
        }
        GraphicsBackend::WineBuiltin => {
            // Force Wine builtin D3D/DXGI for explicit compatibility mode only.
            // Do not use this for Steam when games will inherit the environment.
            cmd.env("WINEDLLOVERRIDES", "*dxgi,*d3d8,*d3d9,*d3d10core,*d3d11,*d3d12,*d3d12core=b;user32=n,b;mscoree,mshtml=");
            // Wine 11 wined3d defaults to Vulkan on macOS. OpenGL is safer for
            // legacy launcher UI compatibility mode, but slower for games.
            cmd.env("WINE_D3D_CONFIG", "renderer=gl");
            cmd.env("LIBGL_ALWAYS_SOFTWARE", "1");
        }
        GraphicsBackend::None => {}
    }

    if launch_backend == GraphicsBackend::Dxvk || launch_backend == GraphicsBackend::DxvkVkd3d {
        match opts.dxvk_hud {
            DxvkHud::Full => {
                cmd.env("DXVK_HUD", "full");
            }
            DxvkHud::Partial => {
                cmd.env("DXVK_HUD", "devinfo,fps,frametimes");
            }
            DxvkHud::Fps => {
                cmd.env("DXVK_HUD", "fps");
            }
            DxvkHud::Off => {}
        }
    }

    // ── D3DMetal / GPTK extras ────────────────────────────────────────────

    if opts.enable_dxr {
        cmd.env("D3DM_SUPPORT_DXR", "1");
    }
    if opts.metalfx_enabled {
        cmd.env("D3DM_ENABLE_METALFX", "1");
    }

    // ── MangoHud (comprehensive overlay: FPS, CPU, GPU, RAM, VRAM) ───────
    // Only works with DXVK + MoltenVK (Vulkan pipeline). Requires:
    //   brew install mangohud
    // For D3DMetal (Metal pipeline), the in-game Metal HUD via
    // MTL_HUD_ENABLED=1 is used instead.
    if opts.mangohud_enabled {
        cmd.env("MANGOHUD", "1");
        cmd.env(
            "MANGOHUD_CONFIG",
            "fps,frametime,cpu_load,gpu_load,ram,vram,font_size=20,position=top-left",
        );
    }

    // ── Rosetta / CPU ─────────────────────────────────────────────────────
    if opts.advertise_avx {
        cmd.env("ROSETTA_ADVERTISE_AVX", "1");
    }

    // ── Metal GPU trace (for profiling) ───────────────────────────────────
    if opts.metal_trace {
        cmd.env("METAL_CAPTURE_ENABLED", "1");
    }

    // Apply resolved env late: global -> profile -> bottle -> app/game.
    for (key, value) in &opts.env {
        cmd.env(key, value);
    }

    if is_steam {
        let game_dll_overrides = match game_backend {
            GraphicsBackend::D3DMetal => "dxgi,d3d9,d3d10core,d3d11,d3d12=n,b;user32=n,b",
            GraphicsBackend::Dxvk => "dxgi,d3d9,d3d10core,d3d11,user32=n,b",
            GraphicsBackend::Vkd3d => "d3d12,dxgi,user32=n,b",
            GraphicsBackend::DxvkVkd3d => "dxgi,d3d9,d3d10core,d3d11,d3d12,user32=n,b",
            GraphicsBackend::WineBuiltin => {
                "*dxgi,*d3d8,*d3d9,*d3d10core,*d3d11,*d3d12,*d3d12core=b;user32=n,b;mscoree,mshtml="
            }
            GraphicsBackend::None => "",
        };
        let game_vk_icd = opts
            .env
            .get("VK_ICD_FILENAMES")
            .map(|value| value.as_str())
            .unwrap_or("");

        // Steam's Chromium UI needs safe WineD3D/OpenGL mode, but games
        // launched from Steam must keep acceleration. Forge Wine sees this
        // marker and restores FORGE_GAME_* for non-Steam child processes.
        cmd.env("FORGE_STEAM_SAFE_MODE", "1")
            .env("FORGE_GAME_WINEDLLOVERRIDES", game_dll_overrides)
            .env("FORGE_GAME_VK_ICD_FILENAMES", game_vk_icd)
            .env("FORGE_GAME_MTL_HUD_ENABLED", if opts.show_hud { "1" } else { "0" })
            .env("MOLTENVK_CONFIG_LOG_LEVEL", "0")
            .env("WINEDLLOVERRIDES", "*dxgi,*d3d8,*d3d9,*d3d10core,*d3d11,*d3d12,*d3d12core=b;user32=n,b;mscoree,mshtml=")
            .env("WINE_D3D_CONFIG", "renderer=gl")
            .env("LIBGL_ALWAYS_SOFTWARE", "1")
            .env("VK_ICD_FILENAMES", "/dev/null")
            .env("VK_DRIVER_FILES", "/dev/null")
            .env("DXVK_FILTER_DEVICE_NAME", "__forge_disable_dxvk_for_steam__")
            .env("MTL_HUD_ENABLED", "0");
    }

    // Check wine64 exists before spawning to give a clear actionable error
    if !std::path::Path::new(&opts.wine64_path).exists() {
        return Err(format!(
            "wine64 not found at '{}'.\n\n\
             Wine is not installed. Run this in Terminal to install:\n\
             brew install --cask gcenx/wine/game-porting-toolkit\n\n\
             Then restart Forge Launcher — it will detect Wine automatically.",
            opts.wine64_path
        ));
    }

    let child = cmd
        .spawn()
        .map_err(|e| format!("Failed to spawn Wine: {}", e))?;

    let started_at = std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .unwrap_or_default()
        .as_secs();

    Ok(GameProcess { child, started_at })
}

// ---------------------------------------------------------------------------
// init_wine_prefix
// ---------------------------------------------------------------------------

/// Initialise a new Wine bottle.
///
/// Runs: `<wine64> wineboot --init`
/// No `arch -x86_64` needed — Rosetta handles x86_64 binaries automatically.
pub fn init_wine_prefix(prefix_path: &str, wine64_path: &str) -> Result<(), String> {
    let prefix_path = expand_tilde(prefix_path);

    // Create parent directory tree if it doesn't exist
    // (e.g. ~/Wine/Bottles/ may not exist on a fresh system)
    if let Some(parent) = std::path::Path::new(&prefix_path).parent() {
        std::fs::create_dir_all(parent).map_err(|e| {
            format!(
                "Cannot create prefix parent dir '{}': {}",
                parent.display(),
                e
            )
        })?;
    }

    let status = Command::new(wine64_path)
        .args(["wineboot", "--init"])
        .env("WINEPREFIX", &prefix_path)
        .env("WINEDEBUG", "fixme-all")
        .env("GST_DEBUG", "1")
        // Avoid first-run Mono/Gecko prompts blocking unattended bottle setup.
        .env("WINEDLLOVERRIDES", "mscoree,mshtml=")
        .status()
        .map_err(|e| format!("Failed to run wineboot: {}", e))?;

    if status.success() {
        Ok(())
    } else {
        Err(format!(
            "wineboot exited with code {}. Is wine64_path correct?",
            status.code().unwrap_or(-1)
        ))
    }
}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

pub fn merge_env(
    global: &HashMap<String, String>,
    profile: &HashMap<String, String>,
    bottle: &HashMap<String, String>,
    app: &HashMap<String, String>,
) -> HashMap<String, String> {
    let mut merged = HashMap::new();
    for source in [global, profile, bottle, app] {
        for (key, value) in source {
            merged.insert(key.clone(), value.clone());
        }
    }
    merged
}

fn build_dyld_path(gptk_lib: &str, existing: &str) -> String {
    let mut parts = Vec::new();
    if let Some(gptk_lib) = trimmed_non_empty_path(gptk_lib) {
        let configured = PathBuf::from(gptk_lib);
        parts.push(configured.to_string_lossy().to_string());

        // Accept either GPTK's base Wine lib directory:
        //   .../Resources/wine/lib
        // or the external directory directly:
        //   .../Resources/wine/lib/external
        if configured
            .file_name()
            .and_then(|name| name.to_str())
            .map(|name| name.eq_ignore_ascii_case("external"))
            .unwrap_or(false)
        {
            if let Some(parent) = configured.parent() {
                parts.push(parent.to_string_lossy().to_string());
            }
        } else {
            parts.push(configured.join("external").to_string_lossy().to_string());
        }
    }
    if !existing.is_empty() {
        parts.push(existing.to_string());
    }
    dedupe_path_parts(parts).join(":")
}

fn gptk_wine_lib_base(gptk_lib: &str) -> Option<PathBuf> {
    let gptk_lib = trimmed_non_empty_path(gptk_lib)?;
    let configured = PathBuf::from(gptk_lib);
    if configured
        .file_name()
        .and_then(|name| name.to_str())
        .map(|name| name.eq_ignore_ascii_case("external"))
        .unwrap_or(false)
    {
        configured.parent().map(|path| path.to_path_buf())
    } else {
        Some(configured)
    }
}

fn trimmed_non_empty_path(path: &str) -> Option<&str> {
    let trimmed = path.trim();
    if trimmed.is_empty() {
        None
    } else {
        Some(trimmed)
    }
}

fn dedupe_path_parts(parts: Vec<String>) -> Vec<String> {
    let mut out = Vec::new();
    for part in parts {
        if !part.is_empty() && !out.iter().any(|existing| existing == &part) {
            out.push(part);
        }
    }
    out
}

fn resolve_work_dir(working_dir: &Option<String>, expanded_exe_path: &str) -> PathBuf {
    let candidate = match working_dir {
        Some(wd) => PathBuf::from(expand_tilde(wd)),
        None => PathBuf::from(expanded_exe_path)
            .parent()
            .unwrap_or_else(|| std::path::Path::new("/tmp"))
            .to_path_buf(),
    };
    // If the resolved directory doesn't exist, fall back to exe parent
    // rather than letting Wine crash with a silent chdir error
    if candidate.is_dir() {
        candidate
    } else {
        PathBuf::from(expanded_exe_path)
            .parent()
            .unwrap_or_else(|| std::path::Path::new("/tmp"))
            .to_path_buf()
    }
}

pub fn expand_tilde(path: &str) -> String {
    let home = match std::env::var("HOME") {
        Ok(h) => h,
        Err(_) => return path.to_string(),
    };
    if path == "~" {
        return home;
    }
    if let Some(rest) = path.strip_prefix("~/") {
        return format!("{}/{}", home, rest);
    }
    path.to_string()
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn build_dyld_path_trims_configured_gptk_path() {
        let dyld_path = build_dyld_path(
            "  /Applications/GPTK/wine/lib/external  \n",
            "/opt/forge/lib",
        );

        assert_eq!(
            dyld_path,
            "/Applications/GPTK/wine/lib/external:/Applications/GPTK/wine/lib:/opt/forge/lib"
        );
    }

    #[test]
    fn gptk_wine_lib_base_trims_external_path() {
        let base = gptk_wine_lib_base("  /Applications/GPTK/wine/lib/external  ")
            .expect("trimmed GPTK path should resolve");

        assert_eq!(base, PathBuf::from("/Applications/GPTK/wine/lib"));
    }

    #[test]
    fn trimmed_non_empty_path_rejects_blank_values() {
        assert_eq!(trimmed_non_empty_path(" \n\t "), None);
        assert_eq!(
            trimmed_non_empty_path(" /opt/runtime/lib "),
            Some("/opt/runtime/lib")
        );
    }
}
