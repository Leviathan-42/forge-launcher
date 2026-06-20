// Prevents an additional console window on Windows release builds.
// Harmless on macOS but kept for cross-platform hygiene.
#![cfg_attr(not(debug_assertions), windows_subsystem = "windows")]

mod bottles;
mod config;
mod downloader;
mod launcher;
mod saves;
mod steam;

use std::collections::HashMap;
use std::sync::{Arc, Mutex};
use tauri::{AppHandle, State};

use config::{AppConfig, Game};
use downloader::{DownloadBackend, DownloadRequest, ToolStatus};
use launcher::LaunchOptions;
use steam::SteamGame;

const FIREFOX_STEAM_COOKIE_MISSING: &str =
    "No Steam session cookie found in Firefox. Make sure you're logged into Steam in Firefox first.";
const STEAM_LOGIN_SECURE_QUERY: &str =
    "SELECT value FROM moz_cookies WHERE host='store.steampowered.com' AND name='steamLoginSecure' LIMIT 1;";

// ---------------------------------------------------------------------------
// Global app state
// ---------------------------------------------------------------------------

/// Every game child process we have spawned, keyed by game UUID.
pub struct RunningGames(pub Arc<Mutex<HashMap<String, launcher::GameProcess>>>);

/// Active download handles keyed by AppID string, used for cancellation.
pub struct ActiveDownloads(pub Arc<Mutex<HashMap<String, Arc<std::sync::atomic::AtomicBool>>>>);

// ---------------------------------------------------------------------------
// Bottle-first commands
// ---------------------------------------------------------------------------

#[tauri::command]
async fn list_bottles(app: AppHandle) -> Result<Vec<bottles::Bottle>, String> {
    bottles::list_bottles(&app)
}

#[tauri::command]
async fn create_bottle(
    app: AppHandle,
    name: String,
    prefix_path: Option<String>,
) -> Result<Vec<bottles::Bottle>, String> {
    bottles::create_bottle(&app, name, prefix_path)
}

#[tauri::command]
async fn list_runtime_profiles(app: AppHandle) -> Result<Vec<config::RuntimeProfile>, String> {
    config::load_runtime_profiles(&app)
}

#[tauri::command]
async fn save_runtime_profiles(
    app: AppHandle,
    profiles: Vec<config::RuntimeProfile>,
) -> Result<(), String> {
    config::save_runtime_profiles(&app, &profiles)
}

#[tauri::command]
async fn update_bottle_runtime(
    app: AppHandle,
    prefix_path: String,
    runtime_profile_id: String,
    graphics_backend: Option<config::GraphicsBackend>,
    env_overrides: Option<std::collections::HashMap<String, String>>,
    force: bool,
) -> Result<Vec<bottles::Bottle>, String> {
    bottles::update_bottle_runtime(
        &app,
        prefix_path,
        runtime_profile_id,
        graphics_backend,
        env_overrides,
        force,
    )
}

#[tauri::command]
async fn create_peak_test_bottle(app: AppHandle) -> Result<Vec<bottles::Bottle>, String> {
    bottles::create_peak_test_bottle(&app)
}

#[tauri::command]
async fn bottle_launcher_status(prefix_path: String) -> Result<bottles::LauncherStatus, String> {
    Ok(bottles::launcher_status(&prefix_path))
}

#[tauri::command]
async fn list_bottle_apps(prefix_path: String) -> Result<Vec<bottles::BottleApp>, String> {
    Ok(bottles::list_apps(&prefix_path))
}

#[tauri::command]
async fn install_steam_in_prefix(app: AppHandle, prefix_path: String) -> Result<(), String> {
    bottles::install_steam(&app, prefix_path)
}

#[tauri::command]
async fn open_steam_in_prefix(app: AppHandle, prefix_path: String) -> Result<(), String> {
    bottles::open_steam(&app, prefix_path)
}

#[tauri::command]
async fn repair_steam_in_prefix(app: AppHandle, prefix_path: String) -> Result<(), String> {
    bottles::repair_steam(&app, prefix_path)
}

#[tauri::command]
async fn run_exe_in_prefix(
    app: AppHandle,
    prefix_path: String,
    exe_path: String,
    args: Vec<String>,
) -> Result<(), String> {
    bottles::run_exe(&app, prefix_path, exe_path, args)
}

