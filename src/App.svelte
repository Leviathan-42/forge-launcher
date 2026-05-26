<script lang="ts">
  import { onMount } from "svelte";
  import Icon from "$lib/components/Icon.svelte";
  import {
    checkWine,
    createBottle as createBottleCommand,
    installSteam,
    launcherStatus,
    listBottleApps,
    listBottles,
    loadConfig,
    loadGames,
    openSteam,
    pickExe,
    pickFolder,
    repairSteam,
    runExe,
    saveConfig,
  } from "$lib/tauri";
  import type { AppConfig, Bottle, BottleApp, Game, LauncherStatus, WineStatus } from "$lib/types";

  type Toast = {
    id: number;
    tone: "ok" | "bad" | "info";
    text: string;
  };

  const launcherRows = [
    "Epic Games Launcher",
    "Battle.net",
    "EA App",
    "Ubisoft Connect",
    "Rockstar Launcher",
  ];

  let bottles: Bottle[] = [];
  let selectedBottleId = "";
  let apps: BottleApp[] = [];
  let games: Game[] = [];
  let config: AppConfig | null = null;
  let wine: WineStatus | null = null;
  let status: LauncherStatus | null = null;
  let selectedBottle: Bottle | undefined;
  let selectedGames: Game[] = [];
  let loading = true;
  let appLoading = false;
  let busy = "";
  let appFilter = "";
  let createName = "";
  let createPrefix = "";
  let exePath = "";
  let exeArgs = "";
  let settingsOpen = false;
  let toasts: Toast[] = [];
  let toastId = 1;

  $: selectedBottle = bottles.find((bottle) => bottle.id === selectedBottleId) || bottles[0];
  $: selectedGames =
    selectedBottle && config
      ? games.filter((game) => samePath(game.wine_prefix || config?.default_prefix, selectedBottle?.prefix_path))
      : [];
  $: filteredApps = apps.filter((app) => {
    const needle = appFilter.trim().toLowerCase();
    if (!needle) return true;
    return `${app.name} ${app.kind} ${app.path}`.toLowerCase().includes(needle);
  });

  onMount(() => {
    void refreshAll();
  });

  async function refreshAll() {
    loading = true;
    try {
      const [nextConfig, nextWine, nextBottles, nextGames] = await Promise.all([
        loadConfig(),
        checkWine(),
        listBottles(),
        loadGames(),
      ]);

      config = nextConfig;
      wine = nextWine;
      games = nextGames;
      bottles = nextBottles;

      if (!selectedBottleId || !bottles.some((bottle) => bottle.id === selectedBottleId)) {
        selectedBottleId = bottles[0]?.id || "";
      }

      await refreshSelectedBottle();
    } catch (error) {
      notify("bad", errorMessage(error));
    } finally {
      loading = false;
    }
  }

  async function refreshSelectedBottle() {
    const bottle = currentBottle();
    if (!bottle) return;

    appLoading = true;
    try {
      const [nextStatus, nextApps, nextBottles, nextGames] = await Promise.all([
        launcherStatus(bottle.prefix_path),
        listBottleApps(bottle.prefix_path),
        listBottles(),
        loadGames(),
      ]);

      status = nextStatus;
      apps = nextApps;
      bottles = nextBottles;
      games = nextGames;
    } catch (error) {
      notify("bad", errorMessage(error));
    } finally {
      appLoading = false;
    }
  }

  async function selectBottle(id: string) {
    selectedBottleId = id;
    await refreshSelectedBottle();
  }

  async function submitCreate() {
    if (!createName.trim() && !createPrefix.trim()) {
      createName = "Default";
    }

    await withBusy("create-bottle", async () => {
      bottles = await createBottleCommand(createName.trim() || "New Bottle", createPrefix.trim() || undefined);
      selectedBottleId = bottles[bottles.length - 1]?.id || selectedBottleId;
      createName = "";
      createPrefix = "";
      notify("ok", "Bottle ready.");
      await refreshSelectedBottle();
    });
  }

  async function chooseCreatePrefix() {
    const picked = await pickFolder();
    if (picked) createPrefix = picked;
  }

  async function chooseExe() {
    const picked = await pickExe();
    if (picked) exePath = picked;
  }

  async function chooseLauncherExe(name: string) {
    const picked = await pickExe();
    const bottle = currentBottle();
    if (!picked || !bottle) return;

    await withBusy(`launcher-${name}`, async () => {
      await runExe(bottle.prefix_path, picked);
      notify("ok", `${name} started.`);
      await refreshSelectedBottle();
    });
  }

  async function runCustomExe() {
    const bottle = currentBottle();
    if (!bottle || !exePath.trim()) return;
    const args = parseArgs(exeArgs);

    await withBusy("custom-exe", async () => {
      await runExe(bottle.prefix_path, exePath.trim(), args);
      notify("ok", "App started.");
      await refreshSelectedBottle();
    });
  }

  async function runBottleApp(app: BottleApp) {
    const bottle = currentBottle();
    if (!bottle) return;

    await withBusy(`app-${app.id}`, async () => {
      await runExe(bottle.prefix_path, app.path);
      notify("ok", `${app.name} started.`);
    });
  }

  async function runRegisteredGame(game: Game, mode: "steam" | "direct") {
    const bottle = currentBottle();
    if (!bottle || !config) return;

    await withBusy(`${mode}-${game.id}`, async () => {
      if (mode === "steam" && game.steam_app_id && status?.steam_path) {
        await runExe(bottle.prefix_path, status.steam_path, ["-applaunch", String(game.steam_app_id)]);
      } else {
        await runExe(bottle.prefix_path, game.exe_path);
      }
      notify("ok", `${game.name} started.`);
    });
  }

  async function installWindowsSteam() {
    const bottle = currentBottle();
    if (!bottle) return;

    await withBusy("install-steam", async () => {
      await installSteam(bottle.prefix_path);
      notify("ok", "Steam installer started.");
      await refreshSelectedBottle();
    });
  }

  async function openWindowsSteam() {
    const bottle = currentBottle();
    if (!bottle) return;

    await withBusy("open-steam", async () => {
      await openSteam(bottle.prefix_path);
      notify("ok", "Steam started.");
      await refreshSelectedBottle();
    });
  }

  async function repairWindowsSteam() {
    const bottle = currentBottle();
    if (!bottle) return;

    await withBusy("repair-steam", async () => {
      await repairSteam(bottle.prefix_path);
      notify("ok", "Steam repair started.");
      await refreshSelectedBottle();
    });
  }

  async function persistSettings() {
    if (!config) return;

    await withBusy("save-settings", async () => {
      await saveConfig(config as AppConfig);
      notify("ok", "Settings saved.");
      await refreshAll();
    });
  }

  async function withBusy(name: string, action: () => Promise<void>) {
    busy = name;
    try {
      await action();
    } catch (error) {
      notify("bad", errorMessage(error));
    } finally {
      busy = "";
    }
  }

  function notify(tone: Toast["tone"], text: string) {
    const id = toastId++;
    toasts = [...toasts, { id, tone, text }];
    window.setTimeout(() => {
      toasts = toasts.filter((toast) => toast.id !== id);
    }, 4200);
  }

  function dismissToast(id: number) {
    toasts = toasts.filter((toast) => toast.id !== id);
  }

  function parseArgs(raw: string) {
    const matches = raw.match(/"[^"]+"|\S+/g) || [];
    return matches.map((arg) => arg.replace(/^"|"$/g, ""));
  }

  function currentBottle() {
    return bottles.find((bottle) => bottle.id === selectedBottleId) || bottles[0];
  }

  function errorMessage(error: unknown) {
    if (typeof error === "string") return error;
    if (error instanceof Error) return error.message;
    return "Something went wrong.";
  }

  function shortPath(path?: string | null) {
    if (!path) return "Not set";
    return path.replace(/^\/Users\/[^/]+/, "~");
  }

  function samePath(a?: string | null, b?: string | null) {
    if (!a || !b) return false;
    return a.replace(/\/+$/, "") === b.replace(/\/+$/, "");
  }

  function statusText() {
    if (!status) return "Checking";
    if (!status.prefix_exists) return "Missing";
    if (!status.steam_installed) return "Steam off";
    return "Steam ready";
  }
