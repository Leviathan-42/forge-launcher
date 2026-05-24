# Downloading Windows Steam Games on macOS

## Why the macOS Steam client can't do this

The macOS Steam client contacts Steam's servers and asks for your library.
Steam's API filters the response to only return games whose depot manifests
include `"macos"` in their `oslist`. Windows-only games never appear.
This is enforced server-side — there is no client setting to override it.

---

## The two tools that actually work

### DepotDownloader (recommended)

- **What it is:** Open-source .NET 8 tool by SteamRE that speaks the Steam
  protocol directly and can request any depot for any platform.
- **ARM64 native:** Has a `macos-arm64` binary — runs natively on Apple Silicon,
  no Rosetta needed.
- **Install:**
  ```sh
  brew tap steamre/tools
  brew install depotdownloader
  ```
  Or download the binary directly from:
  https://github.com/SteamRE/DepotDownloader/releases
  (grab `DepotDownloader-macos-arm64.zip`)

- **Key flags Forge Launcher uses:**
  ```sh
  DepotDownloader \
    -app 1245620 \          # Steam AppID
    -os windows \           # Force Windows depot
    -username yourname \    # Your Steam account
    -remember-password \    # Cache credentials after first use
    -dir ~/Games/1245620    # Where to put the files
  ```

### SteamCMD (fallback)

- **What it is:** Valve's official headless Steam client, intended for
  game server operators but works for any Steam content.
- **x86_64 only:** Valve has never shipped an ARM64 build. Runs via Rosetta 2
  on Apple Silicon — the same way we run games.
- **Install:**
  ```sh
  brew install steamcmd
  ```
  Or manually:
  ```sh
  mkdir ~/steamcmd && cd ~/steamcmd
  curl -O http://media.steampowered.com/client/installer/steamcmd_osx.tar.gz
  tar -xvzf steamcmd_osx.tar.gz
  ```

- **Key flags Forge Launcher uses:**
  ```sh
  arch -x86_64 steamcmd \
    +@sSteamCmdForcePlatformType windows \
    +@sSteamCmdForcePlatformBitness 64 \
    +@ShutdownOnFailedCommand 1 \
    +force_install_dir ~/Games/1245620 \
    +login yourname \
    +app_update 1245620 validate \
    +quit
  ```

---

## Authentication and Steam Guard

Both tools require your Steam account credentials because game files are
associated with your purchase.

### First run
On first use, you'll be prompted for your Steam password and Steam Guard
code (the 2FA code from your phone or email) in a terminal-style prompt
inside the Forge Launcher log output.

### Subsequent runs
Both tools cache an authentication token so you don't have to re-enter
credentials. DepotDownloader stores this in `~/.config/DepotDownloader/`.
SteamCMD stores it in `~/steamcmd/config/`.

**Forge Launcher never sees, stores, or transmits your password.**

---

## Flow inside Forge Launcher

```
User clicks "Download Game"
  → invoke("download_steam_game", { app_id, username, install_dir, backend })
  → Rust: spawn_blocking(|| downloader::download_game(...))
  → Rust: Command::new("DepotDownloader").args([...]).stdout(Stdio::piped())
  → Rust: read stdout line-by-line
  → Rust: parse "Progress: 45.23%" → emit("download://progress", { percent: 45.23, ... })
  → Frontend: listen("download://progress") → update progress bar
  → On "Done!" → emit completed: true → add game to library
```

The download runs in a **blocking thread** (not async) because it's pure
synchronous I/O. Tauri's `spawn_blocking` moves it off the async runtime.
The UI stays fully responsive throughout.

---

## Progress event format

The Rust backend emits `"download://progress"` events with this payload:

```ts
interface DownloadProgress {
  app_id:    number;   // Steam AppID
  percent:   number;   // 0.0 – 100.0
  status:    string;   // Raw status line from the tool
  completed: boolean;  // true when download finishes successfully
  error:     string | null; // Non-null on failure
}
```

Listen in any Svelte component:

```ts
import { listen } from "@tauri-apps/api/event";

const unlisten = await listen<DownloadProgress>("download://progress", (e) => {
  console.log(e.payload.percent, e.payload.status);
});

// Clean up:
onDestroy(() => unlisten());
```

---

## After downloading

DepotDownloader and SteamCMD place game files at your chosen `install_dir`.
The game is automatically added to your Forge Launcher library, but the
`.exe` path is left blank because the primary executable location varies
by game.

**To complete setup:**
1. Open the game's detail panel in Forge Launcher
2. Set the `.exe path` field to the game's main executable
3. Optionally assign a Wine prefix
4. Click Launch

**Finding the exe:** Most games put their main binary in the root of the
install dir or in a `bin/`, `Game/`, or `<GameName>/` subdirectory.
SteamDB (https://www.steamdb.info/app/<id>/info/) shows the launch
configuration Valve uses on Windows, which tells you the exact exe path.

---

## Troubleshooting

### "Invalid platform" error from SteamCMD
Some games have had their platform flags changed. Try DepotDownloader instead
— it handles this more reliably.

### Steam Guard keeps prompting
Run the download once manually in Terminal first:
```sh
DepotDownloader -app 1245620 -os windows -username yourname -remember-password -dir /tmp/test
```
Complete the Steam Guard prompt, then subsequent Forge Launcher downloads
won't need it.

### Download stops mid-way / slow speed
Steam CDN throttles downloads for some accounts. This is a Steam-side limit,
not a Forge Launcher issue. Try again later or use `-max-downloads 4` (lower
concurrency) in a manual DepotDownloader run.

### Game won't launch after downloading
1. Check the `.exe` path is set correctly in the detail panel
2. Make sure your Wine prefix is initialised (`create_prefix` command)
3. Check `docs/SETUP.md` for GPTK library path configuration
4. Try enabling verbose Wine output: set `suppress_wine_debug: false` in Settings

---

## Comparison table

| | DepotDownloader | SteamCMD |
|---|---|---|
| Architecture | ARM64 native | x86_64 (Rosetta) |
| Maintained by | SteamRE (community) | Valve (official) |
| Progress output | Clean `Progress: X%` lines | `[ XX%] Downloading...` |
| Credential caching | Yes (`~/.config/DepotDownloader/`) | Yes (`~/steamcmd/config/`) |
| Speed | Slightly faster (no Rosetta overhead) | Slightly slower |
| Validate existing files | `-validate` flag | `validate` argument |
| Free-to-play games | Yes (anonymous login works for some) | Yes |
| Games you own | Yes (login required) | Yes |
