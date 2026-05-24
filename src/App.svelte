<!--
  App.svelte — Root component.

  Sidebar nav items:
    Library     — game grid + detail panel
    Download    — download Windows games via DepotDownloader / SteamCMD
    Settings    — launcher config (GPTK paths, prefix, theme)

  Modals (rendered at root so they sit above everything):
    SteamImport — scan local Steam library and import already-installed games
    Toast       — notification queue
-->

<script lang="ts">
  import { onMount, onDestroy } from "svelte";
  import { open as openDialog, } from "@tauri-apps/plugin-dialog";
  import { convertFileSrc }      from "@tauri-apps/api/core";

  import GameCard      from "./lib/components/GameCard.svelte";
  import GameDownload  from "./lib/components/GameDownload.svelte";
  import SteamImport   from "./lib/components/SteamImport.svelte";
  import Toast         from "./lib/components/Toast.svelte";

  import {
    games,
    selectedGameId,
    selectedGame,
    runningGameIds,
    liveStats,
    loadGames,
    startPolling,
    stopPolling,
    removeGame,
    upsertGame,
  } from "./lib/stores/games";

  import { invoke }              from "@tauri-apps/api/core";
  import { launchGame, killGame, notify } from "./lib/stores/launcher";
  import { loadConfig, appConfig, saveConfig } from "./lib/stores/config";
  import type { Game, SaveMapping, ProcessStats } from "./lib/types";

  // ── UI state ─────────────────────────────────────────────────────────────
  type View = "library" | "download" | "settings";
  let activeView: View = "library";
  let showSteamImport  = false;

  // ── Wine detection ────────────────────────────────────────────────────────
  let wineInstalled: boolean | null = null;  // null = checking
  let wineInstallCmd = "brew install --cask gcenx/wine/game-porting-toolkit";

  // ── Boot ─────────────────────────────────────────────────────────────────
  onMount(async () => {
    try {
      await Promise.all([loadConfig(), loadGames()]);
    } catch (err) {
      notify("error", `Failed to load library: ${err}`);
    }
    startPolling(3000);

    // Check if wine64 is installed
    try {
      const result = await invoke<{ installed: boolean; path: string | null }>("check_wine");
      wineInstalled = result.installed;
      // If wine was auto-detected, update config so the correct path is saved
      if (result.installed && result.path && $appConfig.wine64_path !== result.path) {
        await saveConfig({ ...$appConfig, wine64_path: result.path });
      }
    } catch {
      wineInstalled = false;
    }
  });

  onDestroy(() => stopPolling());

  // ── Settings save handler ─────────────────────────────────────────────────
  async function handleSaveConfig() {
    try {
      await saveConfig($appConfig);
      notify("success", "Settings saved");
    } catch (err) {
      notify("error", `Failed to save settings: ${err}`);
    }
  }

  // ── Detail panel helpers ──────────────────────────────────────────────────
  function formatPlaytime(secs: number): string {
    if (secs < 60) return "< 1 min";
    const h = Math.floor(secs / 3600);
    const m = Math.floor((secs % 3600) / 60);
    return h > 0 ? `${h}h ${m}m` : `${m}m`;
  }

  async function handleLaunch(id: string) {
    try { await launchGame(id); } catch { /* toast shown in store */ }
  }

  async function handleKill(id: string) {
    try { await killGame(id); } catch { /* toast shown in store */ }
  }

  // ── File / folder pickers ─────────────────────────────────────────────────

  /** Open a native file picker filtered to .exe files and save to game. */
  async function pickExe(game: Game) {
    const selected = await openDialog({
      title:       "Select the game executable (.exe)",
      multiple:    false,
      filters:     [{ name: "Windows Executable", extensions: ["exe"] }],
      defaultPath: game.working_dir ?? undefined,
    });

    if (!selected || typeof selected !== "string") return;

    await upsertGame({ ...game, exe_path: selected });
    notify("success", "Executable path saved");
  }

  // ── Save sync ───────────────────────────────────────────────────────────
  let saveSyncing = false;

  /** Manually sync saves in one direction. */
  async function handleSyncSaves(game: Game, direction: "to_prefix" | "from_prefix") {
    saveSyncing = true;
    try {
      const count = await invoke<number>("sync_game_saves", { gameId: game.id, direction });
      const label = direction === "to_prefix" ? "Loaded saves into Wine prefix" : "Saved progress back to macOS";
      notify(count > 0 ? "success" : "info", `${label}${count > 0 ? ` (${count} file${count === 1 ? "" : "s"})` : " — no files to sync"}`);
    } catch (err) {
      notify("error", `Save sync failed: ${err}`);
    } finally {
      saveSyncing = false;
    }
  }

  /** Add a new empty save mapping to a game. */
  async function addSaveMapping(game: Game) {
    const updated = {
      ...game,
      save_mappings: [...game.save_mappings, { source: "", target: "" }],
    };
    await upsertGame(updated);
  }

  /** Remove a save mapping by index. */
  async function removeSaveMapping(game: Game, idx: number) {
    const updated = {
      ...game,
      save_mappings: game.save_mappings.filter((_, i) => i !== idx),
    };
    await upsertGame(updated);
  }

  /** Update a save mapping field and persist. */
  async function updateSaveMapping(game: Game, idx: number, field: "source" | "target", value: string) {
    const newMappings = [...game.save_mappings];
    newMappings[idx] = { ...newMappings[idx], [field]: value };
    await upsertGame({ ...game, save_mappings: newMappings });
  }

  /** Open a folder picker for a save mapping field. */
  async function browseSavePath(game: Game, idx: number, field: "source" | "target") {
    const selected = await openDialog({
      title:     field === "source" ? "Select macOS save directory" : "Select Wine prefix save directory",
      multiple:  false,
      directory: true,
      defaultPath: field === "source" ? "~/Documents/" : game.wine_prefix ?? $appConfig.default_prefix,
    });

    if (!selected || typeof selected !== "string") return;
    await updateSaveMapping(game, idx, field, selected);
  }

  /** Toggle MangoHud on the game. */
  async function toggleMangoHud(game: Game) {
    await upsertGame({ ...game, mangohud_enabled: !game.mangohud_enabled });
  }

  /** Open Steam Cloud page for a game's AppID. */
  async function openSteamCloud(appId: number) {
    try {
      const url = await invoke<string>("steam_cloud_url", { appId });
      window.open(url, "_blank");
    } catch (err) {
      notify("error", `Could not open Steam Cloud: ${err}`);
    }
  }

  /** Open a native folder picker and save as the working directory. */
  async function pickWorkingDir(game: Game) {
    const selected = await openDialog({
      title:       "Select the game's working directory",
      multiple:    false,
      directory:   true,
      defaultPath: game.working_dir ?? undefined,
    });

    if (!selected || typeof selected !== "string") return;

    await upsertGame({ ...game, working_dir: selected });
    notify("success", "Working directory saved");
  }