// ---------------------------------------------------------------------------
// Game library commands
// ---------------------------------------------------------------------------

#[tauri::command]
async fn load_games(app: AppHandle) -> Result<Vec<Game>, String> {
    config::load_games(&app)
}

#[tauri::command]
async fn save_games(app: AppHandle, games: Vec<Game>) -> Result<(), String> {
    config::save_games(&app, &games)
}

#[tauri::command]
async fn upsert_game(app: AppHandle, mut game: Game) -> Result<Vec<Game>, String> {
    // Auto-fetch Steam cover art if this is a Steam game with no art yet
    if game.cover_art.is_none() {
        if let Some(app_id) = game.steam_app_id {
            if let Ok(art_path) = fetch_steam_cover(&app, app_id).await {
                game.cover_art = Some(art_path);
            }
        }
    }

    let mut games = config::load_games(&app)?;
    match games.iter().position(|g| g.id == game.id) {
        Some(pos) => games[pos] = game,
        None => games.push(game),
    }
    config::save_games(&app, &games)?;
    Ok(games)
}

/// Download Steam cover art (600x900 portrait) to app data dir.
/// URL: https://cdn.akamai.steamstatic.com/steam/apps/{id}/library_600x900.jpg
/// Returns the local file path on success, silently fails if offline.
async fn fetch_steam_cover(app: &AppHandle, app_id: u64) -> Result<String, ()> {
    use tauri::Manager;

    let url = format!(
        "https://cdn.akamai.steamstatic.com/steam/apps/{}/library_600x900.jpg",
        app_id
    );

    // Download bytes using reqwest (available via tauri's bundled http client)
    let bytes = tauri::async_runtime::spawn_blocking(move || {
        // Use std blocking http — avoids adding reqwest as a dep
        let output = std::process::Command::new("curl")
            .args(["-sL", "--max-time", "10", "--output", "-", &url])
            .output();
        match output {
            Ok(o) if o.status.success() && !o.stdout.is_empty() => Ok(o.stdout),
            _ => Err(()),
        }
    })
    .await
    .map_err(|_| ())?
    .map_err(|_| ())?;

    // Save to <app_data>/covers/<app_id>.jpg
    let covers_dir = app.path().app_data_dir().map_err(|_| ())?.join("covers");

    std::fs::create_dir_all(&covers_dir).map_err(|_| ())?;

    let path = covers_dir.join(format!("{}.jpg", app_id));
    std::fs::write(&path, &bytes).map_err(|_| ())?;

    Ok(path.to_string_lossy().to_string())
}

#[tauri::command]
async fn remove_game(app: AppHandle, id: String) -> Result<Vec<Game>, String> {
    let mut games = config::load_games(&app)?;
    games.retain(|g| g.id != id);
    config::save_games(&app, &games)?;
    Ok(games)
}

// ---------------------------------------------------------------------------
// Launcher commands
// ---------------------------------------------------------------------------

/// Launch a Windows .exe through GPTK / Wine / Rosetta 2.
///
/// Effective shell equivalent:
///   arch -x86_64 /usr/local/bin/wine64 /path/to/game.exe [extra_args...]
///
/// Environment injected: WINEPREFIX, DYLD_LIBRARY_PATH, WINEESYNC,
/// WINEDEBUG, MTL_HUD_ENABLED, WINEDLLOVERRIDES, D3DM_SUPPORT_DXR,
/// ROSETTA_ADVERTISE_AVX, D3DM_ENABLE_METALFX.
///
/// Before launching, save files are synced from macOS → Wine prefix
/// so the game picks up your latest cloud / backup saves.
#[tauri::command]
async fn launch_game(
    app: AppHandle,
    state: State<'_, RunningGames>,
    game_id: String,
) -> Result<(), String> {
    let games = config::load_games(&app)?;
    let game = games
        .iter()
        .find(|g| g.id == game_id)
        .ok_or_else(|| format!("Game '{}' not found in library", game_id))?
        .clone();

    // Sync saves from macOS into the Wine prefix before launching
    if !game.save_mappings.is_empty() {
        eprintln!("[forge] Syncing saves before launch for '{}'...", game.name);
        let _ = saves::sync_saves(saves::SyncDirection::ToPrefix, &game.save_mappings);
    }

    let cfg = config::load_config(&app)?;
    let prefix = game
        .wine_prefix
        .clone()
        .unwrap_or_else(|| cfg.default_prefix.clone());
    let mut opts = bottles::resolve_launch_options(
        &app,
        &prefix,
        &game.exe_path,
        game.extra_args.clone(),
        &game.env_overrides,
    )?;
    opts.esync = game.esync;
    opts.msync = game.msync;
    opts.show_hud = game.show_hud || cfg.global_hud;
    opts.advertise_avx = game.advertise_avx;
    opts.enable_dxr = game.enable_dxr;
    opts.metalfx_enabled = cfg.metalfx_enabled;
    opts.mangohud_enabled = game.mangohud_enabled;
    let process = launcher::spawn(opts)?;

    state
        .0
        .lock()
        .map_err(|e| e.to_string())?
        .insert(game_id, process);

    Ok(())
}

