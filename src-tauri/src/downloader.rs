//! downloader.rs — Download Windows Steam games on macOS via DepotDownloader.
//!
//! # The authentication problem
//!
//! DepotDownloader needs to log into Steam. On first use it prompts interactively
//! for a password and Steam Guard code. This cannot happen inside a piped process
//! because there is no TTY for the user to type into.
//!
//! # Two-phase solution
//!
//! ## Phase 1 — Authentication (one time only)
//!
//! Open macOS Terminal.app with a pre-built shell command that:
//!   1. Runs DepotDownloader with `-remember-password`
//!   2. User types their password + Steam Guard code in the terminal
//!   3. DepotDownloader saves an auth token to `~/.config/DepotDownloader/`
//!   4. Terminal window closes automatically on success
//!
//! We detect whether cached credentials exist by checking that directory.
//!
//! ## Phase 2 — Actual download (silent, progress bar works)
//!
//! Once credentials are cached, DepotDownloader runs non-interactively.
//! We pipe stderr (all output goes there) and parse progress lines.
//! The progress bar in the UI updates in real time.
//!
//! # Credential storage
//!
//! DepotDownloader stores tokens at:
//!   `~/.config/DepotDownloader/<username>.json`
//!
//! We never see, store, or transmit the password. The token is managed
//! entirely by DepotDownloader and Steam.

use std::io::{BufRead, BufReader};
use std::path::{Path, PathBuf};
use std::process::{Command, Stdio};
use std::os::fd::AsRawFd;
use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::Arc;
use std::ffi::CString;

use nix::pty::{forkpty, Winsize};
use nix::unistd::{execvp, read as nix_read};
use nix::sys::wait::{waitpid, WaitStatus};
use nix::libc;

use serde::{Deserialize, Serialize};
use tauri::{AppHandle, Emitter};

// ---------------------------------------------------------------------------
// Public types
// ---------------------------------------------------------------------------

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
#[serde(rename_all = "snake_case")]
pub enum DownloadBackend {
    DepotDownloader,
    SteamCmd,
}