</script>

<!-- ═══════════════════════════════════════════════════════════════════════ -->
<!-- Root shell                                                              -->
<!-- ═══════════════════════════════════════════════════════════════════════ -->
<div class="app" data-theme={$appConfig.theme}>

  <!-- macOS traffic-light drag region -->
  <header class="titlebar" data-tauri-drag-region>
    <span class="app-title">Forge Launcher</span>
  </header>

  <div class="shell">

    <!-- ── Sidebar ──────────────────────────────────────────────────────── -->
    <nav class="sidebar" aria-label="Main navigation">

      <div class="sidebar-section">
        <p class="sidebar-label">Library</p>

        <button
          class="nav-item"
          class:active={activeView === "library"}
          on:click={() => (activeView = "library")}
          aria-current={activeView === "library" ? "page" : undefined}
        >
          <span class="nav-icon">󰊴</span>
          Games
          {#if $games.length > 0}
            <span class="badge">{$games.length}</span>
          {/if}
        </button>
      </div>

      <div class="sidebar-section">
        <p class="sidebar-label">Steam</p>

        <!-- Download Windows game (DepotDownloader / SteamCMD) -->
        <button
          class="nav-item"
          class:active={activeView === "download"}
          on:click={() => (activeView = "download")}
          aria-current={activeView === "download" ? "page" : undefined}
        >
          <span class="nav-icon">↓</span>
          Download Game
        </button>

        <!-- Import already-installed Steam game -->
        <button
          class="nav-item"
          on:click={() => (showSteamImport = true)}
        >
          <span class="nav-icon">+</span>
          Import Installed
        </button>
      </div>

      <div class="sidebar-bottom">
        <button
          class="nav-item"
          class:active={activeView === "settings"}
          on:click={() => (activeView = "settings")}
          aria-current={activeView === "settings" ? "page" : undefined}
        >
          <span class="nav-icon">⚙</span>
          Settings
        </button>
      </div>

    </nav>

    <!-- ── Main content ─────────────────────────────────────────────────── -->
    <main class="content">

      <!-- ── Wine not installed banner ────────────────────────────────── -->
      {#if wineInstalled === false}
        <div class="wine-banner">
          <div class="wine-banner-body">
            <span class="wine-banner-icon">⚠</span>
            <div>
              <strong>Wine is not installed</strong>
              <p>You need Wine to run Windows games. Install it with:</p>
              <code>{wineInstallCmd}</code>
            </div>
          </div>
          <button
            class="wine-banner-copy"
            on:click={() => { navigator.clipboard.writeText(wineInstallCmd); notify("success", "Copied to clipboard"); }}
          >
            Copy
          </button>
          <button class="wine-banner-dismiss" on:click={() => (wineInstalled = null)}>✕</button>
        </div>
      {/if}

      <!-- ── Library view ─────────────────────────────────────────────── -->
      {#if activeView === "library"}
        <div class="library-layout">

          <!-- Game grid -->
          <section class="game-grid" aria-label="Game library">
            {#if $games.length === 0}
              <div class="empty-library">
                <div class="empty-icon">󰊴</div>
                <h3>Your library is empty</h3>
                <p>
                  <button class="link-btn" on:click={() => (activeView = "download")}>
                    Download a Windows game
                  </button>
                  {" "}or{" "}
                  <button class="link-btn" on:click={() => (showSteamImport = true)}>
                    import from Steam
                  </button>
                </p>
              </div>
            {:else}
              {#each $games as game (game.id)}
                <GameCard
                  {game}
                  active={$runningGameIds.has(game.id)}
                />
              {/each}
            {/if}
          </section>

          <!-- Detail panel — shown when a game is selected -->
          {#if $selectedGame}
            {@const g = $selectedGame}
            <aside class="detail-panel" aria-label="Game detail">

              <!-- Cover art -->
              <div class="detail-cover">
                {#if g.cover_art}
                  <img src={convertFileSrc(g.cover_art)} alt="{g.name} cover" />
                {:else}
                  <div class="detail-cover-placeholder">
                    {g.name[0]?.toUpperCase() ?? "?"}
                  </div>
                {/if}
              </div>

              <div class="detail-body">
                <h2 class="detail-title">{g.name}</h2>

                <!-- Metadata rows -->
                <div class="detail-meta-grid">
                  {#if g.steam_app_id}
                    <span class="meta-label">AppID</span>
                    <span class="meta-value">{g.steam_app_id}</span>
                  {/if}
                  <span class="meta-label">Playtime</span>
                  <span class="meta-value">{formatPlaytime(g.playtime_secs)}</span>
                  <span class="meta-label">Backend</span>
                  <span class="meta-value meta-badge">{g.translation_backend.toUpperCase()}</span>
                  <span class="meta-label">Source</span>
                  <span class="meta-value meta-badge meta-badge--{g.source}">
                    {g.source === "steam" ? "Steam" : "Manual"}
                  </span>
                </div>

                <!-- ── Executable path ──────────────────────────────────── -->
                <div class="path-section">
                  <div class="path-header">
                    <span class="path-label">Executable (.exe)</span>
                    <button class="path-browse" on:click={() => pickExe(g)}>
                      Browse…
                    </button>
                  </div>
                  {#if g.exe_path}
                    <p class="path-value" title={g.exe_path}>{g.exe_path}</p>
                  {:else}
                    <p class="path-missing">
                      Not set — click Browse to pick the .exe
                    </p>
                  {/if}
                </div>

                <!-- ── Working directory ────────────────────────────────── -->
                <div class="path-section">
                  <div class="path-header">
                    <span class="path-label">Working directory</span>
                    <button class="path-browse" on:click={() => pickWorkingDir(g)}>
                      Browse…
                    </button>
                  </div>
                  {#if g.working_dir}
                    <p class="path-value" title={g.working_dir}>{g.working_dir}</p>
                  {:else}
                    <p class="path-auto">Auto (exe folder)</p>
                  {/if}
                </div>

                <!-- ── Quick toggles ───────────────────────────────── -->
                <div class="detail-toggles">
                  <label class="toggle-row">
                    <span>Metal HUD</span>
                    <input
                      type="checkbox"
                      checked={g.show_hud}
                      on:change={() => upsertGame({ ...g, show_hud: !g.show_hud })}
                    />
                  </label>
                  <label class="toggle-row">
                    <span>ESYNC</span>
                    <input
                      type="checkbox"
                      checked={g.esync}
                      on:change={() => upsertGame({ ...g, esync: !g.esync })}
                    />
                  </label>
                  <label class="toggle-row">
                    <span>MangoHud</span>
                    <input
                      type="checkbox"
                      checked={g.mangohud_enabled}
                      on:change={() => toggleMangoHud(g)}
                      title="FPS, CPU, GPU, RAM overlay (requires DXVK + brew install mangohud)"
                    />
                  </label>
                </div>

                <!-- ── Save file sync ─────────────────────────────────── -->
                <div class="save-sync-section">
                  <div class="save-sync-header">
                    <span class="save-sync-title">Save File Sync</span>
                    <button
                      class="save-add-btn"
                      on:click={() => addSaveMapping(g)}
                      title="Add save path mapping"
                    >+ Add</button>
                  </div>

                  {#if g.save_mappings.length === 0}
                    <p class="save-hint">
                      No save mappings configured. Add one to automatically sync save files
                      between macOS and the Wine prefix before launch and after exit.
                    </p>
                  {:else}
                    {#each g.save_mappings as mapping, i (i)}
                      <div class="save-mapping-card">
                        <div class="save-mapping-row">
                          <span class="save-mapping-label">macOS</span>
                          <div class="save-path-input-wrap">
                            <input
                              type="text"
                              class="save-path-input"
                              placeholder="~/Documents/MyGame Saves/"
                              value={mapping.source}
                              on:change={(e) => updateSaveMapping(g, i, "source", e.currentTarget.value)}
                            />
                            <button
                              class="save-path-btn"
                              on:click={() => browseSavePath(g, i, "source")}
                              title="Browse…"
                            >…</button>
                          </div>
                        </div>
                        <div class="save-mapping-row">
                          <span class="save-mapping-label">Wine</span>
                          <div class="save-path-input-wrap">
                            <input
                              type="text"
                              class="save-path-input"
                              placeholder="~/Wine/Bottles/default/drive_c/users/.../Saves/"
                              value={mapping.target}
                              on:change={(e) => updateSaveMapping(g, i, "target", e.currentTarget.value)}
                            />
                            <button
                              class="save-path-btn"
                              on:click={() => browseSavePath(g, i, "target")}
                              title="Browse…"
                            >…</button>
                          </div>
                        </div>
                        <button
                          class="save-remove-btn"
                          on:click={() => removeSaveMapping(g, i)}
                          title="Remove this mapping"
                        >✕</button>
                      </div>
                    {/each}

                    <div class="save-sync-actions">
                      <button
                        class="btn btn--save-sync"
                        on:click={() => handleSyncSaves(g, "to_prefix")}
                        disabled={saveSyncing}
                        title="Copy saves from macOS into the Wine prefix"
                      >
                        {saveSyncing ? "Syncing…" : "→ Load saves into Wine"}
                      </button>
                      <button
                        class="btn btn--save-sync"
                        on:click={() => handleSyncSaves(g, "from_prefix")}
                        disabled={saveSyncing}
                        title="Copy saves from the Wine prefix back to macOS"
                      >
                        {saveSyncing ? "Syncing…" : "← Save progress to macOS"}
                      </button>
                    </div>
                  {/if}
                </div>

                <!-- ── Performance ──────────────────────────────────── -->
                {#if $runningGameIds.has(g.id)}
                  {@const stats = $liveStats.get(g.id)}
                  <div class="perf-section">
                    <div class="perf-header">
                      <span class="perf-title">Performance</span>
                      <span class="perf-live">● LIVE</span>
                    </div>
                    <div class="perf-grid">
                      <div class="perf-stat">
                        <span class="perf-value">{stats ? stats.elapsed_secs : g.playtime_secs}s</span>
                        <span class="perf-label">Runtime</span>
                      </div>
                      <div class="perf-stat">
                        <span class="perf-value">{stats ? stats.rss_mb.toFixed(0) : "?"} MB</span>
                        <span class="perf-label">RAM</span>
                      </div>
                      <div class="perf-stat">
                        <span class="perf-value">{stats ? stats.cpu_percent.toFixed(1) : "?"}%</span>
                        <span class="perf-label">CPU</span>
                      </div>
                      <div class="perf-stat">
                        <span class="perf-value">{stats ? stats.vsz_mb.toFixed(0) : "?"} MB</span>
                        <span class="perf-label">VM Size</span>
                      </div>
                    </div>
                    <p class="perf-hint">
                      FPS: shown in-game via Metal HUD (D3DMetal) or MangoHud (DXVK)
                    </p>
                  </div>
                {/if}

                <!-- ── Primary actions ──────────────────────────────────── -->
                <div class="detail-actions">
                  {#if $runningGameIds.has(g.id)}
                    <button class="btn btn--stop" on:click={() => handleKill(g.id)}>
                      Stop Game
                    </button>
                  {:else}
                    <button
                      class="btn btn--launch"
                      on:click={() => handleLaunch(g.id)}
                      disabled={!g.exe_path}
                      title={!g.exe_path ? "Browse to set the .exe path first" : ""}
                    >
                      {g.exe_path ? "Launch" : "Set exe to launch"}
                    </button>
                  {/if}

                  {#if g.source === "steam" && g.steam_app_id}
                    <button
                      class="btn btn--secondary"
                      on:click={() => { activeView = "download"; selectedGameId.set(null); }}
                    >
                      Re-download
                    </button>
                    <button
                      class="btn btn--secondary"
                      on:click={() => openSteamCloud(g.steam_app_id!)}
                      title="Open Steam Cloud page to download save files"
                    >
                      Steam Cloud Saves
                    </button>
                  {/if}

                  <button class="btn btn--danger" on:click={() => removeGame(g.id)}>
                    Remove from Library
                  </button>
                </div>

                {#if g.notes}
                  <p class="detail-notes">{g.notes}</p>
                {/if}
              </div>
            </aside>
          {/if}

        </div>

      <!-- ── Download view ─────────────────────────────────────────────── -->
      {:else if activeView === "download"}
        <div class="view-padded">
          <div class="view-header">
            <div>
              <h2>Download Windows Game</h2>
              <p class="view-subtitle">
                Download Windows-only Steam games using DepotDownloader or SteamCMD.
                The macOS Steam client cannot download these — this goes direct to Steam's servers.
              </p>
            </div>
          </div>

          <!-- Inline (not modal) download form -->
          <GameDownload onClose={() => (activeView = "library")} />
        </div>

      <!-- ── Settings view ─────────────────────────────────────────────── -->
      {:else if activeView === "settings"}
        <div class="view-padded">
          <div class="view-header">
            <div>
              <h2>Settings</h2>
              <p class="view-subtitle">Configure paths and global launch options.</p>
            </div>
            <button class="btn btn--launch btn--save" on:click={handleSaveConfig}>
              Save
            </button>
          </div>

          <div class="settings-form">

            <div class="settings-group">
              <h3 class="settings-group-title">GPTK / Wine</h3>

              <label class="setting-row">
                <span>wine64 path</span>
                <input type="text" bind:value={$appConfig.wine64_path}
                  placeholder="/usr/local/bin/wine64" />
              </label>

              <label class="setting-row">
                <span>GPTK lib path</span>
                <input type="text" bind:value={$appConfig.gptk_lib_path}
                  placeholder="/usr/local/lib/external" />
              </label>

              <label class="setting-row">
                <span>Default Wine prefix</span>
                <input type="text" bind:value={$appConfig.default_prefix} />
              </label>
            </div>

            <div class="settings-group">
              <h3 class="settings-group-title">Performance</h3>

              <label class="setting-row setting-row--toggle">
                <span>Suppress Wine debug output</span>
                <input type="checkbox" bind:checked={$appConfig.suppress_wine_debug} />
              </label>

              <label class="setting-row setting-row--toggle">
                <span>Global Metal HUD</span>
                <input type="checkbox" bind:checked={$appConfig.global_hud} />
              </label>

              <label class="setting-row setting-row--toggle">
                <span>MetalFX upscaling (GPTK 3.0+)</span>
                <input type="checkbox" bind:checked={$appConfig.metalfx_enabled} />
              </label>
            </div>

            <div class="settings-group">
              <h3 class="settings-group-title">Appearance</h3>

              <label class="setting-row">
                <span>Theme</span>
                <select bind:value={$appConfig.theme}>
                  <option value="system">System</option>
                  <option value="dark">Dark</option>
                  <option value="light">Light</option>
                </select>
              </label>
            </div>

          </div>
        </div>
      {/if}

    </main>
  </div>

  <!-- Modals -->
  {#if showSteamImport}
    <SteamImport onClose={() => (showSteamImport = false)} />
  {/if}

  <Toast />
</div>

<!-- ═══════════════════════════════════════════════════════════════════════ -->
<!-- Styles                                                                  -->
<!-- ═══════════════════════════════════════════════════════════════════════ -->
<style>
  /* ── Design tokens ───────────────────────────────────────────────────── */
  :global(*) { box-sizing: border-box; margin: 0; padding: 0; }

  :global(:root) {
    --color-bg:           #13131f;
    --color-surface:      #1e1e2e;
    --color-surface-2:    #2a2a3e;
    --color-border:       #333348;
    --color-text:         #e2e2f0;
    --color-muted:        #888899;
    --color-accent:       #7f5af0;
    --color-accent-hover: #9d7ef5;
    font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif;
    font-size:   15px;
    color:       var(--color-text);
  }

  :global([data-theme="light"]) {
    --color-bg:        #f4f4f8;
    --color-surface:   #ffffff;
    --color-surface-2: #eeeef5;
    --color-border:    #d0d0e0;
    --color-text:      #111122;
    --color-muted:     #666677;
  }

  :global(body) { background: var(--color-bg); overflow: hidden; height: 100vh; }

  /* ── App shell ───────────────────────────────────────────────────────── */
  .app { display: flex; flex-direction: column; height: 100vh; background: var(--color-bg); }

  .titlebar {
    height:        38px;
    display:       flex;
    align-items:   center;
    justify-content: center;
    padding-left:  80px; /* room for traffic-light buttons */
    background:    var(--color-surface);
    border-bottom: 1px solid var(--color-border);
    flex-shrink:   0;
    -webkit-app-region: drag;
  }

  .app-title { font-size: 0.78rem; font-weight: 600; color: var(--color-muted); letter-spacing: 0.05em; }

  .shell { display: flex; flex: 1; overflow: hidden; }

  /* ── Sidebar ─────────────────────────────────────────────────────────── */
  .sidebar {
    width:           200px;
    background:      var(--color-surface);
    border-right:    1px solid var(--color-border);
    display:         flex;
    flex-direction:  column;
    padding:         16px 0 12px;
    flex-shrink:     0;
    gap:             8px;
  }

  .sidebar-section {
    display:        flex;
    flex-direction: column;
    gap:            2px;
    padding:        0 10px;
  }

  .sidebar-bottom {
    margin-top: auto;
    padding:    0 10px;
  }

  .sidebar-label {
    font-size:      0.65rem;
    font-weight:    700;
    letter-spacing: 0.08em;
    text-transform: uppercase;
    color:          var(--color-muted);
    padding:        0 12px;
    margin-bottom:  4px;
  }

  .nav-item {
    display:         flex;
    align-items:     center;
    gap:             8px;
    background:      transparent;
    border:          none;
    color:           var(--color-muted);
    font-size:       0.85rem;
    font-weight:     500;
    padding:         7px 12px;
    border-radius:   8px;
    cursor:          pointer;
    text-align:      left;
    width:           100%;
    transition:      background 0.12s, color 0.12s;
  }

  .nav-item:hover  { background: rgba(255,255,255,0.06); color: var(--color-text); }
  .nav-item.active { background: rgba(127,90,240,0.15);  color: var(--color-accent); font-weight: 600; }

  .nav-icon { width: 16px; text-align: center; flex-shrink: 0; font-size: 0.9rem; }

  .badge {
    margin-left:   auto;
    background:    var(--color-surface-2);
    color:         var(--color-muted);
    font-size:     0.68rem;
    padding:       1px 7px;
    border-radius: 999px;
  }

  /* ── Content area ────────────────────────────────────────────────────── */
  .content { flex: 1; overflow: hidden; display: flex; flex-direction: column; }

  /* Padded wrapper for download + settings views */
  .view-padded {
    padding:    28px 32px;
    overflow-y: auto;
    height:     100%;
    display:    flex;
    flex-direction: column;
    gap:        20px;
  }

  .view-header {
    display:     flex;
    align-items: flex-start;
    justify-content: space-between;
    gap:         16px;
  }

  .view-header h2 { font-size: 1.1rem; font-weight: 700; margin-bottom: 4px; }

  .view-subtitle {
    font-size:   0.8rem;
    color:       var(--color-muted);
    max-width:   560px;
    line-height: 1.5;
  }

  /* ── Library layout ──────────────────────────────────────────────────── */
  .library-layout { display: flex; height: 100%; overflow: hidden; }

  .game-grid {
    flex:          1;
    display:       grid;
    grid-template-columns: repeat(auto-fill, minmax(148px, 1fr));
    gap:           16px;
    padding:       20px;
    overflow-y:    auto;
    align-content: start;
  }

  .empty-library {
    grid-column: 1 / -1;
    display:     flex;
    flex-direction: column;
    align-items: center;
    justify-content: center;
    height:      100%;
    gap:         12px;
    padding:     60px 20px;
    color:       var(--color-muted);
    text-align:  center;
  }

  .empty-icon  { font-size: 3rem; opacity: 0.3; }
  .empty-library h3 { font-size: 1rem; font-weight: 600; color: var(--color-text); }
  .empty-library p  { font-size: 0.85rem; line-height: 1.7; }

  .link-btn {
    background:  none;
    border:      none;
    color:       var(--color-accent);
    cursor:      pointer;
    font-size:   inherit;
    padding:     0;
    font-weight: 600;
    text-decoration: underline;
    text-underline-offset: 2px;
  }

  /* ── Detail panel ────────────────────────────────────────────────────── */
  .detail-panel {
    width:           280px;
    border-left:     1px solid var(--color-border);
    background:      var(--color-surface);
    overflow-y:      auto;
    flex-shrink:     0;
    display:         flex;
    flex-direction:  column;
  }

  .detail-cover {
    width:        100%;
    aspect-ratio: 2 / 3;
    overflow:     hidden;
    background:   var(--color-surface-2);
    flex-shrink:  0;
  }

  .detail-cover img { width: 100%; height: 100%; object-fit: cover; display: block; }

  .detail-cover-placeholder {
    width:           100%;
    height:          100%;
    display:         flex;
    align-items:     center;
    justify-content: center;
    font-size:       4rem;
    font-weight:     700;
    color:           var(--color-muted);
  }

  .detail-body  { padding: 16px; flex: 1; }
  .detail-title { font-size: 1rem; font-weight: 700; margin-bottom: 12px; }

  .detail-meta-grid {
    display:               grid;
    grid-template-columns: auto 1fr;
    gap:                   5px 10px;
    margin-bottom:         16px;
  }

  .meta-label { font-size: 0.72rem; color: var(--color-muted); align-self: center; }
  .meta-value { font-size: 0.78rem; font-weight: 500; }

  .meta-badge {
    display:       inline-flex;
    padding:       2px 8px;
    border-radius: 999px;
    font-size:     0.65rem;
    font-weight:   700;
    background:    var(--color-surface-2);
    width:         fit-content;
    text-transform: uppercase;
    letter-spacing: 0.04em;
  }

  .meta-badge--steam  { background: rgba(23,93,155,0.3);  color: #60a5fa; }
  .meta-badge--manual { background: var(--color-surface-2); color: var(--color-muted); }

  /* ── Path sections (exe + working dir) ──────────────────────────────── */
  .path-section {
    background:    var(--color-surface-2);
    border:        1px solid var(--color-border);
    border-radius: 8px;
    padding:       10px 12px;
    margin-bottom: 10px;
    display:       flex;
    flex-direction: column;
    gap:           5px;
  }

  .path-header {
    display:         flex;
    align-items:     center;
    justify-content: space-between;
  }

  .path-label {
    font-size:   0.72rem;
    font-weight: 600;
    color:       var(--color-muted);
    text-transform: uppercase;
    letter-spacing: 0.04em;
  }

  .path-browse {
    font-size:     0.72rem;
    font-weight:   600;
    color:         var(--color-accent);
    background:    transparent;
    border:        1px solid var(--color-accent);
    border-radius: 5px;
    padding:       2px 8px;
    cursor:        pointer;
    transition:    background 0.12s;
  }

  .path-browse:hover {
    background: rgba(127,90,240,0.12);
  }

  .path-value {
    font-size:     0.68rem;
    color:         var(--color-text);
    font-family:   monospace;
    overflow:      hidden;
    text-overflow: ellipsis;
    white-space:   nowrap;
    margin:        0;
  }

  .path-missing {
    font-size:  0.7rem;
    color:      #f59e0b;
    font-style: italic;
    margin:     0;
  }

  .path-auto {
    font-size:  0.7rem;
    color:      var(--color-muted);
    font-style: italic;
    margin:     0;
  }

  /* ── Quick toggles ─────────────────────────────────────────────── */
  .detail-toggles {
    display:        flex;
    flex-direction: column;
    gap:            6px;
    margin-bottom:  14px;
  }

  .toggle-row {
    display:     flex;
    align-items: center;
    gap:         8px;
    cursor:      pointer;
    font-size:   0.8rem;
    color:       var(--color-text);
  }

  .toggle-row span {
    flex: 1;
    font-size: 0.78rem;
    color: var(--color-muted);
  }

  .toggle-row input[type="checkbox"] {
    width:  16px;
    height: 16px;
    cursor: pointer;
  }

  /* ── Performance stats ──────────────────────────────────────────── */
  .perf-section {
    margin-bottom: 14px;
    background:    rgba(34,197,94,0.06);
    border:         1px solid rgba(34,197,94,0.2);
    border-radius:  8px;
    padding:        12px;
    display:        flex;
    flex-direction: column;
    gap:            10px;
  }

  .perf-header {
    display:         flex;
    align-items:     center;
    justify-content: space-between;
  }

  .perf-title {
    font-size:      0.72rem;
    font-weight:    700;
    text-transform: uppercase;
    letter-spacing: 0.05em;
    color:          var(--color-muted);
  }

  .perf-live {
    font-size:    0.6rem;
    font-weight:  700;
    color:        #22c55e;
    animation:    pulse 2s ease-in-out infinite;
  }

  .perf-grid {
    display:               grid;
    grid-template-columns: 1fr 1fr;
    gap:                   8px;
  }

  .perf-stat {
    background:    var(--color-surface-2);
    border-radius:  6px;
    padding:        8px;
    display:        flex;
    flex-direction: column;
    align-items:    center;
    gap:            2px;
  }

  .perf-value {
    font-size:   1.1rem;
    font-weight: 700;
    color:       var(--color-text);
    font-family: "SF Mono", Monaco, monospace;
  }

  .perf-label {
    font-size:   0.6rem;
    font-weight: 600;
    text-transform: uppercase;
    letter-spacing: 0.06em;
    color:       var(--color-muted);
  }

  .perf-hint {
    font-size:   0.62rem;
    color:       var(--color-muted);
    margin:      0;
    text-align:  center;
    line-height: 1.4;
  }

  /* ── Save file sync ─────────────────────────────────────────────── */
  .save-sync-section {
    margin-bottom: 16px;
    background:    var(--color-surface-2);
    border:         1px solid var(--color-border);
    border-radius:  8px;
    padding:        12px;
    display:        flex;
    flex-direction: column;
    gap:            10px;
  }

  .save-sync-header {
    display:         flex;
    align-items:     center;
    justify-content: space-between;
  }

  .save-sync-title {
    font-size:      0.72rem;
    font-weight:    700;
    color:          var(--color-muted);
    text-transform: uppercase;
    letter-spacing: 0.04em;
  }

  .save-add-btn {
    font-size:      0.72rem;
    font-weight:    600;
    color:          var(--color-accent);
    background:     transparent;
    border:         1px solid var(--color-accent);
    border-radius:  5px;
    padding:        3px 10px;
    cursor:         pointer;
    transition:     background 0.12s;
  }

  .save-add-btn:hover {
    background: rgba(127,90,240,0.12);
  }

  .save-hint {
    font-size:   0.72rem;
    color:       var(--color-muted);
    line-height: 1.5;
    margin:      0;
  }

  .save-mapping-card {
    background:    var(--color-surface);
    border:         1px solid var(--color-border);
    border-radius:  6px;
    padding:        10px;
    display:        flex;
    flex-direction:  column;
    gap:            6px;
    position:       relative;
  }

  .save-mapping-row {
    display:     flex;
    align-items: center;
    gap:         6px;
  }

  .save-mapping-label {
    font-size:       0.62rem;
    font-weight:     700;
    text-transform:  uppercase;
    letter-spacing:  0.05em;
    color:           var(--color-muted);
    min-width:       38px;
    flex-shrink:     0;
  }

  .save-path-input-wrap {
    flex:           1;
    display:        flex;
    gap:            4px;
  }

  .save-path-input {
    flex:          1;
    background:    var(--color-surface-2);
    border:        1px solid var(--color-border);
    border-radius: 4px;
    padding:       4px 7px;
    font-size:     0.65rem;
    font-family:   monospace;
    color:         var(--color-text);
    outline:       none;
    width:         100%;
  }

  .save-path-input:focus {
    border-color: var(--color-accent);
  }

  .save-path-btn {
    font-size:      0.72rem;
    font-weight:    600;
    color:          var(--color-accent);
    background:     transparent;
    border:         1px solid var(--color-accent);
    border-radius:  4px;
    padding:        3px 7px;
    cursor:         pointer;
    flex-shrink:    0;
    transition:     background 0.12s;
  }

  .save-path-btn:hover {
    background: rgba(127,90,240,0.12);
  }

  .save-remove-btn {
    position:        absolute;
    top:             6px;
    right:           6px;
    width:           18px;
    height:          18px;
    border-radius:   50%;
    border:          none;
    background:      rgba(220,38,38,0.7);
    color:           #fff;
    font-size:       0.55rem;
    font-weight:     700;
    cursor:          pointer;
    display:         flex;
    align-items:     center;
    justify-content: center;
    transition:      background 0.12s;
    line-height:     1;
  }

  .save-remove-btn:hover {
    background: #ef4444;
  }

  .save-sync-actions {
    display: flex;
    gap:     8px;
  }

  .btn--save-sync {
    flex:          1;
    padding:       6px 0;
    border:        none;
    border-radius: 6px;
    font-size:     0.7rem;
    font-weight:   600;
    cursor:        pointer;
    background:    var(--color-surface);
    color:         var(--color-text);
    border:        1px solid var(--color-border);
    transition:    background 0.12s, border-color 0.12s;
  }

  .btn--save-sync:hover:not(:disabled) {
    background:    var(--color-accent);
    color:         #fff;
    border-color:  var(--color-accent);
  }

  .btn--save-sync:disabled {
    opacity:    0.5;
    cursor:     not-allowed;
  }

  .detail-actions { display: flex; flex-direction: column; gap: 8px; margin-top: 4px; }

  .detail-exe {
    margin-top:    10px;
    font-size:     0.68rem;
    color:         var(--color-muted);
    overflow:      hidden;
    text-overflow: ellipsis;
    white-space:   nowrap;
    font-family:   monospace;
  }

  .detail-notes {
    margin-top:  12px;
    font-size:   0.78rem;
    color:       var(--color-muted);
    line-height: 1.5;
  }

  /* ── Settings ────────────────────────────────────────────────────────── */
  .settings-form { display: flex; flex-direction: column; gap: 28px; }

  .settings-group { display: flex; flex-direction: column; gap: 10px; }

  .settings-group-title {
    font-size:     0.7rem;
    font-weight:   700;
    letter-spacing: 0.07em;
    text-transform: uppercase;
    color:         var(--color-muted);
    padding-bottom: 6px;
    border-bottom: 1px solid var(--color-border);
  }

  .setting-row {
    display:     flex;
    align-items: center;
    gap:         14px;
    font-size:   0.85rem;
  }

  .setting-row span { min-width: 190px; color: var(--color-muted); font-size: 0.82rem; }

  .setting-row input[type="text"],
  .setting-row select {
    flex:          1;
    background:    var(--color-surface-2);
    border:        1px solid var(--color-border);
    border-radius: 7px;
    padding:       7px 10px;
    font-size:     0.82rem;
    color:         var(--color-text);
    outline:       none;
    transition:    border-color 0.15s;
  }

  .setting-row input[type="text"]:focus,
  .setting-row select:focus { border-color: var(--color-accent); }

  .setting-row--toggle { cursor: pointer; }
  .setting-row--toggle span { flex: 1; }
  .setting-row--toggle input { margin-left: auto; width: 18px; height: 18px; cursor: pointer; }

  /* ── Shared buttons ──────────────────────────────────────────────────── */
  .btn {
    padding:       9px 0;
    border:        none;
    border-radius: 8px;
    font-size:     0.85rem;
    font-weight:   600;
    cursor:        pointer;
    width:         100%;
    transition:    background 0.15s, opacity 0.15s;
  }

  .btn:disabled { opacity: 0.4; cursor: not-allowed; }

  .btn--launch    { background: var(--color-accent, #7f5af0); color: #fff; }
  .btn--launch:hover:not(:disabled) { background: var(--color-accent-hover, #9d7ef5); }
  .btn--secondary { background: var(--color-surface-2); color: var(--color-text); }
  .btn--secondary:hover { background: rgba(255,255,255,0.08); }
  .btn--stop      { background: #dc2626; color: #fff; }
  .btn--stop:hover { background: #ef4444; }
  .btn--danger    { background: transparent; color: #dc2626; border: 1px solid rgba(220,38,38,0.4); }
  .btn--danger:hover { background: rgba(220,38,38,0.08); }

  /* Save button in header — override width */
  .btn--save { width: auto; padding: 8px 22px; flex-shrink: 0; }

  /* ── Wine not installed banner ───────────────────────────────────────── */
  .wine-banner {
    display:         flex;
    align-items:     center;
    gap:             12px;
    padding:         12px 18px;
    background:      rgba(245,158,11,0.1);
    border-bottom:   1px solid rgba(245,158,11,0.25);
    flex-shrink:     0;
  }

  .wine-banner-body {
    display:     flex;
    align-items: flex-start;
    gap:         10px;
    flex:        1;
    min-width:   0;
  }

  .wine-banner-icon {
    font-size:  1.1rem;
    flex-shrink: 0;
    margin-top:  1px;
  }

  .wine-banner-body strong {
    display:     block;
    font-size:   0.83rem;
    color:       #f59e0b;
    margin-bottom: 3px;
  }

  .wine-banner-body p {
    font-size: 0.75rem;
    color:     var(--color-muted);
    margin:    0 0 4px;
  }

  .wine-banner-body code {
    font-size:     0.73rem;
    color:         #fbbf24;
    background:    rgba(245,158,11,0.12);
    padding:       2px 6px;
    border-radius: 4px;
    display:       block;
    word-break:    break-all;
  }

  .wine-banner-copy {
    padding:       5px 12px;
    background:    rgba(245,158,11,0.2);
    border:        1px solid rgba(245,158,11,0.4);
    border-radius: 6px;
    color:         #f59e0b;
    font-size:     0.75rem;
    font-weight:   600;
    cursor:        pointer;
    flex-shrink:   0;
    transition:    background 0.12s;
  }

  .wine-banner-copy:hover { background: rgba(245,158,11,0.3); }

  .wine-banner-dismiss {
    background:  transparent;
    border:      none;
    color:       var(--color-muted);
    font-size:   0.85rem;
    cursor:      pointer;
    padding:     4px;
    flex-shrink: 0;
  }

  .wine-banner-dismiss:hover { color: var(--color-text); }
</style>