#[tauri::command]
async fn kill_game(state: State<'_, RunningGames>, game_id: String) -> Result<(), String> {
    let mut map = state.0.lock().map_err(|e| e.to_string())?;
    if let Some(mut proc) = map.remove(&game_id) {
        proc.kill().map_err(|e| e.to_string())?;
    }
    Ok(())
}

#[tauri::command]
async fn running_games(
    app: AppHandle,
    state: State<'_, RunningGames>,
) -> Result<Vec<String>, String> {
    let mut map = state.0.lock().map_err(|e| e.to_string())?;

    // Collect IDs of processes that have just exited so we can update playtime
    let mut exited: Vec<(String, u64)> = Vec::new();
    map.retain(|id, proc| {
        if proc.is_running() {
            true
        } else {
            exited.push((id.clone(), proc.elapsed_secs()));
            false
        }
    });

    // Persist playtime + sync saves back for each game that just stopped
    if !exited.is_empty() {
        if let Ok(mut games) = config::load_games(&app) {
            for (id, secs) in &exited {
                if let Some(g) = games.iter_mut().find(|g| &g.id == id) {
                    g.playtime_secs += secs;

                    // Sync saves back from Wine prefix → macOS after the game exits
                    if !g.save_mappings.is_empty() {
                        eprintln!("[forge] Saving progress for '{}'...", g.name);
                        let _ =
                            saves::sync_saves(saves::SyncDirection::FromPrefix, &g.save_mappings);
                    }
                }
            }
            let _ = config::save_games(&app, &games);
        }
    }

    Ok(map.keys().cloned().collect())
}

// ---------------------------------------------------------------------------
// Wine prefix commands
// ---------------------------------------------------------------------------

#[tauri::command]
async fn create_prefix(app: AppHandle, prefix_path: String) -> Result<(), String> {
    let cfg = config::load_config(&app)?;
    launcher::init_wine_prefix(&prefix_path, &cfg.wine64_path)
}

// ---------------------------------------------------------------------------
// App configuration commands
// ---------------------------------------------------------------------------

#[tauri::command]
async fn load_config(app: AppHandle) -> Result<AppConfig, String> {
    config::load_config(&app)
}

#[tauri::command]
async fn save_config(app: AppHandle, cfg: AppConfig) -> Result<(), String> {
    config::save_config(&app, &cfg)
}

// ---------------------------------------------------------------------------
// Steam library scanning
// ---------------------------------------------------------------------------

/// Scan ~/Library/.../Steam/steamapps/ for Windows-only ACF manifests.
#[tauri::command]
async fn scan_steam_games() -> Result<Vec<SteamGame>, String> {
    steam::scan_steam_library()
}

/// Launch via steam://rungameid/<id> — delegates everything to Steam client.
#[tauri::command]
async fn launch_steam_game(app_id: u64) -> Result<(), String> {
    steam::launch_via_steam_protocol(app_id)
}

/// Launch directly through GPTK/Wine, bypassing the Steam client.
#[tauri::command]
async fn launch_steam_game_direct(
    app: AppHandle,
    state: State<'_, RunningGames>,
    app_id: u64,
    prefix_path: String,
) -> Result<(), String> {
    let cfg = config::load_config(&app)?;

    let steam_game = steam::scan_steam_library()?
        .into_iter()
        .find(|g| g.app_id == app_id)
        .ok_or_else(|| format!("Steam AppID {} not found in local library", app_id))?;

    let opts = LaunchOptions::from_steam_game(&steam_game, &prefix_path, &cfg);
    let process = launcher::spawn(opts)?;

    state
        .0
        .lock()
        .map_err(|e| e.to_string())?
        .insert(app_id.to_string(), process);

    Ok(())
}