impl Default for DownloadBackend {
    fn default() -> Self {
        DownloadBackend::DepotDownloader
    }
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct DownloadRequest {
    pub app_id: u64,
    pub username: String,
    pub install_dir: String,
    #[serde(default)]
    pub validate_only: bool,
    #[serde(default)]
    pub backend: DownloadBackend,
}

/// Emitted to the frontend via `"download://progress"` Tauri event.
#[derive(Debug, Clone, Serialize)]
pub struct DownloadProgress {
    pub app_id: u64,
    pub percent: f32,
    pub status: String,
    pub completed: bool,
    pub error: Option<String>,
}

#[derive(Debug, Serialize)]
pub struct ToolStatus {
    pub depot_downloader_ok: bool,
    pub depot_downloader_path: Option<String>,
    pub steamcmd_ok: bool,
    pub steamcmd_path: Option<String>,
    pub steamcmd_unavailable_reason: Option<String>,
}

// ---------------------------------------------------------------------------
// Credential cache detection
// ---------------------------------------------------------------------------

/// Returns `true` if DepotDownloader has a cached login token for `username`.
///
/// ## How DepotDownloader stores credentials
///
/// `account.config` is a deflate-compressed protobuf stored under .NET IsolatedStorage
/// at a hashed path: `~/Library/Application Support/IsolatedStorage/<hash>/…/AssemFiles/account.config`
///
/// The protobuf's `LoginTokens` field is a `map<string, string>` where the key is
/// the exact Steam username (lowercase). We decompress the file and do a raw byte
/// search for the username string — this is reliable because protobuf encodes
/// string map keys as length-prefixed UTF-8, so the exact bytes appear in sequence.
///
/// If `username` is empty we just check whether any account.config exists at all.
pub fn has_cached_credentials(username: &str) -> bool {
    let home = match std::env::var("HOME") {
        Ok(h) => h,
        Err(_) => return false,
    };

    let iso_dir = PathBuf::from(&home)
        .join("Library")
        .join("Application Support")
        .join("IsolatedStorage");

    if !iso_dir.exists() {
        return false;
    }

    let config_path = match locate_account_config(&iso_dir, 0) {
        Some(p) => p,
        None => return false,
    };

    // If no specific username requested, just confirm the file exists
    if username.is_empty() {
        return true;
    }

    // Decompress and search for username bytes in the protobuf payload
    match read_account_config_bytes(&config_path) {
        Some(bytes) => bytes_contain_username(&bytes, username),
        None => false,
    }
}

/// Return the Steam username stored in DepotDownloader's account.config, if any.
/// Returns `None` if no credentials are cached.
pub fn get_cached_username() -> Option<String> {
    let home = std::env::var("HOME").ok()?;

    let iso_dir = PathBuf::from(&home)
        .join("Library")
        .join("Application Support")
        .join("IsolatedStorage");

    let config_path = locate_account_config(&iso_dir, 0)?;
    let bytes = read_account_config_bytes(&config_path)?;

    // The username appears twice in the LoginTokens map (once as key, once embedded
    // in the JWT subject). Extract the first ASCII identifier that looks like a
    // Steam username (3-32 chars, letters/digits/underscores/hyphens).
    extract_username_from_bytes(&bytes)
}

/// Locate the account.config file by walking IsolatedStorage (max 6 levels).
fn locate_account_config(dir: &Path, depth: u8) -> Option<PathBuf> {
    if depth > 6 {
        return None;
    }

    let entries = std::fs::read_dir(dir).ok()?;
    for entry in entries.filter_map(|e| e.ok()) {
        let path = entry.path();
        if path.is_file()
            && path
                .file_name()
                .map(|n| n == "account.config")
                .unwrap_or(false)
        {
            return Some(path);
        }
        if path.is_dir() {
            if let Some(found) = locate_account_config(&path, depth + 1) {
                return Some(found);
            }
        }
    }
    None
}

/// Read and deflate-decompress account.config. Returns raw protobuf bytes.
fn read_account_config_bytes(path: &Path) -> Option<Vec<u8>> {
    use std::io::Read;
    let compressed = std::fs::read(path).ok()?;
    // .NET DeflateStream uses raw deflate (no zlib header)
    let mut decoder = flate2::read::DeflateDecoder::new(&compressed[..]);
    let mut out = Vec::new();
    decoder.read_to_end(&mut out).ok()?;
    Some(out)
}

/// Check whether the decompressed protobuf payload contains `username` as a
/// length-prefixed string (protobuf wire format).
fn bytes_contain_username(bytes: &[u8], username: &str) -> bool {
    let needle = username.to_lowercase();
    let needle_bytes = needle.as_bytes();
    // Search for the raw bytes as a substring — sufficient since usernames
    // are ASCII and always appear verbatim in the protobuf encoding.
    bytes.windows(needle_bytes.len()).any(|w| w == needle_bytes)
}

/// Extract the first string that looks like a Steam username from the protobuf.
/// Steam usernames: 3-32 chars, ASCII letters/digits/underscores/hyphens.
fn extract_username_from_bytes(bytes: &[u8]) -> Option<String> {
    let mut i = 0usize;
    while i < bytes.len() {
        // Protobuf length-delimited fields: the length byte precedes the string.
        let len = bytes[i] as usize;
        if len >= 3 && len <= 32 && i + 1 + len <= bytes.len() {
            let slice = &bytes[i + 1..i + 1 + len];
            if let Ok(s) = std::str::from_utf8(slice) {
                if s.chars()
                    .all(|c| c.is_ascii_alphanumeric() || c == '_' || c == '-')
                {
                    return Some(s.to_string());
                }
            }
        }
        i += 1;
    }
    None
}

// ---------------------------------------------------------------------------
// Tool detection
// ---------------------------------------------------------------------------

pub fn find_depot_downloader() -> Result<String, String> {
    let candidates = [
        "/opt/homebrew/bin/DepotDownloader", // ARM Homebrew (Apple Silicon)
        "/usr/local/bin/DepotDownloader",    // Intel Homebrew
        "/opt/homebrew/bin/depotdownloader",
        "/usr/local/bin/depotdownloader",
    ];

    for path in &candidates {
        if Path::new(path).exists() {
            return Ok(path.to_string());
        }
    }

    if let Ok(out) = Command::new("which").arg("DepotDownloader").output() {
        if out.status.success() {
            let p = String::from_utf8_lossy(&out.stdout).trim().to_string();
            if !p.is_empty() && Path::new(&p).exists() {
                return Ok(p);
            }
        }
    }

    Err("DepotDownloader not found.\nInstall: brew tap steamre/tools && brew install depotdownloader".to_string())
}

pub fn find_steamcmd() -> Result<String, String> {
    let home = std::env::var("HOME").unwrap_or_default();
    let candidates: &[&str] = &[
        "/opt/homebrew/bin/steamcmd",
        "/usr/local/bin/steamcmd",
        &format!("{}/steamcmd/steamcmd.sh", home),
    ];

    let exe = candidates.iter().find(|p| Path::new(*p).exists()).copied();

    let Some(exe) = exe else {
        return Err("SteamCMD not found. Install: brew install steamcmd".to_string());
    };

    // Smoke-test for the known broken Homebrew macOS ARM build
    let test = Command::new(exe)
        .arg("+quit")
        .stdout(Stdio::piped())
        .stderr(Stdio::piped())
        .output();

    match test {
        Ok(out) => {
            let combined = format!(
                "{}{}",
                String::from_utf8_lossy(&out.stdout),
                String::from_utf8_lossy(&out.stderr)
            );
            if combined.contains("Failed to load steamconsole") {
                Err("SteamCMD is installed but broken (steamconsole.dylib missing).\nThis is a known Homebrew macOS ARM bug. Use DepotDownloader instead.".to_string())
            } else {
                Ok(exe.to_string())
            }
        }
        Err(e) => Err(format!("SteamCMD test failed: {}", e)),
    }
}

pub fn check_tools() -> ToolStatus {
    let dd = find_depot_downloader();
    let sc = find_steamcmd();
    let (steamcmd_ok, steamcmd_path, steamcmd_unavailable_reason) = match sc {
        Ok(p) => (true, Some(p), None),
        Err(e) => (false, None, Some(e)),
    };
    ToolStatus {
        depot_downloader_ok: dd.is_ok(),
        depot_downloader_path: dd.ok(),
        steamcmd_ok,
        steamcmd_path,
        steamcmd_unavailable_reason,
    }
}

// ---------------------------------------------------------------------------
// Phase 1: Open Terminal for first-time authentication
// ---------------------------------------------------------------------------

/// Open macOS Terminal.app for first-time Steam authentication.
///
/// ## Why we need a terminal window
///
/// DepotDownloader requires a TTY (real terminal) to prompt for a password
/// and Steam Guard code. When we pipe its output for the progress bar there
/// is no TTY, so the interactive prompt silently crashes (exit code -1).
///
/// ## What the script does
///
/// 1. Runs DepotDownloader with `-app 0 -remember-password`.
///    AppID 0 does not exist, so after a successful login Steam returns
///    "not available" and DepotDownloader exits — but the auth token has
///    already been written to IsolatedStorage.  No game files are downloaded.
/// 2. Captures the exit and distinguishes auth success from auth failure
///    by checking whether `account.config` now exists.
/// 3. On success: prints confirmation and waits 3 s before the window closes.
/// 4. On failure: prints the error and waits for a keypress.
///
/// After this function returns the UI should poll `check_steam_credentials`
/// every second until it flips to `true`.
pub fn open_terminal_for_auth(username: &str) -> Result<(), String> {
    let dd_path = find_depot_downloader()?;

    // account.config lives somewhere under this directory after a successful login.
    // We pass this path into the shell script so it can verify auth succeeded
    // without needing to know the exact hashed subdirectory.
    let iso_base = {
        let home = std::env::var("HOME").unwrap_or_else(|_| "~".to_string());
        format!("{}/Library/Application Support/IsolatedStorage", home)
    };

    // The shell script:
    //  - Runs DepotDownloader against AppID 0 (no download, just auth)
    //  - Checks if account.config now exists anywhere under IsolatedStorage
    //  - Prints clear success/failure and closes or waits for keypress
    let auth_script = format!(
        r#"clear
printf '\033[1mForge Launcher — Steam Login\033[0m\n'
printf '─────────────────────────────────────\n'
printf 'Enter your Steam password when prompted.\n'
printf 'If Steam Guard is enabled enter the code\n'
printf 'from your phone or email.\n\n'
'{dd}' -app 0 -username '{user}' -remember-password 2>&1
printf '\n'
if find '{iso}' -name 'account.config' -maxdepth 6 | grep -q .; then
  printf '\033[32m✓ Login successful! Credentials cached.\033[0m\n'
  printf 'You can close this window and click\n'
  printf '"I'"'"'ve logged in" in Forge Launcher.\n'
  sleep 3
else
  printf '\033[31m✗ Login failed.\033[0m\n'
  printf 'Check your username, password, and Steam Guard code.\n'
  printf 'Press any key to close...\n'
  read -rsk 1
fi"#,
        dd = dd_path,
        user = username,
        iso = iso_base,
    );

    // Write the script to a temp file so we avoid any quoting nightmares
    // when passing it through osascript → Terminal → sh
    let script_path = "/tmp/forge_steam_auth.sh";
    std::fs::write(script_path, &auth_script)
        .map_err(|e| format!("Failed to write auth script: {}", e))?;
    std::fs::set_permissions(
        script_path,
        std::os::unix::fs::PermissionsExt::from_mode(0o755),
    )
    .map_err(|e| format!("Failed to chmod auth script: {}", e))?;

    // Open Terminal.app and run the script file — no inline quoting issues
    let osa = format!(
        r#"tell application "Terminal"
    activate
    do script "{script}"
end tell"#,
        script = script_path,
    );

    let status = Command::new("osascript")
        .arg("-e")
        .arg(&osa)
        .status()
        .map_err(|e| format!("Failed to open Terminal: {}", e))?;

    if status.success() {
        Ok(())
    } else {
        Err("Failed to open Terminal.app for authentication".to_string())
    }
}

// ---------------------------------------------------------------------------
// Phase 2: Silent download with progress events
// ---------------------------------------------------------------------------

pub fn download_game(
    app_handle: AppHandle,
    req: DownloadRequest,
    cancelled: Arc<AtomicBool>,
) -> Result<(), String> {
    // Expand ~ in install_dir
    let install_dir = crate::launcher::expand_tilde(&req.install_dir);

    std::fs::create_dir_all(&install_dir)
        .map_err(|e| format!("Cannot create install dir '{}': {}", install_dir, e))?;

    let req = DownloadRequest { install_dir, ..req };

    let emit = |percent: f32, status: &str, completed: bool, error: Option<String>| {
        let _ = app_handle.emit(
            "download://progress",
            DownloadProgress {
                app_id: req.app_id,
                percent,
                status: status.to_string(),
                completed,
                error,
            },
        );
    };

    match req.backend {
        DownloadBackend::DepotDownloader => run_depot_downloader(&req, cancelled, emit),
        DownloadBackend::SteamCmd => run_steamcmd(&req, cancelled, emit),
    }
}

// ---------------------------------------------------------------------------
// DepotDownloader runner — uses a PTY so progress ANSI escape codes are emitted
// ---------------------------------------------------------------------------

fn run_depot_downloader<F>(
    req: &DownloadRequest,
    cancelled: Arc<AtomicBool>,
    emit: F,
) -> Result<(), String>
where
    F: Fn(f32, &str, bool, Option<String>),
{
    let exe = find_depot_downloader()?;

    // Build argv
    let mut args: Vec<CString> = vec![
        CString::new(exe.as_bytes()).unwrap(),
        CString::new("-app").unwrap(),
        CString::new(req.app_id.to_string()).unwrap(),
        CString::new("-os").unwrap(),
        CString::new("windows").unwrap(),
        CString::new("-username").unwrap(),
        CString::new(req.username.as_bytes()).unwrap(),
        CString::new("-remember-password").unwrap(),
        CString::new("-dir").unwrap(),
        CString::new(req.install_dir.as_bytes()).unwrap(),
    ];

    if req.validate_only {
        args.push(CString::new("-validate").unwrap());
    }

    // Fork with a PTY so DepotDownloader sees a real terminal and emits ANSI progress
    let winsize = Winsize {
        ws_row: 24,
        ws_col: 120,
        ws_xpixel: 0,
        ws_ypixel: 0,
    };

    let fork_result = unsafe { forkpty(Some(&winsize), None) }
        .map_err(|e| format!("forkpty failed: {}", e))?;

    match fork_result {
        nix::pty::ForkptyResult::Child => {
            // Child: exec DepotDownloader. The PTY becomes its stdin/stdout/stderr.
            let args_refs: Vec<&CString> = args.iter().collect();
            let _ = execvp(&args_refs[0], &args_refs);
            // execvp never returns on success
            std::process::exit(1);
        }
        nix::pty::ForkptyResult::Parent { master, child: _ } => {
            // Parent continues below
            run_depot_downloader_parent(req, cancelled, emit, master)
        }
    }
}

fn run_depot_downloader_parent<F>(
    _req: &DownloadRequest,
    cancelled: Arc<AtomicBool>,
    emit: F,
    master: std::os::unix::io::OwnedFd,
) -> Result<(), String>
where
    F: Fn(f32, &str, bool, Option<String>),
{
    let master_fd = master.as_raw_fd();

    emit(0.0, "Connecting to Steam…", false, None);

    let mut last_pct: f32 = 0.0;
    let mut last_status = String::from("Connecting to Steam…");
    let mut saw_depots = false;
    let mut total_bytes_line = String::new();
    let mut buf = [0u8; 4096];
    let mut line_buf = String::new();

    // ESC state machine for ANSI escape sequences
    enum EscState {
        Normal,
        GotEsc,
        InOsc(String),  // collecting OSC payload
    }
    let mut esc_state = EscState::Normal;

    loop {
        if cancelled.load(Ordering::SeqCst) {
            unsafe { libc::kill(-(libc::tcgetpgrp(master_fd)), libc::SIGTERM); }
            emit(0.0, "Cancelled", false, Some("Download cancelled".to_string()));
            return Err("Cancelled".to_string());
        }

        let n = match nix_read(master_fd, &mut buf) {
            Ok(0) => break,
            Ok(n) => n,
            Err(nix::errno::Errno::EAGAIN) | Err(nix::errno::Errno::EINTR) => continue,
            Err(e) => {
                emit(last_pct, &format!("Read error: {}", e), false, Some(format!("IO error: {}", e)));
                break;
            }
        };

        for &byte in &buf[..n] {
            match esc_state {
                EscState::Normal => {
                    if byte == 0x1b {
                        esc_state = EscState::GotEsc;
                    } else if byte == b'\n' {
                        let trimmed = line_buf.trim().to_string();
                        line_buf.clear();
                        if !trimmed.is_empty() {
                            track_status(&trimmed, &mut last_status, &mut saw_depots, &mut total_bytes_line);
                            emit(last_pct, &trimmed, false, None);
                        }
                    } else if byte != b'\r' {
                        line_buf.push(byte as char);
                    }
                }
                EscState::GotEsc => {
                    if byte == b']' {
                        esc_state = EscState::InOsc(String::new());
                    } else if byte == b'[' {
                        // CSI sequence — skip until terminating letter
                        esc_state = EscState::Normal;
                    } else {
                        // Unknown escape — reset
                        esc_state = EscState::Normal;
                    }
                }
                EscState::InOsc(ref mut buf) => {
                    if byte == 0x07 {
                        // BEL terminates OSC
                        if let Some(pct) = parse_ansi_progress(buf) {
                            last_pct = pct;
                        }
                        esc_state = EscState::Normal;
                    } else if byte == 0x1b {
                        // ESC inside OSC — ST (ESC \) terminator, or start of another escape
                        // Treat as OSC end
                        if let Some(pct) = parse_ansi_progress(buf) {
                            last_pct = pct;
                        }
                        esc_state = EscState::GotEsc;
                    } else {
                        buf.push(byte as char);
                    }
                }
            }
        }
    }

    // Wait for the child process
    let exit_code = match waitpid(None, None) {
        Ok(WaitStatus::Exited(_, code)) => code,
        Ok(WaitStatus::Signaled(_, sig, _)) => 128 + sig as i32,
        Ok(_) => 0,
        Err(e) => {
            return Err(format!("waitpid failed: {}", e));
        }
    };

    match exit_code {
        0 => {
            let msg = if !total_bytes_line.is_empty() {
                format!("Done! {}", total_bytes_line)
            } else if saw_depots {
                "Download complete!".to_string()
            } else {
                "Done — files are up to date or no depots were needed.".to_string()
            };
            emit(100.0, &msg, true, None);
            Ok(())
        }
        -1 | 134 => {
            let msg = "Authentication failed — credentials may have expired. \
                       Log in again via 'Login with Steam'."
                .to_string();
            emit(0.0, &msg, false, Some(msg.clone()));
            Err(msg)
        }
        other => {
            let msg = format!(
                "DepotDownloader exited with code {}. Last status: {}",
                other, last_status
            );
            emit(last_pct, &msg, false, Some(msg.clone()));
            Err(msg)
        }
    }
}

/// Update status tracking from a text line emitted by DepotDownloader.
fn track_status(line: &str, last_status: &mut String, saw_depots: &mut bool, total_bytes_line: &mut String) {
    if line.starts_with("Downloading depot")
        || line.starts_with("Processing depot")
        || line.starts_with("Progress:")
        || line.contains("Connecting")
        || line.contains("Logging")
        || line.contains("Pre-allocating")
        || line.contains("total bytes")
    {
        *last_status = line.to_string();
    }
    if line.contains("Downloading depot") {
        *saw_depots = true;
    }
    if line.contains("total bytes") {
        *total_bytes_line = line.to_string();
    }
}

/// Parse an ANSI OSC 9;4 progress sequence (DepotDownloader / Windows Terminal format).
/// Format: `9;4;<state>;<percent>`
/// Returns the percent value (0-100) or None if parsing fails.
fn parse_ansi_progress(osc_payload: &str) -> Option<f32> {
    // Strip any leading ']' that got included (from ESC ] detection)
    let payload = osc_payload.strip_prefix(']').unwrap_or(osc_payload);

    let parts: Vec<&str> = payload.split(';').collect();
    if parts.len() >= 4 && parts[0] == "9" && parts[1] == "4" {
        // parts[2] is state (0-4), parts[3] is progress (0-100)
        if let Ok(pct) = parts[3].parse::<u8>() {
            return Some(pct as f32);
        }
    }
    None
}

// ---------------------------------------------------------------------------
// SteamCMD runner (fallback)
// ---------------------------------------------------------------------------

fn run_steamcmd<F>(req: &DownloadRequest, cancelled: Arc<AtomicBool>, emit: F) -> Result<(), String>
where
    F: Fn(f32, &str, bool, Option<String>),
{
    let exe = find_steamcmd()?;

    let mut cmd = Command::new(&exe);
    cmd.args([
        "+@sSteamCmdForcePlatformType",
        "windows",
        "+@sSteamCmdForcePlatformBitness",
        "64",
        "+@ShutdownOnFailedCommand",
        "1",
        "+force_install_dir",
        &req.install_dir,
        "+login",
        &req.username,
        "+app_update",
        &req.app_id.to_string(),
    ]);

    if req.validate_only {
        cmd.arg("validate");
    }
    cmd.arg("+quit");
    cmd.stdout(Stdio::piped()).stderr(Stdio::null());

    let mut child = cmd
        .spawn()
        .map_err(|e| format!("Failed to start SteamCMD: {}", e))?;

    let stdout = child.stdout.take().unwrap();
    let reader = BufReader::new(stdout);

    emit(0.0, "Starting SteamCMD…", false, None);

    for line in reader.lines() {
        if cancelled.load(Ordering::SeqCst) {
            let _ = child.kill();
            emit(0.0, "Cancelled", false, Some("Cancelled".to_string()));
            return Err("Cancelled".to_string());
        }

        let line = match line {
            Ok(l) => l,
            Err(_) => continue,
        };
        let trimmed = line.trim();
        if trimmed.is_empty() {
            continue;
        }

        let percent = parse_steamcmd_progress(trimmed);
        let completed = trimmed.contains("fully installed") || trimmed.contains("up to date");

        emit(percent.unwrap_or(0.0), trimmed, completed, None);
        if completed {
            break;
        }
    }

    let status = child.wait().map_err(|e| e.to_string())?;
    if status.success() {
        emit(100.0, "Download complete!", true, None);
        Ok(())
    } else {
        let msg = format!("SteamCMD exited with code {}", status.code().unwrap_or(-1));
        emit(0.0, &msg, false, Some(msg.clone()));
        Err(msg)
    }
}

fn parse_steamcmd_progress(line: &str) -> Option<f32> {
    if line.contains("fully installed") || line.contains("up to date") {
        return Some(100.0);
    }
    if let Some(start) = line.find('[') {
        if let Some(end) = line[start..].find('%') {
            let inner = line[start + 1..start + end].trim();
            if inner != "----" {
                return inner.parse::<f32>().ok();
            }
        }
    }
    None
}
