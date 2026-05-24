<!--
  GameDownload.svelte — Two-phase Steam download UI.

  Phase 1 (not authenticated):
    Shows a "Login with Steam" button that opens Terminal.app.
    User types their password + Steam Guard code there.
    Once done, they click "I've logged in" — we check for cached credentials.

  Phase 2 (authenticated):
    Shows the download form. Progress bar updates in real time.
    No terminal window needed — DepotDownloader runs silently.
-->

<script lang="ts">
  import { onMount, onDestroy } from "svelte";
  import { invoke }             from "@tauri-apps/api/core";
  import { listen }             from "@tauri-apps/api/event";
  import type { UnlistenFn }    from "@tauri-apps/api/event";
  import { upsertGame }         from "../stores/games";
  import { notify }             from "../stores/launcher";

  export let onClose: () => void = () => {};

  // ── Tool + auth state ────────────────────────────────────────────────────
  interface ToolStatus {
    depot_downloader_ok:           boolean;
    depot_downloader_path:         string | null;
    steamcmd_ok:                   boolean;
    steamcmd_path:                 string | null;
    steamcmd_unavailable_reason:   string | null;
  }
  let toolStatus: ToolStatus | null = null;
  let hasCredentials   = false;
  let checkingAuth     = false;
  let authOpened       = false; // true once Terminal was opened

  // ── Form state ────────────────────────────────────────────────────────────
  let appId      = "";
  let gameName   = "";
  let username   = "";
  let installDir = "~/Games/";
  let backend: "depot_downloader" | "steam_cmd" = "depot_downloader";

  // ── Download progress ─────────────────────────────────────────────────────
  interface DownloadProgress {
    app_id:    number;
    percent:   number;
    status:    string;
    completed: boolean;
    error:     string | null;
  }
  let downloading = false;
  let progress: DownloadProgress | null = null;
  let unlisten: UnlistenFn | null = null;

  // ── Lifecycle ──────────────────────────────────────────────────────────────
  onMount(async () => {
    toolStatus = await invoke<ToolStatus>("check_download_tools");
    if (toolStatus && !toolStatus.depot_downloader_ok && toolStatus.steamcmd_ok) {
      backend = "steam_cmd";
    }

    // Auto-detect cached username from account.config so the user doesn't have
    // to know the exact username string that was used during auth
    const cached = await invoke<string | null>("get_cached_steam_username");
    if (cached) {
      username = cached;
      hasCredentials = true;
    }

    unlisten = await listen<DownloadProgress>("download://progress", (event) => {
      progress = event.payload;
      if (progress.completed) {
        downloading = false;
        notify("success", `"${gameName || `AppID ${appId}`}" downloaded`);
        addToLibrary();
      }
      if (progress.error) {
        downloading = false;
        notify("error", `Download failed: ${progress.error}`);
      }
    });
  });

  onDestroy(() => unlisten?.());

  // ── Auth helpers ──────────────────────────────────────────────────────────

  async function openTerminalAuth() {
    // Username is optional for the terminal auth — DepotDownloader will prompt for it
    try {
      await invoke("authenticate_steam", { username: username.trim() });
      authOpened = true;
      notify("info", "Terminal opened — enter your password and Steam Guard code there");
    } catch (err) {
      notify("error", `Could not open Terminal: ${err}`);
    }
  }

  async function checkCredentials() {
    checkingAuth = true;
    try {
      // First try to read the stored username from account.config directly
      const cached = await invoke<string | null>("get_cached_steam_username");
      if (cached) {
        username = cached;
        hasCredentials = true;
        notify("success", `Logged in as ${cached} — ready to download`);
      } else {
        hasCredentials = false;
        notify("warning", "No cached credentials yet — complete the login in Terminal first");
      }
    } finally {
      checkingAuth = false;
    }
  }

  async function onUsernameChange() {
    if (username.trim().length > 2) {
      hasCredentials = await invoke<boolean>("check_steam_credentials", {
        username: username.trim()
      });
    } else {
      hasCredentials = false;
    }
  }

  // ── Download helpers ──────────────────────────────────────────────────────

  function onAppIdInput() {
    if (appId) installDir = `~/Games/${appId}`;
  }

  async function startDownload() {
    if (!appId || !username || !installDir) {
      notify("warning", "Fill in AppID, username, and install directory");
      return;
    }
    if (!hasCredentials) {
      notify("warning", "Log in with Steam first — click 'Login with Steam'");
      return;
    }
    downloading = true;
    progress = null;
    try {
      await invoke("download_steam_game", {
        request: {
          app_id:        parseInt(appId),
          username:      username.trim(),
          install_dir:   installDir,
          validate_only: false,
          backend,
        },
      });
    } catch (err) {
      downloading = false;
      notify("error", `Could not start download: ${err}`);
    }
  }

  async function cancelDownload() {
    try {
      await invoke("cancel_download", { appId: parseInt(appId) });
      downloading = false;
      progress = null;
    } catch (err) {
      notify("error", `Cancel failed: ${err}`);
    }
  }

  async function addToLibrary() {
    await upsertGame({
      id:                  crypto.randomUUID(),
      name:                gameName || `Steam Game ${appId}`,
      exe_path:            "",
      working_dir:         installDir,
      cover_art:           null,
      wine_prefix:         null,
      extra_args:          [],
      translation_backend: "d3dmetal",
      show_hud:            false,
      esync:               true,
      msync:               false,
      advertise_avx:       false,
      enable_dxr:          false,
      source:              "steam",
      steam_app_id:        parseInt(appId),
      notes:               `Downloaded via ${backend === "depot_downloader" ? "DepotDownloader" : "SteamCMD"}`,
      playtime_secs:       0,
      save_mappings:       [],
      mangohud_enabled:    false,
    });
    notify("info", "Added to library — set the .exe path in the game detail panel");
    onClose();
  }

  $: barWidth  = `${Math.min(progress?.percent ?? 0, 100)}%`;
  $: statusMsg = progress?.status ?? (downloading ? "Starting download…" : "");
  $: noTools   = toolStatus !== null && !toolStatus.depot_downloader_ok && !toolStatus.steamcmd_ok;
  $: canDownload = hasCredentials && !!appId && !!username && !noTools;
