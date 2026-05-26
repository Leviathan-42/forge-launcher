# Forge Launcher Design

Forge is a Wine bottle manager for Windows launchers and apps on macOS.

It should feel closer to CrossOver or Whisky than a traditional game library.
The core object is the bottle, not the game.

## Product Model

Forge manages Wine prefixes called bottles.

Inside each bottle, the user can install and run Windows launchers:

- Steam
- Epic Games Launcher
- Battle.net
- EA App
- Ubisoft Connect
- Rockstar Launcher
- standalone `.exe` apps

Games are still supported, but they are not the center of the product. A game is
usually launched by a launcher inside the bottle.

Example:

```text
Forge
  -> Bottle: Default
    -> Windows Steam
      -> ULTRAKILL
```

The important part is that Steam owns the session. When Steam launches the game,
the game sees the real Steam account, Steam username, Steam Cloud, and Steamworks
APIs.

## Why This Direction

The old flow was:

```text
download game files -> add exe path -> run exe directly
```

That works for some games.

It fails for games that expect Steam, Epic, Battle.net, or another launcher to be
running.

The new flow is:

```text
create bottle -> install launcher -> sign in once -> launch from that launcher
```

This is more plug-and-play.

## Main UI

The app should have three main areas:

1. Bottle sidebar
2. Runtime/launcher controls
3. Apps inside the selected bottle

The first screen should be usable. It should not be a marketing page.

## Bottle Sidebar

The sidebar lists Wine bottles.

Each bottle shows:

- bottle name
- prefix path
- selected state

Actions:

- create bottle
- select bottle

Future actions:

- duplicate bottle
- delete bottle
- open bottle folder
- repair bottle

## Runtime Panel

The runtime panel is for launchers.

Steam should be first-class:

- Install Steam
- Open Steam
- Repair Steam
- Show whether Steam is installed in the selected bottle

Other launchers can start as generic `.exe` entries:

- Epic Games Launcher
- Battle.net
- EA App
- Ubisoft Connect
- Rockstar Launcher

Future versions can add one-click installers for these.

## Apps Panel

The apps panel shows Windows apps that are known inside the selected bottle.

These can be:

- a launcher
- a game executable
- a setup executable
- a tool

For Steam games, the preferred action is not direct launch. The preferred action
is:

```text
steam.exe -applaunch <appid>
```

Direct launch should remain available as a fallback.

## Settings

Settings should be quiet and practical.

Keep:

- Wine binary path
- GPTK library path
- default bottle path
- global HUD options
- MetalFX option

Settings should not dominate the main workflow.

## Save Files

Save sync is still useful.

It should move from being a central game feature to being an app/bottle utility.

Future model:

```text
Bottle
  -> App
    -> Save mappings
```

Steam Cloud should usually be handled by Windows Steam when possible.

The browser-cookie Steam Cloud downloader can stay as a fallback tool.

## Downloading

DepotDownloader and SteamCMD are useful, but they should not define the app.

They are advanced tools for:

- pre-downloading Steam depots
- repairing files
- avoiding Steam download issues

Normal users should be guided toward:

```text
Install Windows Steam -> sign in -> install/play games through Steam
```

## UX Rules

- Use short labels.
- Prefer buttons that do the obvious thing.
- Avoid asking the user to understand Wine internals.
- Make Steam-in-bottle the default for Steam games.
- Keep direct `.exe` launch as an escape hatch.
- Treat each bottle like a small Windows environment.

## Current Implementation Direction

The frontend is being remade around bottles.

The Rust backend still has older game-library commands. Keep them for now.

New commands should be prefix-first where possible:

- setup Windows Steam for a prefix
- open Windows Steam for a prefix
- run any `.exe` in a prefix
- check launcher status for a prefix

The older game commands can later be renamed or wrapped as app commands.
