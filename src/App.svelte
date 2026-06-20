<script lang="ts">
  import { onDestroy, onMount } from "svelte";
  import { getCurrentWebview } from "@tauri-apps/api/webview";
  import Icon from "$lib/components/Icon.svelte";
  import {
    canUseDesktopCommands,
    checkWine,
    createBottle as createBottleCommand,
    launcherStatus,
    listBottleApps,
    listBottles,
    loadConfig,
    loadGames,
    pickExe,
    runExe,
    saveConfig,
    updateBottleRuntime,
    upsertGame,
  } from "$lib/tauri";
  import type { AppConfig, Bottle, BottleApp, Game, GraphicsBackend, WineStatus } from "$lib/types";

  type Toast = {
    id: number;
    tone: "ok" | "bad" | "info";
    text: string;
  };

  type ExeEntry = {
    key: string;
    id: string;
    name: string;
    path: string;
    kind: string;
    source: "library" | "scan";
    app?: BottleApp;
    game?: Game;
  };

  type RuntimeStackId = "wine11-moltenvk";
  type RuntimeChoiceId = RuntimeStackId | "custom";

  const steamSafeArgs = ["-no-cef-sandbox", "-cef-disable-sandbox"] as const;
  const defaultRuntimeStackId: RuntimeStackId = "wine11-moltenvk";
  const runtimeStacks: {
    id: RuntimeStackId;
    label: string;
    bottleName: string;
    profileId: string;
    backend: GraphicsBackend;
  }[] = [
    {
      id: defaultRuntimeStackId,
      label: "Wine 11 + MoltenVK",
      bottleName: "Wine 11 Vulkan",
      profileId: "wine-vulkan",
      backend: "dxvk_vkd3d",
    },
  ];
  let bottles: Bottle[] = [];
  let selectedBottleId = "";
  let apps: BottleApp[] = [];
  let games: Game[] = [];
  let config: AppConfig | null = null;
  let wine: WineStatus | null = null;
  let selectedBottle: Bottle | undefined;
  let exeRows: ExeEntry[] = [];
  let loading = true;
  let appLoading = false;
  let busy = "";
  let appFilter = "";
  let settingsOpen = false;
  let toasts: Toast[] = [];
  let toastId = 1;
  let unlistenDrop: (() => void) | null = null;
  const desktopCommandsAvailable = canUseDesktopCommands();

  $: selectedBottle = bottles.find((bottle) => bottle.id === selectedBottleId) || bottles[0];
  $: exeRows = buildExeRows(apps, games, appFilter);

  onMount(() => {
    void refreshAll();
    void setupFileDrop();
  });

  onDestroy(() => {
    unlistenDrop?.();
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
      const [nextApps, nextBottles, nextGames] = await Promise.all([
        listBottleApps(bottle.prefix_path),
        listBottles(),
        loadGames(),
      ]);

      apps = nextApps;
      bottles = nextBottles;
      games = nextGames;
    } catch (error) {
      notify("bad", errorMessage(error));
    } finally {
      appLoading = false;
    }
  }

  async function chooseExe() {
    const picked = await pickExe();
    if (picked) await addExePath(picked);
  }

  async function addExePath(path: string) {
    const exePath = path.trim();

    if (!exePath.toLowerCase().endsWith(".exe")) {
      notify("bad", "Choose a Windows .exe file.");
      return;
    }

    await withBusy("add-exe", async () => {
      const bottle = await ensureRuntimeBottle(defaultRuntimeStackId);
      const game: Game = {
        id: manualGameId(exePath),
        name: exeDisplayName(exePath),
        exe_path: exePath,
        working_dir: parentPath(exePath),
        wine_prefix: bottle.prefix_path,
        source: "manual",
        env_overrides: {},
      };
      games = await upsertGame(game);
      notify("ok", `${game.name} added to ${runtimeStackLabel(defaultRuntimeStackId)}.`);
    });
  }

  async function runExePath(path: string, args: string[] = []) {
    const bottle = currentBottle();
    if (!bottle) return;

    if (!desktopCommandsAvailable) {
      notify("bad", "Launch is only available in the Tauri desktop app.");
      return;
    }

    await withBusy("custom-exe", async () => {
      await runExe(bottle.prefix_path, path, args);
      notify("ok", "App started.");
      await refreshSelectedBottle();
    });
  }

  async function setupFileDrop() {
    if (!("__TAURI_INTERNALS__" in window)) return;

    unlistenDrop = await getCurrentWebview().onDragDropEvent((event) => {
      const payload = event.payload as { type: string; paths?: string[] };
      if (payload.type !== "drop") {
        return;
      }

      const exe = (payload.paths || []).find((droppedPath: string) => droppedPath.toLowerCase().endsWith(".exe"));
      if (!exe) {
        notify("bad", "Drop a Windows .exe file.");
        return;
      }

      void addExePath(exe);
    });
  }

  function isSteamPath(path: string) {
    return path.replace(/\\/g, "/").toLowerCase().endsWith("/steam.exe");
  }

  function isSteamApp(app: BottleApp) {
    return app.name.toLowerCase() === "steam" || isSteamPath(app.path);
  }

  function steamAppLaunchArgs(appId?: string | number) {
    return appId ? [...steamSafeArgs, "-applaunch", String(appId)] : [...steamSafeArgs];
  }

  function launchArgsForPath(path: string) {
    return isSteamPath(path) ? steamAppLaunchArgs() : [];
  }

  function launchArgsForApp(app: BottleApp) {
    return isSteamApp(app) ? steamAppLaunchArgs() : [];
  }

  async function runBottleApp(app: BottleApp) {
    const bottle = currentBottle();
    if (!bottle) return;

    if (!desktopCommandsAvailable) {
      notify("bad", "Launch is only available in the Tauri desktop app.");
      return;
    }

    await withBusy(`app-${app.id}`, async () => {
      await runExe(bottle.prefix_path, app.path, launchArgsForApp(app));
      notify("ok", `${app.name} started.`);
    });
  }

  async function runRegisteredGame(game: Game, mode: "steam" | "direct") {
    if (!config) return;
    const prefixPath = game.wine_prefix || config.default_prefix;

    if (!desktopCommandsAvailable) {
      notify("bad", "Launch is only available in the Tauri desktop app.");
      return;
    }

    await withBusy(`${mode}-${game.id}`, async () => {
      const targetStatus = mode === "steam" ? await launcherStatus(prefixPath) : null;
      if (mode === "steam" && game.steam_app_id && targetStatus?.steam_path) {
        await runExe(prefixPath, targetStatus.steam_path, steamAppLaunchArgs(game.steam_app_id));
      } else {
        await runExe(prefixPath, game.exe_path, launchArgsForPath(game.exe_path));
      }
      notify("ok", `${game.name} started.`);
    });
  }

  async function runExeEntry(entry: ExeEntry) {
    if (entry.game) {
      await runRegisteredGame(entry.game, "direct");
      return;
    }

    if (entry.app) {
      await runBottleApp(entry.app);
      return;
    }

    await runExePath(entry.path);
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

  async function ensureRuntimeBottle(stackId: RuntimeStackId) {
    const existing = bottleForRuntimeStack(stackId);
    if (existing) return existing;

    const stack = runtimeStackForId(stackId);
    if (!stack) throw new Error("Unknown runtime stack.");

    const nextBottles = await createBottleCommand(stack.bottleName);
    const created =
      nextBottles.find((bottle) => bottle.name === stack.bottleName) ||
      nextBottles[nextBottles.length - 1];

    if (!created) {
      throw new Error(`Could not create ${stack.bottleName}.`);
    }

    bottles = await updateBottleRuntime(
      created.prefix_path,
      stack.profileId,
      stack.backend,
      created.env_overrides || {},
      true,
    );

    return bottleForRuntimeStack(stackId) || bottleForPrefix(created.prefix_path) || created;
  }

  function bottleForRuntimeStack(stackId: RuntimeStackId) {
    return bottles.find((bottle) => runtimeStackIdForBottle(bottle) === stackId);
  }

  function runtimeStackForId(stackId: RuntimeStackId) {
    return runtimeStacks.find((stack) => stack.id === stackId);
  }

  function runtimeStackLabel(stackId: RuntimeStackId) {
    return runtimeStackForId(stackId)?.label || "configured runtime";
  }

  function bottleForPrefix(prefix?: string | null) {
    return bottles.find((bottle) => samePath(bottle.prefix_path, prefix));
  }

  function runtimeStackIdForBottle(bottle?: Bottle): RuntimeChoiceId {
    if (!bottle) return "custom";

    return runtimeStacks.find((stack) => stack.profileId === bottle.runtime_profile_id)?.id || "custom";
  }

  function buildExeRows(scannedApps: BottleApp[], libraryGames: Game[], filter: string) {
    const rows = new Map<string, ExeEntry>();

    for (const app of scannedApps) {
      const key = exeKey(app.path);
      rows.set(key, {
        key,
        id: `app-${app.id}`,
        name: app.name,
        path: app.path,
        kind: app.kind,
        source: "scan",
        app,
      });
    }

    for (const game of libraryGames) {
      const key = exeKey(game.exe_path);
      rows.set(key, {
        key,
        id: `game-${game.id}`,
        name: game.name,
        path: game.exe_path,
        kind: game.source || "manual",
        source: "library",
        game,
      });
    }

    const needle = filter.trim().toLowerCase();
    return Array.from(rows.values())
      .filter((entry) => {
        if (!needle) return true;
        return `${entry.name} ${entry.kind} ${entry.path}`.toLowerCase().includes(needle);
      })
      .sort((a, b) => {
        if (a.source !== b.source) return a.source === "library" ? -1 : 1;
        return kindRank(a.kind) - kindRank(b.kind) || a.name.localeCompare(b.name);
      });
  }

  function kindRank(kind: string) {
    const normalized = kind.toLowerCase();
    if (normalized === "manual") return 0;
    if (normalized === "launcher") return 1;
    if (normalized === "app") return 2;
    if (normalized === "setup") return 3;
    return 4;
  }

  function exeKey(path: string) {
    return path.trim().replace(/\/+$/, "").toLowerCase();
  }

  function manualGameId(path: string) {
    return `manual-${stableHash(exeKey(path))}`;
  }

  function stableHash(value: string) {
    let hash = 2166136261;
    for (let index = 0; index < value.length; index += 1) {
      hash ^= value.charCodeAt(index);
      hash = Math.imul(hash, 16777619);
    }
    return (hash >>> 0).toString(16);
  }

  function exeDisplayName(path: string) {
    const file = path.split(/[\\/]/).pop()?.replace(/\.exe$/i, "") || "Windows App";
    return humanize(file);
  }

  function humanize(value: string) {
    const normalized = value
      .replace(/[_-]+/g, " ")
      .replace(/\s+/g, " ")
      .trim();

    return normalized
      ? normalized.replace(/\b[a-z]/g, (letter) => letter.toUpperCase())
      : "Windows App";
  }

  function parentPath(path: string) {
    const normalized = path.replace(/\\/g, "/");
    const index = normalized.lastIndexOf("/");
    return index > 0 ? normalized.slice(0, index) : null;
  }

  function handleDropZoneKey(event: KeyboardEvent) {
    if (event.key !== "Enter" && event.key !== " ") return;
    event.preventDefault();
    void chooseExe();
  }
</script>

<svelte:head>
  <title>Forge Launcher</title>
</svelte:head>

<div class="app-shell single-bottle-shell">
  <main class="workspace">
    <header class="topbar">
      <div class="brand-mark">
        <Icon name="bottleWine" size={24} />
      </div>
      <div class="title-block">
        <span class="eyebrow">Wine Bottle</span>
        <h1>{selectedBottle?.name || "Default"}</h1>
        <p>{shortPath(selectedBottle?.prefix_path)}</p>
      </div>
      <div class="topbar-actions">
        <span class="system-pill" class:ok={wine?.installed} class:bad={!wine?.installed}>
          <Icon name={wine?.installed ? "circleCheck" : "circleAlert"} size={15} />
          {runtimeStackLabel(defaultRuntimeStackId)}
        </span>
        <button class="icon-button" title="Refresh" aria-label="Refresh" on:click={refreshAll} disabled={loading || busy !== ""}>
          <span class:spin={loading || appLoading}>
            <Icon name="refreshCw" size={16} />
          </span>
        </button>
        <button class="icon-button" title="Settings" aria-label="Settings" on:click={() => (settingsOpen = true)}>
          <Icon name="settings" size={17} />
        </button>
      </div>
    </header>

    <section class="exe-panel full-exe-panel" aria-label="Executables">
      <div class="panel-heading">
        <div>
          <span class="eyebrow">Installed apps</span>
          <h2>Executables</h2>
        </div>
        <button class="primary-button" on:click={chooseExe} disabled={busy !== ""}>
          <Icon name="folderOpen" size={16} />
          Add .exe
        </button>
      </div>

      <div class="search-box">
        <Icon name="search" size={16} />
        <input bind:value={appFilter} placeholder="Search installed .exe files" />
      </div>

      <div class="exe-list">
        {#if exeRows.length === 0}
          <div class="empty-state">
            <Icon name="hardDrive" size={24} />
            <span>{appLoading ? "Scanning bottle" : "No user-installed .exe files found"}</span>
          </div>
        {/if}

        {#each exeRows as entry (entry.key)}
          <article class="exe-row">
            <div class="app-icon">
              <Icon name="appWindow" size={18} />
            </div>
            <div class="app-copy">
              <strong>{entry.name}</strong>
              <span>{entry.kind}</span>
              <small>{shortPath(entry.path)}</small>
            </div>
            <button
              class="run-button"
              title={desktopCommandsAvailable ? `Run ${entry.name}` : "Open the Tauri desktop app to launch"}
              aria-label={desktopCommandsAvailable ? `Run ${entry.name}` : "Open the Tauri desktop app to launch"}
              on:click={() => runExeEntry(entry)}
              disabled={busy !== ""}
            >
              <Icon name="play" size={16} />
              <span>Play</span>
            </button>
          </article>
        {/each}
      </div>
    </section>
  </main>

  {#if settingsOpen && config}
    <aside class="settings-drawer" aria-label="Settings">
      <div class="drawer-heading">
        <div>
          <span class="eyebrow">Settings</span>
          <h2>{runtimeStackLabel(defaultRuntimeStackId)}</h2>
        </div>
        <button class="icon-button" title="Close settings" aria-label="Close settings" on:click={() => (settingsOpen = false)}>
          <Icon name="x" size={17} />
        </button>
      </div>

      <label>
        <span>Wine 11 binary</span>
        <input bind:value={config.wine64_path} placeholder="/Applications/Wine Devel.app/Contents/Resources/wine/bin/wine" />
      </label>
      <label>
        <span>Default bottle</span>
        <input bind:value={config.default_prefix} />
      </label>

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
  :global(*) { box-sizing: border-box; }
  :global(html), :global(body), :global(#app) {
    width: 100%; height: 100%; margin: 0;
  }
  :global(body) {
    overflow: hidden;
    background: #000;
    color: #f5f5f5;
    font-family: Inter, ui-sans-serif, system-ui, -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif;
  }

  button, input { font: inherit; }
  button { border: 0; }
  h1, h2, p { margin: 0; }

  .app-shell {
    width: 100vw;
    height: 100vh;
    overflow: hidden;
    background: #000;
  }

  .workspace {
    display: flex;
    flex-direction: column;
    gap: 18px;
    width: min(1120px, 100%);
    height: 100%;
    margin: 0 auto;
    padding: 28px;
    overflow: hidden;
  }

  .topbar, .panel-heading, .drawer-heading, .search-box, .toggle-row, .topbar-actions {
    display: flex;
    align-items: center;
  }

  .topbar {
    gap: 14px;
  }

  .title-block {
    min-width: 0;
    flex: 1;
  }

  .title-block p, .app-copy strong, .app-copy span, .app-copy small {
    overflow: hidden;
    text-overflow: ellipsis;
    white-space: nowrap;
  }

  .brand-mark, .app-icon {
    display: grid;
    place-items: center;
    flex: 0 0 auto;
    border: 1px solid #202020;
    background: #080808;
    color: #2bf0a1;
  }

  .brand-mark {
    width: 44px;
    height: 44px;
    border-radius: 8px;
  }

  .app-icon {
    width: 44px;
    height: 44px;
    border-radius: 8px;
  }

  .eyebrow, label span, .title-block p, .app-copy span, .app-copy small {
    color: #8a8a8a;
    font-size: 12px;
  }

  .eyebrow {
    display: block;
    margin-bottom: 5px;
    text-transform: uppercase;
    letter-spacing: 0;
  }

  h1 {
    color: #fff;
    font-size: 34px;
    font-weight: 800;
    line-height: 1.05;
    letter-spacing: 0;
  }

  h2 {
    color: #fff;
    font-size: 18px;
    font-weight: 750;
  }

  .topbar-actions {
    flex: 0 0 auto;
    gap: 8px;
  }

  .system-pill {
    display: inline-flex;
    align-items: center;
    gap: 7px;
    height: 36px;
    padding: 0 11px;
    border: 1px solid #202020;
    border-radius: 999px;
    background: #080808;
    color: #d8d8d8;
    font-size: 12px;
    font-weight: 700;
    white-space: nowrap;
  }

  .system-pill.ok {
    border-color: rgba(43, 240, 161, 0.25);
    background: rgba(43, 240, 161, 0.08);
    color: #9ff7d1;
  }

  .system-pill.bad {
    border-color: rgba(255, 92, 92, 0.35);
    background: rgba(255, 92, 92, 0.1);
    color: #ffaaaa;
  }

  .exe-panel {
    display: flex;
    flex-direction: column;
    gap: 14px;
    flex: 1;
    min-height: 0;
    padding: 18px;
    border: 1px solid #171717;
    border-radius: 8px;
    background: #050505;
    overflow: hidden;
  }

  .panel-heading {
    justify-content: space-between;
    gap: 14px;
  }

  .search-box {
    gap: 9px;
    height: 44px;
    padding: 0 12px;
    border: 1px solid #202020;
    border-radius: 8px;
    background: #000;
    color: #8a8a8a;
  }

  input {
    width: 100%;
    min-width: 0;
    height: 38px;
    padding: 0 11px;
    border: 1px solid #202020;
    border-radius: 8px;
    outline: none;
    background: #000;
    color: #f5f5f5;
  }

  input::placeholder { color: #666; }
  input:focus, button:focus-visible {
    border-color: #2bf0a1;
    box-shadow: 0 0 0 3px rgba(43, 240, 161, 0.14);
    outline: none;
  }

  .search-box input {
    height: 40px;
    padding: 0;
    border: 0;
    background: transparent;
    box-shadow: none;
  }

  .exe-list {
    display: flex;
    flex-direction: column;
    gap: 10px;
    flex: 1;
    min-height: 0;
    overflow: auto;
    padding-right: 4px;
  }

  .exe-row {
    display: grid;
    grid-template-columns: 44px minmax(0, 1fr) auto;
    gap: 14px;
    align-items: center;
    min-height: 74px;
    padding: 12px 14px;
    border: 1px solid #171717;
    border-radius: 8px;
    background: #0a0a0a;
  }

  .exe-row:hover {
    border-color: #2a2a2a;
    background: #0f0f0f;
  }

  .app-copy {
    display: grid;
    gap: 3px;
    min-width: 0;
  }

  .app-copy strong {
    color: #fff;
    font-size: 16px;
  }

  .primary-button, .run-button, .icon-button {
    display: inline-flex;
    align-items: center;
    justify-content: center;
    gap: 7px;
    height: 40px;
    border-radius: 8px;
    font-size: 13px;
    font-weight: 800;
    cursor: pointer;
  }

  .primary-button, .run-button {
    min-width: 92px;
    padding: 0 14px;
    background: #2bf0a1;
    color: #000;
  }

  .primary-button:hover, .run-button:hover { background: #78ffd0; }

  .icon-button {
    width: 40px;
    flex: 0 0 auto;
    border: 1px solid #202020;
    background: #080808;
    color: #f2f2f2;
  }

  .icon-button:hover { background: #121212; }
  .icon-button.small {
    width: 26px;
    height: 26px;
    border: 0;
    background: transparent;
  }

  button:disabled {
    cursor: not-allowed;
    opacity: 0.48;
  }

  .empty-state {
    display: grid;
    place-items: center;
    gap: 8px;
    min-height: 140px;
    border: 1px dashed #242424;
    border-radius: 8px;
    background: #080808;
    color: #8a8a8a;
    font-size: 13px;
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
    border: 1px solid #202020;
    border-radius: 8px;
    background: #050505;
  }

  .drawer-heading, .toggle-row { justify-content: space-between; gap: 12px; }
  label { display: grid; gap: 6px; min-width: 0; }
  .toggle-row { color: #d8d8d8; font-size: 13px; font-weight: 700; }
  .toggle-row input { width: 18px; height: 18px; accent-color: #2bf0a1; }

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
    border: 1px solid #202020;
    border-radius: 8px;
    background: #080808;
    color: #f2f2f2;
    font-size: 13px;
  }

  .toast.ok { border-color: rgba(43, 240, 161, 0.34); }
  .toast.bad { border-color: rgba(255, 92, 92, 0.42); }

  .spin { display: inline-flex; animation: spin 1s linear infinite; }
  @keyframes spin { to { transform: rotate(360deg); } }

  @media (max-width: 720px) {
    .workspace { padding: 16px; }
    .topbar { display: grid; grid-template-columns: 44px minmax(0, 1fr); }
    .topbar-actions { grid-column: 1 / -1; justify-content: space-between; }
    .system-pill { flex: 1; justify-content: center; }
    h1 { font-size: 28px; }
    .exe-panel { padding: 14px; }
    .panel-heading { align-items: flex-start; }
    .exe-row { grid-template-columns: 44px minmax(0, 1fr); }
    .run-button { grid-column: 1 / -1; width: 100%; }
  }
</style>