// ---------------------------------------------------------------------------
// Wine / GPTK detection
// ---------------------------------------------------------------------------

/// Check whether wine64 is installed and return its path + installation advice.
#[tauri::command]
async fn check_wine() -> serde_json::Value {
    match config::detect_wine64() {
        Some(path) => serde_json::json!({
            "installed": true,
            "path": path,
            "gptk_lib": config::detect_gptk_lib_path(),
            "message": null
        }),
        None => serde_json::json!({
            "installed": false,
            "path": null,
            "gptk_lib": null,
            "message": "Wine is not installed. Run in Terminal:\nbrew install --cask gcenx/wine/game-porting-toolkit"
        }),
    }
}

// ---------------------------------------------------------------------------
// Download commands
// ---------------------------------------------------------------------------

/// Check whether DepotDownloader and SteamCMD are installed and return
/// their paths. Also checks if credentials are already cached for `username`.
#[tauri::command]
async fn check_download_tools() -> ToolStatus {
    downloader::check_tools()
}

/// Returns true if DepotDownloader has a cached auth token for this username.
/// When true, downloads can run silently — no Terminal window needed.
#[tauri::command]
async fn check_steam_credentials(username: String) -> bool {
    downloader::has_cached_credentials(&username)
}

/// Read the Steam username stored inside DepotDownloader's account.config.
/// Returns the username string if credentials are cached, or null if not.
/// Use this to auto-fill the username field after the user has logged in.
#[tauri::command]
async fn get_cached_steam_username() -> Option<String> {
    downloader::get_cached_username()
}

/// Open macOS Terminal.app for first-time Steam authentication.
///
/// Runs DepotDownloader with -remember-password against a tiny free app so
/// the user can type their password + Steam Guard code. On success the token
/// is saved to ~/.config/DepotDownloader/<username>.json and all future
/// downloads work silently without a terminal window.
#[tauri::command]
async fn authenticate_steam(username: String) -> Result<(), String> {
    downloader::open_terminal_for_auth(&username)
}

/// Download a Windows Steam game using DepotDownloader or SteamCMD.
///
/// This command returns immediately. Progress is streamed to the frontend
/// via the `"download://progress"` Tauri event.  Listen with:
///
/// ```ts
/// import { listen } from "@tauri-apps/api/event";
/// const unlisten = await listen("download://progress", (event) => {
///   const p = event.payload as DownloadProgress;
///   updateDownloadProgress(p.percent, p.status, p.completed);
/// });
/// ```
///
/// The download runs in a background thread so the UI stays responsive.
/// Call `cancel_download(app_id)` to abort it mid-flight.
#[tauri::command]
async fn download_steam_game(
    app: AppHandle,
    downloads: State<'_, ActiveDownloads>,
    request: DownloadRequest,
) -> Result<(), String> {
    use std::sync::atomic::AtomicBool;
    use tauri::async_runtime::spawn_blocking;

    let app_id_str = request.app_id.to_string();

    // Create a cancellation flag and register it
    let cancel_flag = Arc::new(AtomicBool::new(false));
    downloads
        .0
        .lock()
        .map_err(|e| e.to_string())?
        .insert(app_id_str, cancel_flag.clone());

    let app_clone = app.clone();

    // Spawn in a blocking thread — the download loop is synchronous I/O
    spawn_blocking(move || downloader::download_game(app_clone, request, cancel_flag));

    Ok(())
}

/// Cancel an in-progress download by Steam AppID.
#[tauri::command]
async fn cancel_download(downloads: State<'_, ActiveDownloads>, app_id: u64) -> Result<(), String> {
    use std::sync::atomic::Ordering;

    let mut map = downloads.0.lock().map_err(|e| e.to_string())?;
    if let Some(flag) = map.remove(&app_id.to_string()) {
        flag.store(true, Ordering::SeqCst);
    }
    Ok(())
}