</script>

<div class="download-view">

  <!-- ── Tool status ──────────────────────────────────────────────────── -->
  {#if toolStatus}
    <div class="tool-cards">
      <div class="tool-card" class:ok={toolStatus.depot_downloader_ok}>
        <div class="tool-card-top">
          <span class="dot" class:green={toolStatus.depot_downloader_ok}></span>
          <strong>DepotDownloader</strong>
          <span class="tag">ARM64 · Recommended</span>
        </div>
        {#if toolStatus.depot_downloader_ok}
          <code class="tool-path">{toolStatus.depot_downloader_path}</code>
        {:else}
          <code class="install-cmd">brew tap steamre/tools && brew install depotdownloader</code>
        {/if}
      </div>

      <div class="tool-card" class:ok={toolStatus.steamcmd_ok}>
        <div class="tool-card-top">
          <span class="dot" class:green={toolStatus.steamcmd_ok}></span>
          <strong>SteamCMD</strong>
          <span class="tag">x86_64 via Rosetta</span>
        </div>
        {#if toolStatus.steamcmd_ok}
          <code class="tool-path">{toolStatus.steamcmd_path}</code>
        {:else}
          <code class="install-cmd">{toolStatus.steamcmd_unavailable_reason?.split('\n')[0]}</code>
        {/if}
      </div>
    </div>
  {/if}

  {#if noTools}
    <div class="alert alert--warn">
      No download tools installed. Install DepotDownloader first:
      <code>brew tap steamre/tools && brew install depotdownloader</code>
    </div>
  {/if}

  <!-- ── Step 1: Steam username + auth ────────────────────────────────── -->
  <div class="step-card">
    <div class="step-header">
      <span class="step-num">1</span>
      <div>
        <h3>Steam Account</h3>
        <p class="step-desc">Login once — credentials are cached for all future downloads</p>
      </div>
      {#if hasCredentials}
        <span class="auth-badge auth-badge--ok">Logged in</span>
      {:else if authOpened}
        <span class="auth-badge auth-badge--pending">Waiting…</span>
      {/if}
    </div>

    <label class="field">
      <span class="label">
        Steam username
        {#if hasCredentials && username}
          <span class="label-auto">(auto-detected from saved credentials)</span>
        {/if}
      </span>
      <input
        type="text"
        bind:value={username}
        on:input={onUsernameChange}
        placeholder="Your Steam login name (not email)"
        autocomplete="username"
        disabled={downloading || (hasCredentials && !!username)}
      />
    </label>

    {#if !hasCredentials}
      <div class="auth-actions">
        <button
          class="auth-btn auth-btn--primary"
          on:click={openTerminalAuth}
          disabled={!toolStatus?.depot_downloader_ok || downloading}
        >
          Login with Steam →
        </button>

        {#if authOpened}
          <button
            class="auth-btn auth-btn--secondary"
            on:click={checkCredentials}
            disabled={checkingAuth}
          >
            {checkingAuth ? "Checking…" : "I've logged in ✓"}
          </button>
        {/if}
      </div>

      <p class="auth-hint">
        Opens Terminal.app. Enter your Steam password and Steam Guard code there.
        This only happens once — all future downloads are silent.
      </p>
    {:else}
      <p class="auth-hint auth-hint--ok">
        Credentials cached at <code>~/.config/DepotDownloader/{username}.json</code>
      </p>
    {/if}
  </div>

  <!-- ── Step 2: Game details ──────────────────────────────────────────── -->
  <div class="step-card" class:step-card--disabled={!hasCredentials}>
    <div class="step-header">
      <span class="step-num">2</span>
      <div>
        <h3>Game</h3>
        <p class="step-desc">Find the AppID on <a href="https://steamdb.info" target="_blank" rel="noopener">steamdb.info</a></p>
      </div>
    </div>

    <div class="form-grid">
      <label class="field field--wide">
        <span class="label">Steam AppID</span>
        <input
          type="number"
          bind:value={appId}
          on:input={onAppIdInput}
          placeholder="e.g. 1245620 (Elden Ring)"
          disabled={!hasCredentials || downloading}
        />
      </label>

      <label class="field">
        <span class="label">Game name <span class="optional">(optional)</span></span>
        <input
          type="text"
          bind:value={gameName}
          placeholder="e.g. Elden Ring"
          disabled={!hasCredentials || downloading}
        />
      </label>

      <label class="field">
        <span class="label">Install directory</span>
        <input
          type="text"
          bind:value={installDir}
          placeholder="~/Games/1245620"
          disabled={!hasCredentials || downloading}
        />
      </label>

      <div class="field field--wide">
        <span class="label">Download tool</span>
        <div class="backend-row">
          <button
            class="backend-btn"
            class:selected={backend === "depot_downloader"}
            disabled={!toolStatus?.depot_downloader_ok || downloading || !hasCredentials}
            on:click={() => (backend = "depot_downloader")}
            type="button"
          >
            <strong>DepotDownloader</strong>
            <span>ARM64 native · Faster</span>
          </button>
          <button
            class="backend-btn"
            class:selected={backend === "steam_cmd"}
            disabled={!toolStatus?.steamcmd_ok || downloading || !hasCredentials}
            on:click={() => (backend = "steam_cmd")}
            type="button"
          >
            <strong>SteamCMD</strong>
            <span>x86_64 via Rosetta</span>
          </button>
        </div>
      </div>
    </div>
  </div>

  <!-- ── Progress ─────────────────────────────────────────────────────── -->
  {#if downloading || progress}
    <div class="progress-box">
      <div class="progress-track">
        <div class="progress-fill" style="width: {barWidth}"></div>
      </div>
      <div class="progress-row">
        <span class="progress-pct">{(progress?.percent ?? 0).toFixed(1)}%</span>
        <span class="progress-status">{statusMsg}</span>
      </div>
      {#if progress?.error}
        <p class="progress-error">{progress.error}</p>
      {/if}
    </div>
  {/if}

  <!-- ── Actions ──────────────────────────────────────────────────────── -->
  <div class="actions">
    {#if downloading}
      <button class="action-btn action-btn--stop" on:click={cancelDownload}>
        Cancel Download
      </button>
    {:else}
      <button
        class="action-btn action-btn--download"
        on:click={startDownload}
        disabled={!canDownload}
        title={!hasCredentials ? "Log in with Steam first" : !appId ? "Enter a Steam AppID" : ""}
      >
        {!hasCredentials ? "Log in first →" : "Download Game"}
      </button>
    {/if}
  </div>

</div>

<style>
  .download-view {
    display:        flex;
    flex-direction: column;
    gap:            20px;
    max-width:      640px;
  }

  /* ── Tool cards ──────────────────────────────────────────────────────── */
  .tool-cards {
    display:               grid;
    grid-template-columns: 1fr 1fr;
    gap:                   10px;
  }

  .tool-card {
    padding:        10px 14px;
    border-radius:  10px;
    border:         1.5px solid var(--color-border, #333348);
    background:     var(--color-surface-2, #2a2a3e);
    display:        flex;
    flex-direction: column;
    gap:            4px;
    opacity:        0.55;
    transition:     opacity 0.15s, border-color 0.15s;
  }

  .tool-card.ok { opacity: 1; border-color: rgba(34,197,94,0.3); }

  .tool-card-top {
    display:     flex;
    align-items: center;
    gap:         7px;
  }

  .tool-card-top strong { font-size: 0.82rem; color: var(--color-text, #e2e2f0); }

  .tag {
    margin-left:   auto;
    font-size:     0.62rem;
    color:         var(--color-muted, #888899);
    background:    rgba(255,255,255,0.05);
    padding:       1px 6px;
    border-radius: 4px;
  }

  .dot {
    width:         7px;
    height:        7px;
    border-radius: 50%;
    background:    #555;
    flex-shrink:   0;
  }

  .dot.green { background: #22c55e; }

  .tool-path   { font-size: 0.67rem; color: var(--color-muted, #888899); word-break: break-all; }
  .install-cmd { font-size: 0.67rem; color: var(--color-accent, #7f5af0); word-break: break-all; }

  /* ── Alert ───────────────────────────────────────────────────────────── */
  .alert {
    padding:       10px 14px;
    border-radius: 8px;
    font-size:     0.8rem;
    line-height:   1.5;
  }

  .alert--warn {
    background: rgba(245,158,11,0.1);
    border:     1px solid rgba(245,158,11,0.3);
    color:      #f59e0b;
  }

  .alert code { font-size: 0.72rem; }

  /* ── Step cards ──────────────────────────────────────────────────────── */
  .step-card {
    background:     var(--color-surface, #1e1e2e);
    border:         1px solid var(--color-border, #333348);
    border-radius:  12px;
    padding:        18px 20px;
    display:        flex;
    flex-direction: column;
    gap:            14px;
    transition:     opacity 0.2s;
  }

  .step-card--disabled { opacity: 0.45; pointer-events: none; }

  .step-header {
    display:     flex;
    align-items: flex-start;
    gap:         12px;
  }

  .step-num {
    width:           26px;
    height:          26px;
    border-radius:   50%;
    background:      var(--color-accent, #7f5af0);
    color:           #fff;
    font-size:       0.78rem;
    font-weight:     700;
    display:         flex;
    align-items:     center;
    justify-content: center;
    flex-shrink:     0;
    margin-top:      1px;
  }

  .step-header h3    { font-size: 0.9rem; font-weight: 700; margin-bottom: 2px; }
  .step-desc         { font-size: 0.75rem; color: var(--color-muted, #888899); margin: 0; }
  .step-desc a       { color: var(--color-accent, #7f5af0); }

  /* Auth badge */
  .auth-badge {
    margin-left:   auto;
    padding:       3px 10px;
    border-radius: 999px;
    font-size:     0.72rem;
    font-weight:   600;
    flex-shrink:   0;
  }

  .auth-badge--ok      { background: rgba(34,197,94,0.15); color: #22c55e; border: 1px solid rgba(34,197,94,0.3); }
  .auth-badge--pending { background: rgba(245,158,11,0.15); color: #f59e0b; border: 1px solid rgba(245,158,11,0.3); }

  /* Auth actions */
  .auth-actions {
    display: flex;
    gap:     10px;
  }

  .auth-btn {
    padding:       9px 18px;
    border:        none;
    border-radius: 8px;
    font-size:     0.83rem;
    font-weight:   600;
    cursor:        pointer;
    transition:    background 0.15s, opacity 0.15s;
  }

  .auth-btn:disabled { opacity: 0.4; cursor: not-allowed; }

  .auth-btn--primary  { background: var(--color-accent, #7f5af0); color: #fff; }
  .auth-btn--primary:hover:not(:disabled) { background: var(--color-accent-hover, #9d7ef5); }
  .auth-btn--secondary { background: rgba(34,197,94,0.15); color: #22c55e; border: 1px solid rgba(34,197,94,0.3); }
  .auth-btn--secondary:hover:not(:disabled) { background: rgba(34,197,94,0.25); }

  .auth-hint {
    margin:      0;
    font-size:   0.72rem;
    color:       var(--color-muted, #888899);
    line-height: 1.55;
  }

  .auth-hint--ok { color: #22c55e; }
  .auth-hint code { font-size: 0.68rem; opacity: 0.8; }

  /* ── Form ────────────────────────────────────────────────────────────── */
  .form-grid {
    display:               grid;
    grid-template-columns: 1fr 1fr;
    gap:                   14px;
  }

  .field {
    display:        flex;
    flex-direction: column;
    gap:            5px;
  }

  .field--wide { grid-column: 1 / -1; }

  .label {
    font-size:   0.78rem;
    font-weight: 600;
    color:       var(--color-text, #e2e2f0);
    display:     flex;
    align-items: center;
    gap:         6px;
    flex-wrap:   wrap;
  }

  .label-auto {
    font-weight: 400;
    font-size:   0.68rem;
    color:       #22c55e;
  }

  .optional { font-weight: 400; color: var(--color-muted, #888899); }

  .field input {
    background:    var(--color-surface-2, #2a2a3e);
    border:        1px solid var(--color-border, #333348);
    border-radius: 8px;
    padding:       8px 11px;
    font-size:     0.83rem;
    color:         var(--color-text, #e2e2f0);
    outline:       none;
    transition:    border-color 0.15s;
    width:         100%;
  }

  .field input:focus   { border-color: var(--color-accent, #7f5af0); }
  .field input:disabled { opacity: 0.4; cursor: not-allowed; }

  /* ── Backend selector ────────────────────────────────────────────────── */
  .backend-row { display: flex; gap: 10px; }

  .backend-btn {
    flex:           1;
    display:        flex;
    flex-direction: column;
    align-items:    flex-start;
    gap:            2px;
    padding:        9px 12px;
    background:     var(--color-surface-2, #2a2a3e);
    border:         1.5px solid var(--color-border, #333348);
    border-radius:  9px;
    cursor:         pointer;
    text-align:     left;
    transition:     border-color 0.12s, background 0.12s;
  }

  .backend-btn strong { font-size: 0.82rem; color: var(--color-text, #e2e2f0); }
  .backend-btn span   { font-size: 0.68rem; color: var(--color-muted, #888899); }
  .backend-btn.selected { border-color: var(--color-accent, #7f5af0); background: rgba(127,90,240,0.1); }
  .backend-btn:disabled { opacity: 0.35; cursor: not-allowed; }

  /* ── Progress ────────────────────────────────────────────────────────── */
  .progress-box {
    padding:        14px 16px;
    background:     var(--color-surface, #1e1e2e);
    border:         1px solid var(--color-border, #333348);
    border-radius:  10px;
    display:        flex;
    flex-direction: column;
    gap:            8px;
  }

  .progress-track {
    height:        8px;
    border-radius: 999px;
    background:    rgba(255,255,255,0.07);
    overflow:      hidden;
  }

  .progress-fill {
    height:        100%;
    border-radius: 999px;
    background:    var(--color-accent, #7f5af0);
    transition:    width 0.3s ease;
  }

  .progress-row {
    display:         flex;
    justify-content: space-between;
    align-items:     center;
  }

  .progress-pct    { font-size: 0.82rem; font-weight: 700; color: var(--color-accent, #7f5af0); }
  .progress-status { font-size: 0.72rem; color: var(--color-muted, #888899); max-width: 75%; overflow: hidden; text-overflow: ellipsis; white-space: nowrap; }
  .progress-error  { font-size: 0.75rem; color: #ef4444; }

  /* ── Actions ─────────────────────────────────────────────────────────── */
  .actions { display: flex; gap: 10px; }

  .action-btn {
    padding:       10px 26px;
    border:        none;
    border-radius: 8px;
    font-size:     0.86rem;
    font-weight:   600;
    cursor:        pointer;
    transition:    background 0.15s, opacity 0.15s;
  }

  .action-btn:disabled { opacity: 0.4; cursor: not-allowed; }

  .action-btn--download { background: var(--color-accent, #7f5af0); color: #fff; }
  .action-btn--download:hover:not(:disabled) { background: var(--color-accent-hover, #9d7ef5); }
  .action-btn--stop  { background: #dc2626; color: #fff; }
  .action-btn--stop:hover { background: #ef4444; }
</style>
