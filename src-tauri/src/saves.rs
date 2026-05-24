//! saves.rs — Save file sync between macOS and Wine prefix.
//!
//! # Problem
//!
//! When running a Windows game through Wine, the game saves to its normal
//! Windows path *inside the Wine prefix*.  These saves have no connection to
//! Steam Cloud or any macOS-side backup.
//!
//! # Solution
//!
//! Per-game configurable save path mappings:
//!
//! | Field        | Meaning                                              |
//! |--------------|------------------------------------------------------|
//! | `source`     | macOS directory where your saves live (e.g. backup)  |
//! | `target`     | Save directory inside the Wine prefix                |
//!
//! **Before launch:** files are copied FROM source INTO target (Wine prefix),
//! so the game picks up your latest progress.
//!
//! **After exit:** files are copied FROM target (Wine prefix) BACK TO source,
//! so the new progress is saved to your macOS backup / Steam cloud location.
//!
//! Both paths support tilde (~) expansion and must point to directories.

use std::path::{Path, PathBuf};

use crate::launcher::expand_tilde;

// ---------------------------------------------------------------------------
// SaveMapping — one save location pair
// ---------------------------------------------------------------------------

/// A pairing of a macOS-side save directory and its Wine-prefix counterpart.
#[derive(Debug, Clone, serde::Serialize, serde::Deserialize)]
pub struct SaveMapping {
    /// macOS directory where saves are stored / backed up (e.g. ~/Documents/ULTRAKILL Saves).
    /// This is where your existing progress lives and where new saves will land.
    pub source: String,

    /// Absolute path to the save directory inside the Wine prefix
    /// (e.g. ~/Wine/Bottles/default/drive_c/users/levi/AppData/LocalLow/Hakita/ULTRAKILL/Saves).
    /// This is where the running game expects to find and write its saves.
    pub target: String,
}

/// Which direction to sync.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum SyncDirection {
    /// Copy from source (macOS) into target (Wine prefix) — before launch.
    ToPrefix,
    /// Copy from target (Wine prefix) back to source (macOS) — after exit.
    FromPrefix,
}

// ---------------------------------------------------------------------------
// Sync helpers
// ---------------------------------------------------------------------------

/// Recursively copy a directory from `src` to `dst`.
///
/// Creates `dst` if it doesn't exist. Overwrites existing files.
/// Returns the number of files copied or an error message.
fn copy_dir_recursive(src: &Path, dst: &Path) -> Result<u64, String> {
    if !src.exists() {
        return Err(format!("Source directory does not exist: {}", src.display()));
    }
    if !src.is_dir() {
        return Err(format!("Source is not a directory: {}", src.display()));
    }

    std::fs::create_dir_all(dst)
        .map_err(|e| format!("Cannot create target directory {}: {}", dst.display(), e))?;

    let mut count: u64 = 0;

    for entry in std::fs::read_dir(src).map_err(|e| format!("Read dir {}: {}", src.display(), e))? {
        let entry = entry.map_err(|e| format!("Dir entry error in {}: {}", src.display(), e))?;
        let src_path = entry.path();
        let fname = src_path
            .file_name()
            .ok_or_else(|| format!("Path has no file name: {}", src_path.display()))?;
        let dst_path = dst.join(fname);

        if src_path.is_dir() {
            count += copy_dir_recursive(&src_path, &dst_path)?;
        } else if src_path.is_symlink() {
            // Copy symlink target instead of the link itself
            let resolved = std::fs::read_link(&src_path)
                .map_err(|e| format!("Read symlink {}: {}", src_path.display(), e))?;
            // If the symlink points to an absolute path, use it directly
            // If relative, resolve relative to the symlink's parent directory
            let resolved_abs = if resolved.is_absolute() {
                resolved
            } else {
                src_path.parent().unwrap_or(Path::new("/")).join(&resolved)
            };

            if resolved_abs.is_dir() {
                count += copy_dir_recursive(&resolved_abs, &dst_path)?;
            } else if resolved_abs.is_file() {
                std::fs::copy(&resolved_abs, &dst_path)
                    .map_err(|e| format!("Copy symlinked file {} → {}: {}", resolved_abs.display(), dst_path.display(), e))?;
                count += 1;
            }
        } else {
            std::fs::copy(&src_path, &dst_path)
                .map_err(|e| format!("Copy {} → {}: {}", src_path.display(), dst_path.display(), e))?;
            count += 1;
        }
    }

    Ok(count)
}

/// Sync saves for one mapping in the given direction.
fn sync_one(direction: SyncDirection, mapping: &SaveMapping) -> Result<u64, String> {
    let source = PathBuf::from(expand_tilde(&mapping.source));
    let target = PathBuf::from(expand_tilde(&mapping.target));

    let (src, dst, dir_label) = match direction {
        SyncDirection::ToPrefix => (&source, &target, "Wine prefix"),
        SyncDirection::FromPrefix => (&target, &source, "macOS backup"),
    };

    if !src.exists() {
        eprintln!(
            "[forge] Save sync skipped — {} directory not found: {}",
            if matches!(direction, SyncDirection::ToPrefix) {
                "source "
            } else {
                "Wine "
            },
            src.display()
        );
        return Ok(0);
    }

    let count = copy_dir_recursive(src, dst)?;
    if count > 0 {
        eprintln!(
            "[forge] Save sync: {} {} file(s) → {}",
            if matches!(direction, SyncDirection::ToPrefix) {
                "loaded"
            } else {
                "saved"
            },
            count,
            dir_label
        );
    }
    Ok(count)
}

/// Sync saves for a list of mappings in the given direction.
///
/// Returns the total number of files copied.
pub fn sync_saves(
    direction: SyncDirection,
    mappings: &[SaveMapping],
) -> Result<u64, String> {
    let mut total = 0u64;
    let mut first_err: Option<String> = None;

    for mapping in mappings {
        match sync_one(direction, mapping) {
            Ok(n) => total += n,
            Err(e) => {
                eprintln!("[forge] Save sync error: {}", e);
                if first_err.is_none() {
                    first_err = Some(e);
                }
            }
        }
    }

    // Return the first error if all mappings failed, otherwise just warn
    if total == 0 && first_err.is_some() {
        Err(first_err.unwrap())
    } else {
        Ok(total)
    }
}

// ---------------------------------------------------------------------------
// Path helpers for display
// ---------------------------------------------------------------------------

/// Guess the Wine username inside a prefix by listing drive_c/users/.
/// Falls back to the macOS $USER if no users dir exists yet.
pub fn guess_wine_username(prefix_path: &str) -> String {
    let prefix = expand_tilde(prefix_path);
    let users_dir = PathBuf::from(&prefix).join("drive_c/users");

    if let Ok(entries) = std::fs::read_dir(&users_dir) {
        for entry in entries.filter_map(|e| e.ok()) {
            let name = entry.file_name();
            let name_str = name.to_string_lossy();
            // Skip Windows virtual users like Public, Default, All Users
            if name_str == "Public" || name_str == "Default" || name_str == "All Users" {
                continue;
            }
            if entry.path().is_dir() {
                return name_str.to_string();
            }
        }
    }

    // Fall back to macOS username
    std::env::var("USER").unwrap_or_else(|_| "steamuser".to_string())
}