/// Validate (re-verify) an already-downloaded game's files.
/// Uses the same DepotDownloader / SteamCMD backend with `-validate`.
#[tauri::command]
async fn validate_game_files(
    app: AppHandle,
    downloads: State<'_, ActiveDownloads>,
    app_id: u64,
    username: String,
    install_dir: String,
    backend: DownloadBackend,
) -> Result<(), String> {
    let request = DownloadRequest {
        app_id,
        username,
        install_dir,
        validate_only: true,
        backend,
    };
    download_steam_game(app, downloads, request).await
}

// ---------------------------------------------------------------------------
// Save sync commands
// ---------------------------------------------------------------------------

/// Manually sync game saves in one direction.
/// `direction` must be "to_prefix" (macOS → Wine) or "from_prefix" (Wine → macOS).
/// Returns the number of files copied.
#[tauri::command]
async fn sync_game_saves(
    app: AppHandle,
    game_id: String,
    direction: String,
) -> Result<u64, String> {
    let games = config::load_games(&app)?;
    let game = games
        .iter()
        .find(|g| g.id == game_id)
        .ok_or_else(|| format!("Game '{}' not found in library", game_id))?;

    let dir = match direction.as_str() {
        "to_prefix" => saves::SyncDirection::ToPrefix,
        "from_prefix" => saves::SyncDirection::FromPrefix,
        other => {
            return Err(format!(
                "Invalid direction '{}'. Use 'to_prefix' or 'from_prefix'.",
                other
            ))
        }
    };

    saves::sync_saves(dir, &game.save_mappings)
}

/// Guess the Wine username inside a prefix directory.
/// Useful for building save path suggestions in the UI.
#[tauri::command]
async fn guess_wine_username(prefix_path: String) -> Result<String, String> {
    Ok(saves::guess_wine_username(&prefix_path))
}

// ---------------------------------------------------------------------------
// Performance monitoring
// ---------------------------------------------------------------------------

/// Live performance stats for a running game process.
#[derive(serde::Serialize, serde::Deserialize, Debug, Clone)]
pub struct ProcessStats {
    /// Process ID.
    pub pid: u32,
    /// Resident Set Size in MB (physical RAM currently used).
    pub rss_mb: f64,
    /// Virtual memory size in MB (address space allocated).
    pub vsz_mb: f64,
    /// CPU usage as a percentage (100 = one full core).
    pub cpu_percent: f64,
    /// Seconds since the game process was spawned.
    pub elapsed_secs: u64,
    /// Human-readable FPS summary from Metal HUD log (only populated if available).
    pub fps_hint: Option<String>,
}

/// Get live performance stats for a running game by UUID.
///
/// Reads RSS, VSZ, and CPU% via `ps -p <pid> -o rss,vsz,%cpu`.
/// Returns an error if the game is not currently running.
///
/// This is called from a fast frontend poll loop (every 1 s) while a game is active.
#[tauri::command]
async fn process_stats(
    state: State<'_, RunningGames>,
    game_id: String,
) -> Result<ProcessStats, String> {
    let map = state.0.lock().map_err(|e| e.to_string())?;
    let proc = map
        .get(&game_id)
        .ok_or_else(|| format!("Game '{}' is not running", game_id))?;

    let pid = proc.pid();
    let elapsed = proc.elapsed_secs();
    drop(map); // release the lock before shelling out

    // macOS ps: rss is in KB, vsz is in KB, %cpu is float
    let output = std::process::Command::new("ps")
        .args(["-p", &pid.to_string(), "-o", "rss,vsz,%cpu"])
        .output()
        .map_err(|e| format!("ps command failed: {}", e))?;

    if !output.status.success() {
        return Err(format!(
            "ps exited with status {} — game may have exited",
            output.status
        ));
    }

    let stdout = String::from_utf8_lossy(&output.stdout);
    // ps output looks like:
    //    RSS    VSZ  %CPU
    //  12345  67890  45.2
    // (the first line is the header, second is the data)
    let data_line = stdout
        .lines()
        .nth(1)
        .ok_or_else(|| "ps returned no data for pid".to_string())?;

    let parts: Vec<&str> = data_line.split_whitespace().collect();
    if parts.len() < 3 {
        return Err(format!("Unexpected ps output: {}", data_line));
    }

    let rss_kb: f64 = parts[0].parse().unwrap_or(0.0);
    let vsz_kb: f64 = parts[1].parse().unwrap_or(0.0);
    let cpu_pct: f64 = parts[2].parse().unwrap_or(0.0);

    // Also try to grab FPS hint from Metal HUD log file if it exists
    // MTL_HUD_ENABLED writes a summary to stdout which we don't capture,
    // so we can't get precise FPS here — but the in-game HUD shows it.
    // We still include the elapsed time and RAM stats from this poll.
    Ok(ProcessStats {
        pid,
        rss_mb: rss_kb / 1024.0,
        vsz_mb: vsz_kb / 1024.0,
        cpu_percent: cpu_pct,
        elapsed_secs: elapsed,
        fps_hint: None,
    })
}

