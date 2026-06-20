//! steam.rs — Steam library scanning and launch integration.
//!
//! # How Steam game detection works
//!
//! Steam stores metadata for every installed game in ACF (AppCache Format)
//! manifest files inside its `steamapps/` directory:
//!
//! ```
//! ~/Library/Application Support/Steam/steamapps/
//!   appmanifest_220.acf       ← Half-Life 2 (AppID 220)
//!   appmanifest_570.acf       ← Dota 2 (AppID 570)
//!   libraryfolders.vdf        ← additional Steam library roots
//!   common/
//!     Half-Life 2/            ← actual game files
//! ```
//!
//! ACF is a simple key-value format. We parse only the fields we need with a
//! minimal hand-rolled parser (no external dependency) rather than pulling in
//! a full VDF crate.
//!
//! # Steam launch modes
//!
//! | Mode              | Command                                      | Notes                          |
//! |-------------------|----------------------------------------------|--------------------------------|
//! | Protocol (safe)   | `open steam://rungameid/<id>`                | Steam handles everything       |
//! | Direct (advanced) | `arch -x86_64 wine64 SteamService.exe`       | bypasses Steam client entirely |
//!
//! Use the protocol mode unless you have a specific reason to go direct.

use serde::{Deserialize, Serialize};
use std::path::{Path, PathBuf};

// ---------------------------------------------------------------------------
// SteamGame — metadata returned to the frontend
// ---------------------------------------------------------------------------

/// Metadata for a single Steam game detected in the local library.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct SteamGame {
    /// Steam numeric application identifier.
    pub app_id: u64,
    /// Display name as written in the ACF manifest.
    pub name: String,
    /// Absolute path to the game's install directory on macOS.
    pub install_dir: String,
    /// Absolute path to the primary Windows .exe (best-effort detection).
    pub exe_path: String,
    /// Raw `oslist` field from the manifest (e.g. "windows", "macos,windows").
    pub os_list: String,
    /// Size on disk in bytes.
    pub size_on_disk: u64,
}

// ---------------------------------------------------------------------------
// ACF parser — minimal hand-rolled VDF key-value reader
// ---------------------------------------------------------------------------

/// Extract a value for a given key from an ACF file's contents.
///
/// ACF lines look like:  `\t"key"\t\t"value"`
/// This function returns the first match or `None`.
fn acf_value<'a>(contents: &'a str, key: &str) -> Option<&'a str> {
    for line in contents.lines() {
        let trimmed = line.trim();
        // Lines look like: "key"  "value"  (with tab separators)
        if trimmed.starts_with('"') {
            let parts: Vec<&str> = trimmed.splitn(4, '"').collect();
            // parts[0]="", parts[1]=key, parts[2]=whitespace, parts[3]=value
            if parts.len() >= 4 && parts[1] == key {
                return Some(parts[3]);
            }
        }
    }
    None
}

// ---------------------------------------------------------------------------
// Library root detection — handles multiple Steam library folders
// ---------------------------------------------------------------------------

/// Collect all Steam library roots from `libraryfolders.vdf`.
///
/// Returns a Vec of absolute paths, always including the primary Steam dir.
fn steam_library_roots(primary: &Path) -> Vec<PathBuf> {
    let mut roots = vec![primary.to_path_buf()];

    let vdf_path = primary.join("libraryfolders.vdf");
    if let Ok(contents) = std::fs::read_to_string(&vdf_path) {
        // Library entries look like:  "path"  "/Volumes/Games/Steam"
        for line in contents.lines() {
            let trimmed = line.trim();
            if trimmed.starts_with('"') {
                let parts: Vec<&str> = trimmed.splitn(4, '"').collect();
                if parts.len() >= 4 && parts[1] == "path" {
                    let p = PathBuf::from(parts[3]).join("steamapps");
                    if p.is_dir() && p != primary {
                        roots.push(p);
                    }
                }
            }
        }
    }

    roots
}

// ---------------------------------------------------------------------------
// exe detection — best-effort heuristic
// ---------------------------------------------------------------------------