</script>

<svelte:head>
  <title>Forge Launcher</title>
</svelte:head>

<div class="app-shell">
  <aside class="sidebar" aria-label="Bottles">
    <div class="brand-row">
      <div class="brand-mark">
        <Icon name="bottleWine" size={20} />
      </div>
      <div class="brand-copy">
        <strong>Forge</strong>
        <span>Bottles</span>
      </div>
      <button class="icon-button" title="Settings" aria-label="Settings" on:click={() => (settingsOpen = true)}>
        <Icon name="settings" size={17} />
      </button>
    </div>

    <div class="tool-row">
      <button class="secondary-button" on:click={refreshAll} disabled={loading || busy !== ""}>
        <span class:spin={loading}>
          <Icon name="refreshCw" size={15} />
        </span>
        Refresh
      </button>
    </div>

    <div class="bottle-list">
      {#if bottles.length === 0 && !loading}
        <div class="empty-state compact">No bottles</div>
      {/if}

      {#each bottles as bottle (bottle.id)}
        <button
          class="bottle-item"
          class:active={selectedBottle?.id === bottle.id}
          aria-pressed={selectedBottle?.id === bottle.id}
          on:click={() => selectBottle(bottle.id)}
        >
          <Icon name="bottleWine" size={18} />
          <span class="bottle-text">
            <strong>{bottle.name}</strong>
            <small>{shortPath(bottle.prefix_path)}</small>
          </span>
          <span class="dot" class:ok={bottle.exists && bottle.steam_installed} class:warn={bottle.exists && !bottle.steam_installed}></span>
        </button>
      {/each}
    </div>

    <form class="create-box" on:submit|preventDefault={submitCreate}>
      <label>
        <span>Name</span>
        <input bind:value={createName} placeholder="Default" />
      </label>
      <label>
        <span>Path</span>
        <div class="input-button">
          <input bind:value={createPrefix} placeholder="Auto" />
          <button type="button" class="icon-button" title="Choose folder" aria-label="Choose folder" on:click={chooseCreatePrefix}>
            <Icon name="folderPlus" size={16} />
          </button>
        </div>
      </label>
      <button class="primary-button" type="submit" disabled={busy !== ""}>
        <Icon name="plus" size={15} />
        Create
      </button>
    </form>
  </aside>

  <main class="main-surface">
    <header class="topbar">
      <div class="title-block">
        <span class="eyebrow">Selected Bottle</span>
        <h1>{selectedBottle?.name || "Bottle"}</h1>
        <p>{shortPath(selectedBottle?.prefix_path)}</p>
      </div>
      <div class="topbar-actions">
        <span class="system-pill" class:ok={wine?.installed} class:bad={!wine?.installed}>
          {#if wine?.installed}
            <Icon name="circleCheck" size={15} />
          {:else}
            <Icon name="circleAlert" size={15} />
          {/if}
          Wine
        </span>
        <span class="system-pill" class:ok={status?.steam_installed} class:bad={status && !status.steam_installed}>
          <Icon name="disc3" size={15} />
          {statusText()}
        </span>
      </div>
    </header>

    <div class="content-grid">
      <section class="panel runtime-panel" aria-label="Runtime controls">
        <div class="panel-heading">
          <div>
            <span class="eyebrow">Runtime</span>
            <h2>Windows Steam</h2>
          </div>
          <span class="status-label" class:ok={status?.steam_installed}>
            {status?.steam_installed ? "Installed" : "Not installed"}
          </span>
        </div>

        <div class="steam-actions">
          <button class="primary-button" on:click={installWindowsSteam} disabled={!selectedBottle || busy !== ""}>
            <Icon name="download" size={16} />
            Install Steam
          </button>
          <button class="secondary-button" on:click={openWindowsSteam} disabled={!status?.steam_installed || busy !== ""}>
            <Icon name="play" size={16} />
            Open Steam
          </button>
          <button class="icon-button strong" title="Repair Steam" aria-label="Repair Steam" on:click={repairWindowsSteam} disabled={!status?.steam_installed || busy !== ""}>
            <Icon name="wrench" size={17} />
          </button>
        </div>

        <div class="runtime-meta">
          <div>
            <span>Prefix</span>
            <strong>{status?.prefix_exists ? "Ready" : "Missing"}</strong>
          </div>
          <div>
            <span>Steam</span>
            <strong>{status?.steam_path ? shortPath(status.steam_path) : "None"}</strong>
          </div>
        </div>

        <div class="launcher-list" aria-label="Other launchers">
          {#each launcherRows as launcher}
            <div class="launcher-row">
              <div class="launcher-name">
                <Icon name="appWindow" size={16} />
                <span>{launcher}</span>
              </div>
              <button class="ghost-button" on:click={() => chooseLauncherExe(launcher)} disabled={!selectedBottle || busy !== ""}>
                <Icon name="filePlus" size={15} />
                Run .exe
              </button>
            </div>
          {/each}
        </div>

        <div class="custom-runner">
          <div class="section-title">
            <Icon name="slidersHorizontal" size={16} />
            <span>Standalone .exe</span>
          </div>
          <div class="input-button">
            <input bind:value={exePath} placeholder="Executable path" />
            <button class="icon-button" type="button" title="Choose executable" aria-label="Choose executable" on:click={chooseExe}>
              <Icon name="folderOpen" size={16} />
            </button>
          </div>
          <input bind:value={exeArgs} placeholder="Arguments" />
          <button class="secondary-button" on:click={runCustomExe} disabled={!selectedBottle || !exePath.trim() || busy !== ""}>
            <Icon name="play" size={15} />
            Run
          </button>
        </div>
      </section>

      <section class="panel apps-panel" aria-label="Apps">
        <div class="panel-heading">
          <div>
            <span class="eyebrow">Bottle Apps</span>
            <h2>Apps</h2>
          </div>
          <button class="icon-button" title="Refresh apps" aria-label="Refresh apps" on:click={refreshSelectedBottle} disabled={appLoading || busy !== ""}>
            <span class:spin={appLoading}>
              <Icon name="refreshCw" size={16} />
            </span>
          </button>
        </div>

        <div class="search-box">
          <Icon name="search" size={16} />
          <input bind:value={appFilter} placeholder="Search apps" />
        </div>

        <div class="app-list">
          {#if filteredApps.length === 0 && selectedGames.length === 0}
            <div class="empty-state">
              <Icon name="hardDrive" size={24} />
              <span>{appLoading ? "Scanning" : "No apps found"}</span>
            </div>
          {/if}

          {#each filteredApps as app (app.id)}
            <article class="app-row">
              <div class="app-icon">
                <Icon name="appWindow" size={18} />
              </div>
              <div class="app-copy">
                <strong>{app.name}</strong>
                <span>{app.kind}</span>
                <small>{shortPath(app.path)}</small>
              </div>
              <button class="icon-button strong" title={`Run ${app.name}`} aria-label={`Run ${app.name}`} on:click={() => runBottleApp(app)} disabled={busy !== ""}>
                <Icon name="play" size={16} />
              </button>
            </article>
          {/each}

          {#each selectedGames as game (game.id)}
            <article class="app-row registered">
              <div class="app-icon">
                <Icon name="shieldCheck" size={18} />
              </div>
              <div class="app-copy">
                <strong>{game.name}</strong>
                <span>{game.source || "library"}</span>
                <small>{shortPath(game.exe_path)}</small>
              </div>
              {#if game.steam_app_id && status?.steam_path}
                <button class="secondary-button compact-button" on:click={() => runRegisteredGame(game, "steam")} disabled={busy !== ""}>
                  <Icon name="disc3" size={15} />
                  Steam
                </button>
              {/if}
              <button class="icon-button strong" title={`Run ${game.name} directly`} aria-label={`Run ${game.name} directly`} on:click={() => runRegisteredGame(game, "direct")} disabled={busy !== ""}>
                <Icon name="play" size={16} />
              </button>
            </article>
          {/each}
        </div>
      </section>
    </div>
  </main>

  {#if settingsOpen && config}
    <aside class="settings-drawer" aria-label="Settings">
      <div class="drawer-heading">
        <div>
          <span class="eyebrow">Settings</span>
          <h2>Runtime Paths</h2>
        </div>
        <button class="icon-button" title="Close settings" aria-label="Close settings" on:click={() => (settingsOpen = false)}>
          <Icon name="x" size={17} />
        </button>
      </div>

      <label>
        <span>Wine binary</span>
        <input bind:value={config.wine64_path} />
      </label>
      <label>
        <span>GPTK library</span>
        <input bind:value={config.gptk_lib_path} />
      </label>
      <label>
        <span>Default bottle</span>
        <input bind:value={config.default_prefix} />
      </label>

      <div class="toggle-row">
        <span>Metal HUD</span>
        <input type="checkbox" bind:checked={config.global_hud} />
      </div>
      <div class="toggle-row">
        <span>MetalFX</span>
        <input type="checkbox" bind:checked={config.metalfx_enabled} />
      </div>
      <div class="toggle-row">
        <span>Quiet Wine logs</span>
        <input type="checkbox" bind:checked={config.suppress_wine_debug} />
      </div>

      <button class="primary-button" on:click={persistSettings} disabled={busy !== ""}>
        <Icon name="save" size={15} />
        Save
      </button>
    </aside>
  {/if}

  <div class="toast-stack" aria-live="polite">
    {#each toasts as toast (toast.id)}
      <div class="toast" class:ok={toast.tone === "ok"} class:bad={toast.tone === "bad"}>
        <span>{toast.text}</span>
        <button class="icon-button small" title="Dismiss" aria-label="Dismiss" on:click={() => dismissToast(toast.id)}>
          <Icon name="x" size={14} />
        </button>
      </div>
    {/each}
  </div>
</div>

<style>
  :global(*) {
    box-sizing: border-box;
  }

  :global(html),
  :global(body),
  :global(#app) {
    width: 100%;
    height: 100%;
    margin: 0;
  }

  :global(body) {
    overflow: hidden;
    background: #eef2f0;
    color: #18211e;
    font-family:
      Inter, ui-sans-serif, system-ui, -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif;
  }

  button,
  input {
    font: inherit;
  }

  button {
    border: 0;
  }

  .app-shell {
    display: grid;
    grid-template-columns: 292px minmax(0, 1fr);
    width: 100%;
    height: 100%;
    min-width: 860px;
    background:
      linear-gradient(180deg, rgba(255, 255, 255, 0.74), rgba(255, 255, 255, 0) 360px),
      #eef2f0;
  }

  .sidebar {
    display: flex;
    flex-direction: column;
    gap: 14px;
    min-width: 0;
    padding: 18px;
    border-right: 1px solid #cfd7d2;
    background: #f7f8f6;
  }

  .brand-row,
  .topbar,
  .panel-heading,
  .drawer-heading,
  .tool-row,
  .steam-actions,
  .section-title,
  .launcher-row,
  .search-box,
  .input-button,
  .toggle-row {
    display: flex;
    align-items: center;
  }

  .brand-row {
    gap: 10px;
    min-height: 38px;
  }

  .brand-mark,
  .app-icon {
    display: grid;
    place-items: center;
    flex: 0 0 auto;
    border: 1px solid #c7d3cc;
    background: #ffffff;
    color: #1f6f5b;
  }

  .brand-mark {
    width: 36px;
    height: 36px;
    border-radius: 8px;
  }

  .brand-copy {
    display: grid;
    flex: 1;
    min-width: 0;
    line-height: 1.1;
  }

  .brand-copy strong {
    font-size: 15px;
  }

  .brand-copy span,
  .eyebrow,
  label span,
  .runtime-meta span,
  .app-copy span,
  .app-copy small,
  .bottle-text small {
    color: #66716c;
    font-size: 12px;
  }

  .tool-row {
    justify-content: stretch;
  }

  .tool-row > button {
    width: 100%;
  }

  .bottle-list {
    display: flex;
    flex: 1;
    flex-direction: column;
    gap: 8px;
    min-height: 0;
    overflow: auto;
    padding-right: 2px;
  }

  .bottle-item {
    display: grid;
    grid-template-columns: 22px minmax(0, 1fr) 10px;
    gap: 9px;
    align-items: center;
    width: 100%;
    min-height: 58px;
    padding: 10px;
    border: 1px solid transparent;
    border-radius: 8px;
    background: transparent;
    color: #23302b;
    text-align: left;
    cursor: pointer;
  }

  .bottle-item:hover,
  .bottle-item.active {
    border-color: #b7cac0;
    background: #ffffff;
  }

  .bottle-item.active {
    box-shadow: inset 3px 0 0 #22735e;
  }

  .bottle-text {
    display: grid;
    gap: 4px;
    min-width: 0;
  }

  .bottle-text strong,
  .bottle-text small,
  .app-copy strong,
  .app-copy span,
  .app-copy small,
  .title-block p,
  .runtime-meta strong {
    overflow: hidden;
    text-overflow: ellipsis;
    white-space: nowrap;
  }

  .dot {
    width: 8px;
    height: 8px;
    border-radius: 999px;
    background: #c6ccc8;
  }

  .dot.ok,
  .system-pill.ok,
  .status-label.ok {
    color: #12674f;
    background: #e2f4ec;
  }

  .dot.ok {
    background: #1d8f6e;
  }

  .dot.warn {
    background: #c98c22;
  }

  .create-box {
    display: grid;
    gap: 10px;
    padding-top: 12px;
    border-top: 1px solid #d8dfdb;
  }

  label {
    display: grid;
    gap: 6px;
    min-width: 0;
  }

  input {
    width: 100%;
    min-width: 0;
    height: 36px;
    padding: 0 11px;
    border: 1px solid #c8d1cc;
    border-radius: 8px;
    outline: none;
    background: #ffffff;
    color: #17211d;
  }

  input:focus {
    border-color: #2c8069;
    box-shadow: 0 0 0 3px rgba(44, 128, 105, 0.13);
  }

  .input-button {
    gap: 7px;
    min-width: 0;
  }

  .main-surface {
    display: flex;
    flex-direction: column;
    min-width: 0;
    min-height: 0;
    overflow: hidden;
    padding: 22px;
  }

  .topbar {
    justify-content: space-between;
    gap: 18px;
    min-height: 72px;
    margin-bottom: 18px;
  }

  .title-block {
    min-width: 0;
  }

  .eyebrow {
    display: block;
    margin-bottom: 5px;
    text-transform: uppercase;
  }

  h1,
  h2,
  p {
    margin: 0;
  }

  h1 {
    font-size: 28px;
    font-weight: 720;
    line-height: 1.1;
  }

  h2 {
    font-size: 18px;
    line-height: 1.2;
  }

  .title-block p {
    max-width: 780px;
    margin-top: 6px;
    color: #5b6761;
    font-size: 13px;
  }

  .topbar-actions {
    display: flex;
    flex: 0 0 auto;
    gap: 8px;
  }

  .system-pill,
  .status-label {
    display: inline-flex;
    align-items: center;
    gap: 7px;
    min-height: 30px;
    padding: 0 10px;
    border: 1px solid #ccd7d1;
    border-radius: 999px;
    background: #ffffff;
    color: #4f5d56;
    font-size: 12px;
    font-weight: 650;
  }

  .system-pill.bad {
    color: #9b3028;
    background: #fdecea;
  }

  .content-grid {
    display: grid;
    flex: 1;
    grid-template-columns: minmax(320px, 420px) minmax(0, 1fr);
    gap: 16px;
    min-height: 0;
  }

  .panel,
  .settings-drawer {
    border: 1px solid #cfd8d2;
    border-radius: 8px;
    background: rgba(255, 255, 255, 0.84);
    box-shadow: 0 14px 40px rgba(36, 51, 45, 0.08);
  }

  .panel {
    min-width: 0;
    min-height: 0;
    padding: 16px;
  }

  .runtime-panel,
  .apps-panel {
    display: flex;
    flex-direction: column;
    gap: 16px;
  }

  .runtime-panel {
    overflow: auto;
  }

  .apps-panel {
    overflow: hidden;
  }

  .panel-heading {
    justify-content: space-between;
    gap: 12px;
    min-height: 42px;
  }

  .steam-actions {
    flex-wrap: wrap;
    gap: 8px;
  }

  .runtime-meta {
    display: grid;
    grid-template-columns: 96px minmax(0, 1fr);
    gap: 8px;
    padding: 12px;
    border: 1px solid #dde5e0;
    border-radius: 8px;
    background: #f8faf8;
  }

  .runtime-meta div {
    display: grid;
    min-width: 0;
    gap: 3px;
  }

  .runtime-meta div:nth-child(2) {
    min-width: 0;
  }

  .launcher-list,
  .custom-runner {
    display: grid;
    gap: 8px;
  }

  .launcher-row {
    justify-content: space-between;
    gap: 8px;
    min-height: 42px;
    padding: 8px 0;
    border-top: 1px solid #e4ebe7;
  }

  .launcher-name {
    display: flex;
    align-items: center;
    gap: 9px;
    min-width: 0;
    color: #24322d;
    font-size: 13px;
    font-weight: 650;
  }

  .section-title {
    gap: 8px;
    color: #39453f;
    font-size: 13px;
    font-weight: 700;
  }

  .search-box {
    gap: 8px;
    height: 38px;
    padding: 0 11px;
    border: 1px solid #c8d1cc;
    border-radius: 8px;
    background: #ffffff;
    color: #65716b;
  }

  .search-box input {
    height: 34px;
    padding: 0;
    border: 0;
    box-shadow: none;
  }

  .app-list {
    display: flex;
    flex: 1;
    flex-direction: column;
    gap: 8px;
    min-height: 0;
    overflow: auto;
    padding-right: 2px;
  }

  .app-row {
    display: grid;
    grid-template-columns: 38px minmax(0, 1fr) auto auto;
    gap: 10px;
    align-items: center;
    min-height: 64px;
    padding: 10px;
    border: 1px solid #dce4df;
    border-radius: 8px;
    background: #ffffff;
  }

  .app-row.registered {
    border-color: #ccd8e4;
    background: #fbfdff;
  }

  .app-icon {
    width: 36px;
    height: 36px;
    border-radius: 8px;
  }

  .app-copy {
    display: grid;
    gap: 3px;
    min-width: 0;
  }

  .app-copy strong {
    font-size: 14px;
  }

  .app-copy span {
    text-transform: capitalize;
  }

  .empty-state {
    display: grid;
    place-items: center;
    gap: 8px;
    min-height: 140px;
    border: 1px dashed #c8d2cc;
    border-radius: 8px;
    color: #6a756f;
    background: #f8faf8;
    font-size: 13px;
  }

  .empty-state.compact {
    min-height: 80px;
  }

  .settings-drawer {
    position: fixed;
    top: 16px;
    right: 16px;
    z-index: 20;
    display: grid;
    gap: 14px;
    width: min(420px, calc(100vw - 32px));
    padding: 16px;
  }

  .drawer-heading {
    justify-content: space-between;
    gap: 12px;
  }

  .toggle-row {
    justify-content: space-between;
    min-height: 38px;
    padding: 0 2px;
    color: #26322d;
    font-size: 13px;
    font-weight: 650;
  }

  .toggle-row input {
    width: 18px;
    height: 18px;
    accent-color: #22735e;
  }

  .primary-button,
  .secondary-button,
  .ghost-button,
  .icon-button {
    display: inline-flex;
    align-items: center;
    justify-content: center;
    gap: 7px;
    height: 36px;
    border-radius: 8px;
    font-size: 13px;
    font-weight: 700;
    cursor: pointer;
    transition:
      background 120ms ease,
      border-color 120ms ease,
      color 120ms ease,
      transform 120ms ease;
  }

  .primary-button {
    padding: 0 13px;
    background: #22735e;
    color: #ffffff;
  }

  .primary-button:hover {
    background: #1a604e;
  }

  .secondary-button {
    padding: 0 12px;
    border: 1px solid #bdcbc4;
    background: #ffffff;
    color: #25322d;
  }

  .secondary-button:hover,
  .ghost-button:hover,
  .icon-button:hover {
    background: #edf4f0;
  }

  .ghost-button {
    padding: 0 10px;
    background: transparent;
    color: #266652;
  }

  .icon-button {
    width: 36px;
    flex: 0 0 auto;
    border: 1px solid #cbd6d0;
    background: #ffffff;
    color: #27342f;
  }

  .icon-button.strong {
    color: #17664f;
  }

  .icon-button.small {
    width: 26px;
    height: 26px;
    border: 0;
    background: transparent;
  }

  .compact-button {
    height: 34px;
    padding: 0 10px;
  }

  button:disabled {
    cursor: not-allowed;
    opacity: 0.48;
    transform: none;
  }

  .spin {
    display: inline-flex;
    animation: spin 1s linear infinite;
  }

  .toast-stack {
    position: fixed;
    right: 18px;
    bottom: 18px;
    z-index: 30;
    display: grid;
    gap: 8px;
    width: min(420px, calc(100vw - 36px));
  }

  .toast {
    display: flex;
    align-items: center;
    justify-content: space-between;
    gap: 12px;
    min-height: 42px;
    padding: 8px 8px 8px 12px;
    border: 1px solid #cfd8d2;
    border-radius: 8px;
    background: #ffffff;
    color: #25312c;
    box-shadow: 0 10px 30px rgba(23, 37, 31, 0.14);
    font-size: 13px;
  }

  .toast.ok {
    border-color: #9dceb9;
    background: #eef9f3;
  }

  .toast.bad {
    border-color: #e2aca8;
    background: #fff3f1;
  }

  @keyframes spin {
    to {
      transform: rotate(360deg);
    }
  }

  @media (max-width: 1040px) {
    .app-shell {
      grid-template-columns: 248px minmax(0, 1fr);
      min-width: 720px;
    }

    .content-grid {
      grid-template-columns: 1fr;
      overflow: auto;
    }
  }
</style>