/// Returns true if MangoHud is installed on this system (via Homebrew or other).
#[tauri::command]
async fn check_mangohud() -> serde_json::Value {
    let paths = ["/opt/homebrew/bin/mangohud", "/usr/local/bin/mangohud"];

    for path in &paths {
        if std::path::Path::new(path).exists() {
            return serde_json::json!({
                "installed": true,
                "path": path,
            });
        }
    }

    // Also check PATH
    if let Ok(out) = std::process::Command::new("which").arg("mangohud").output() {
        if out.status.success() {
            let p = String::from_utf8_lossy(&out.stdout).trim().to_string();
            if !p.is_empty() && std::path::Path::new(&p).exists() {
                return serde_json::json!({
                    "installed": true,
                    "path": p,
                });
            }
        }
    }

    serde_json::json!({
        "installed": false,
        "path": null,
    })
}

// ---------------------------------------------------------------------------
// Steam Cloud bridge
// ---------------------------------------------------------------------------

/// Returns the URL to a game's Steam Cloud page for manual download.
/// Steam Cloud saves ARE on Steam's servers — but Forge Launcher bypasses the
/// Steam client (which normally syncs them), so we provide a direct link.
#[tauri::command]
async fn steam_cloud_url(app_id: u64) -> Result<String, String> {
    // Steam's cloud save page for a specific app (requires Steam login)
    Ok(format!(
        "https://store.steampowered.com/account/remotestorageapp/?appid={}",
        app_id
    ))
}

/// Bulk-download all Steam Cloud saves for a game using the browser session cookie.
///
/// Requires: steamLoginSecure cookie from Firefox (extracted automatically).
/// Saves all files to `~/${target_dir}/`.
///
/// Returns: number of files downloaded and the target directory.
#[tauri::command]
async fn download_steam_cloud_saves(app_id: u64, target_dir: String) -> Result<String, String> {
    let _home = std::env::var("HOME").map_err(|_| "HOME not set".to_string())?;
    let expanded_dir = launcher::expand_tilde(&target_dir);
    let target = std::path::PathBuf::from(&expanded_dir);
    std::fs::create_dir_all(&target).map_err(|e| format!("Cannot create target dir: {}", e))?;

    // Try to find steamLoginSecure cookie from Firefox
    let cookie =
        get_firefox_steam_cookie().ok_or_else(|| FIREFOX_STEAM_COOKIE_MISSING.to_string())?;

    // Build the remote storage URL
    let rs_url = format!(
        "https://store.steampowered.com/account/remotestorageapp/?appid={}",
        app_id
    );

    // Fetch the page with session cookie — the page embeds file metadata in a JSON config
    let output = std::process::Command::new("curl")
        .args([
            "-sL",
            "-b",
            &format!("steamLoginSecure={}", cookie),
            &rs_url,
        ])
        .output()
        .map_err(|e| format!("curl failed: {}", e))?;

    let html = String::from_utf8_lossy(&output.stdout);

    // The page embeds a JSON config with the file list. For the React version,
    // file data is loaded dynamically. But the page also has <a> tags with
    // onclick handlers containing file IDs.
    //
    // We'll try two approaches:
    // 1. Look for onclick handlers with remotestoragefile and extract IDs
    // 2. Try the older page format with direct <a href> links

    let mut file_ids: Vec<String> = Vec::new();

    // Extract IDs from onclick handlers
    for cap in html.match_indices("remotestoragefile") {
        // Look for the numeric ID near this match
        let start = cap.0;
        let slice = &html[start..std::cmp::min(start + 150, html.len())];
        // Extract all numeric sequences, taking the first one after 'id='
        if let Some(id_start) = slice.find("id=") {
            let after_id = &slice[id_start + 3..];
            let digits: String = after_id
                .chars()
                .take_while(|c| c.is_ascii_digit())
                .collect();
            if !digits.is_empty() {
                file_ids.push(digits);
            }
        }
    }

    // Deduplicate
    file_ids.sort();
    file_ids.dedup();

    if file_ids.is_empty() {
        return Err("Could not find any save files on Steam Cloud.\n\n\
             The page may have changed format. As a fallback:\n\
             1. Open Firefox and go to the Steam Cloud page\n\
             2. Use the JavaScript snippet in the helper tool\n\
             3. Or click each file individually"
            .to_string());
    }

    // Download each file
    let mut count = 0u32;
    for id in &file_ids {
        let dl_url = format!(
            "https://store.steampowered.com/account/remotestoragefile/?appid={}&id={}",
            app_id, id
        );

        // Use curl with -L (follow redirects), -J (use server filename), -O (write to file)
        let dl = std::process::Command::new("curl")
            .args([
                "-sLJO",
                "-b",
                &format!("steamLoginSecure={}", cookie),
                &dl_url,
            ])
            .current_dir(&target)
            .output()
            .map_err(|e| format!("Download failed for id {}: {}", id, e))?;

        if dl.status.success() {
            count += 1;
        } else {
            eprintln!("[forge] Failed to download cloud save id={}", id);
        }
    }

    Ok(format!(
        "Downloaded {}/{} files to {}",
        count,
        file_ids.len(),
        target.display()
    ))
}