/// Attempt to find the main Windows .exe inside a game's install directory.
///
/// Strategy (in order):
/// 1. Single .exe at the root — obvious candidate.
/// 2. An .exe whose stem matches the game name (case-insensitive).
/// 3. The largest .exe at the root (usually the main binary).
/// 4. Fall back to an empty string (user can set it manually in the UI).
fn find_main_exe(install_dir: &Path, game_name: &str) -> String {
    let Ok(entries) = std::fs::read_dir(install_dir) else {
        return String::new();
    };

    let exes: Vec<PathBuf> = entries
        .filter_map(|e| e.ok())
        .map(|e| e.path())
        .filter(|p| {
            p.is_file()
                && p.extension()
                    .and_then(|e| e.to_str())
                    .map(|e| e.eq_ignore_ascii_case("exe"))
                    .unwrap_or(false)
        })
        .collect();

    if exes.is_empty() {
        return String::new();
    }
    if exes.len() == 1 {
        return exes[0].to_string_lossy().to_string();
    }

    // Prefer an exe whose stem matches game name
    let name_lower = game_name.to_lowercase().replace(' ', "");
    if let Some(matched) = exes.iter().find(|p| {
        p.file_stem()
            .and_then(|s| s.to_str())
            .map(|s| s.to_lowercase().replace(' ', "") == name_lower)
            .unwrap_or(false)
    }) {
        return matched.to_string_lossy().to_string();
    }

    // Fall back to the largest exe
    exes.iter()
        .max_by_key(|p| std::fs::metadata(p).map(|m| m.len()).unwrap_or(0))
        .map(|p| p.to_string_lossy().to_string())
        .unwrap_or_default()
}

// ---------------------------------------------------------------------------
// Public API
// ---------------------------------------------------------------------------

/// Scan all Steam library roots and return detected Windows-only games.
///
/// A game is included when its `oslist` field does **not** contain "macos"
/// (indicating it has no native Mac build and needs Wine to run).
///
/// Returns an error string if the primary Steam directory doesn't exist.
pub fn scan_steam_library() -> Result<Vec<SteamGame>, String> {
    let home =
        std::env::var("HOME").map_err(|_| "HOME environment variable not set".to_string())?;

    let primary_steamapps =
        PathBuf::from(&home).join("Library/Application Support/Steam/steamapps");

    if !primary_steamapps.is_dir() {
        return Err(format!(
            "Steam steamapps directory not found at: {}",
            primary_steamapps.display()
        ));
    }

    let mut games = Vec::new();

    for library_root in steam_library_roots(&primary_steamapps) {
        let Ok(entries) = std::fs::read_dir(&library_root) else {
            continue;
        };

        for entry in entries.filter_map(|e| e.ok()) {
            let path = entry.path();

            // Only process appmanifest_*.acf files
            let fname = path
                .file_name()
                .and_then(|n| n.to_str())
                .unwrap_or_default();

            if !fname.starts_with("appmanifest_") || !fname.ends_with(".acf") {
                continue;
            }

            let Ok(contents) = std::fs::read_to_string(&path) else {
                continue;
            };

            // Parse required fields — skip manifest if any are missing
            let Some(app_id_str) = acf_value(&contents, "appid") else {
                continue;
            };
            let Some(name) = acf_value(&contents, "name") else {
                continue;
            };
            let Some(install_dir_name) = acf_value(&contents, "installdir") else {
                continue;
            };

            let Ok(app_id) = app_id_str.parse::<u64>() else {
                continue;
            };

            let os_list = acf_value(&contents, "oslist")
                .unwrap_or("windows")
                .to_string();

            // Skip games that have a native macOS build
            if os_list.contains("macos") {
                continue;
            }

            let size_on_disk = acf_value(&contents, "SizeOnDisk")
                .and_then(|s| s.parse::<u64>().ok())
                .unwrap_or(0);

            let install_path = library_root.join("common").join(install_dir_name);
            let exe_path = find_main_exe(&install_path, name);

            games.push(SteamGame {
                app_id,
                name: name.to_string(),
                install_dir: install_path.to_string_lossy().to_string(),
                exe_path,
                os_list,
                size_on_disk,
            });
        }
    }

    // Sort alphabetically for consistent UI ordering
    games.sort_by_key(|game| game.name.to_lowercase());

    Ok(games)
}

/// Launch a Steam game via the `steam://` URI scheme.
///
/// This opens the Steam client and asks it to launch the game identified by
/// `app_id`. Steam handles authentication, updates, and the overlay.
///
/// Uses: `open -a Steam steam://rungameid/<app_id>`
pub fn launch_via_steam_protocol(app_id: u64) -> Result<(), String> {
    let status = std::process::Command::new("open")
        .args(["-a", "Steam", &format!("steam://rungameid/{}", app_id)])
        .status()
        .map_err(|e| format!("Failed to open Steam URI: {}", e))?;

    if status.success() {
        Ok(())
    } else {
        Err(format!(
            "open -a Steam exited with status: {}",
            status.code().unwrap_or(-1)
        ))
    }
}
