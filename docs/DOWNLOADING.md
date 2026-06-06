# Downloading Windows Games

Forge's current direction is launcher/bottle-first. The preferred way to install Windows games is to run the Windows launcher inside a Forge Wine bottle and let that launcher install the game.

For Steam games, that means Windows Steam inside the bottle.

## Recommended flow

```text
Open Forge
  -> launch/install Windows Steam in the bottle
  -> sign into Steam
  -> install Windows games from Steam
  -> press Refresh in Forge
  -> launch the detected game entry or launch from Steam
```

This keeps Steam authentication, updates, DRM, cloud saves, and Steamworks behavior intact.

## Direct download tools

DepotDownloader and SteamCMD are still useful for advanced repair or depot experiments, but they are no longer the main user workflow.

### DepotDownloader

```sh
brew tap steamre/tools
brew install depotdownloader
```

Example:

```sh
DepotDownloader \
  -app 1245620 \
  -os windows \
  -username yourname \
  -remember-password \
  -dir ~/Games/1245620
```

### SteamCMD

```sh
brew install steamcmd
```

Example:

```sh
arch -x86_64 steamcmd \
  +@sSteamCmdForcePlatformType windows \
  +@sSteamCmdForcePlatformBitness 64 \
  +force_install_dir ~/Games/1245620 \
  +login yourname \
  +app_update 1245620 validate \
  +quit
```

## Why not macOS Steam downloads?

The macOS Steam client generally only exposes macOS-compatible depots. Windows-only games often do not appear as installable through native macOS Steam.

Windows Steam running inside the Forge bottle requests and installs the Windows build directly, which is why it is the preferred path.

## Authentication

Forge should not store Steam passwords. If a third-party downloader prompts for Steam Guard or credentials, that authentication is handled by the tool itself.

## After manual downloads

If you manually download files with DepotDownloader or SteamCMD:

1. Put the files somewhere inside or accessible to the Wine bottle.
2. Drag the main `.exe` into Forge or use **Select EXE**.
3. Pick a graphics backend.
4. Launch and check logs if it fails.

Manual downloads may not behave like Steam-owned launches because Steamworks/DRM may expect Steam to be running.