/// Try to get the steamLoginSecure cookie from Firefox.
fn get_firefox_steam_cookie() -> Option<String> {
    let home = std::env::var("HOME").ok()?;
    let profiles_dir =
        std::path::PathBuf::from(&home).join("Library/Application Support/Firefox/Profiles");

    if !profiles_dir.is_dir() {
        return None;
    }

    // Find any cookies.sqlite in Firefox profiles
    for entry in std::fs::read_dir(&profiles_dir).ok()? {
        let entry = entry.ok()?;
        let cookies_path = entry.path().join("cookies.sqlite");
        if !cookies_path.is_file() {
            continue;
        }

        // Copy the DB first (Firefox might lock it)
        let tmp = std::path::PathBuf::from("/tmp/ff_cookies_forge.db");
        std::fs::copy(&cookies_path, &tmp).ok()?;

        let output = std::process::Command::new("sqlite3")
            .args([tmp.to_str()?, STEAM_LOGIN_SECURE_QUERY])
            .output()
            .ok()?;

        if output.status.success() {
            let val = String::from_utf8_lossy(&output.stdout).trim().to_string();
            if !val.is_empty() {
                return Some(val);
            }
        }
    }

    None
}

// ---------------------------------------------------------------------------
// Entry point
// ---------------------------------------------------------------------------

fn main() {
    tauri::Builder::default()
        .plugin(tauri_plugin_dialog::init())
        .manage(RunningGames(Arc::new(Mutex::new(HashMap::new()))))
        .manage(ActiveDownloads(Arc::new(Mutex::new(HashMap::new()))))
        .invoke_handler(tauri::generate_handler![
            // Bottles
            list_bottles,
            create_bottle,
            list_runtime_profiles,
            save_runtime_profiles,
            update_bottle_runtime,
            create_peak_test_bottle,
            bottle_launcher_status,
            list_bottle_apps,
            install_steam_in_prefix,
            open_steam_in_prefix,
            repair_steam_in_prefix,
            run_exe_in_prefix,
            // Library
            load_games,
            save_games,
            upsert_game,
            remove_game,
            // Launcher
            launch_game,
            kill_game,
            running_games,
            create_prefix,
            // Config
            load_config,
            save_config,
            // Steam scanning + launching
            scan_steam_games,
            launch_steam_game,
            launch_steam_game_direct,
            // Wine detection
            check_wine,
            // Downloading
            check_download_tools,
            check_steam_credentials,
            get_cached_steam_username,
            authenticate_steam,
            download_steam_game,
            cancel_download,
            validate_game_files,
            // Save sync
            sync_game_saves,
            guess_wine_username,
            // Performance monitoring
            process_stats,
            check_mangohud,
            // Steam Cloud bridge
            steam_cloud_url,
            download_steam_cloud_saves,
        ])
        .run(tauri::generate_context!())
        .expect("error while running Tauri application");
}
