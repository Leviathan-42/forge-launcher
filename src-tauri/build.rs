// build.rs
//
// This file MUST exist at the crate root for `tauri::generate_context!()` to
// work. The macro reads tauri.conf.json at compile time and needs the build
// script to have run first so that OUT_DIR is set by Cargo.
//
// `tauri_build::build()` does three things:
//   1. Sets the OUT_DIR environment variable Cargo uses for codegen output.
//   2. Embeds the tauri.conf.json content into the binary via include_str!().
//   3. On macOS: links required system frameworks (AppKit, WebKit, etc.).

fn main() {
    tauri_build::build()
}
