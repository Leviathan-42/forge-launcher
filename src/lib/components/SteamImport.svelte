<!--
  SteamImport.svelte

  Modal / panel that lets the user scan their local Steam library and import
  Windows-only games into the Forge Launcher library.

  Flow:
    1. User clicks "Scan Steam Library"
    2. Rust reads ACF manifests from ~/Library/.../Steam/steamapps/
    3. Results populate a searchable list
    4. User selects games and clicks "Import Selected"
    5. Each selected game is upserted into the library as a Steam-sourced entry
-->

<script lang="ts">
  import { onMount }         from "svelte";
  import type { SteamGame, Game } from "../types/index";
  import {
    steamGames,
    steamScanLoading,
    scanSteamGames,
  }                          from "../stores/config";
  import { upsertGame }      from "../stores/games";
  import { notify }          from "../stores/launcher";

  /** Simple UUID v4 generator — no dependency needed */
  function generateId(): string {
    return "xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx".replace(/[xy]/g, (c) => {
      const r = (Math.random() * 16) | 0;
      return (c === "x" ? r : (r & 0x3) | 0x8).toString(16);
    });
  }

  /** Emitted when the panel should close. */
  export let onClose: () => void = () => {};

  let searchQuery    = "";
  let selected       = new Set<number>();  // selected app_ids
  let importing      = false;

  // Filter steam games by search query
  $: filtered = $steamGames.filter((g) =>
    g.name.toLowerCase().includes(searchQuery.toLowerCase())
  );

  function toggleSelect(appId: number) {
    selected = new Set(selected); // trigger reactivity
    if (selected.has(appId)) {
      selected.delete(appId);
    } else {
      selected.add(appId);
    }
    selected = selected; // reassign for Svelte reactivity
  }

  function selectAll()   { selected = new Set(filtered.map((g) => g.app_id)); }
  function selectNone()  { selected = new Set(); }

  function formatSize(bytes: number): string {
    if (bytes === 0) return "unknown";
    const gb = bytes / 1_073_741_824;
    return gb >= 1 ? `${gb.toFixed(1)} GB` : `${(bytes / 1_048_576).toFixed(0)} MB`;
  }

  async function importSelected() {
    if (selected.size === 0) return;
    importing = true;

    const toImport = $steamGames.filter((g) => selected.has(g.app_id));
    let imported = 0;

    for (const sg of toImport) {
      const game: Game = {
        id:                   generateId(),
        name:                 sg.name,
        exe_path:             sg.exe_path,
        working_dir:          sg.install_dir,
        cover_art:            null,
        wine_prefix:          null,          // uses global default
        extra_args:           [],
        translation_backend:  "d3dmetal",
        show_hud:             false,
        esync:                true,
        msync:                false,
        advertise_avx:        false,
        enable_dxr:           false,
        source:               "steam",
        steam_app_id:         sg.app_id,
        notes:                "",
        playtime_secs:        0,
        save_mappings:        [],
        mangohud_enabled:     false,
      };

      try {
        await upsertGame(game);
        imported++;
      } catch (err) {
        notify("error", `Failed to import "${sg.name}": ${err}`);
      }
    }

    importing = false;
    notify("success", `Imported ${imported} game${imported === 1 ? "" : "s"} from Steam`);
    onClose();
  }

  onMount(() => {
    if ($steamGames.length === 0) scanSteamGames();
  });
</script>

<div class="overlay" role="dialog" aria-modal="true" aria-label="Import Steam games">
  <div class="panel">

    <!-- Header -->
    <div class="panel-header">
      <div>
        <h2>Import from Steam</h2>
        <p class="subtitle">
          Windows-only games detected in your Steam library
        </p>
      </div>
      <button class="btn-close" on:click={onClose} aria-label="Close">✕</button>
    </div>

    <!-- Toolbar -->
    <div class="toolbar">
      <input
        class="search"
        type="search"
        placeholder="Search games…"
        bind:value={searchQuery}
        aria-label="Search games"
      />
      <button class="btn btn--scan" on:click={scanSteamGames} disabled={$steamScanLoading}>
        {$steamScanLoading ? "Scanning…" : "Re-scan"}
      </button>
    </div>

    <!-- Selection helpers -->
    {#if filtered.length > 0}
      <div class="selection-bar">
        <span>{selected.size} of {filtered.length} selected</span>
        <button class="link-btn" on:click={selectAll}>Select all</button>
        <span>·</span>
        <button class="link-btn" on:click={selectNone}>None</button>
      </div>
    {/if}

    <!-- Game list -->
    <div class="game-list" role="list">
      {#if $steamScanLoading}
        <div class="empty-state">Scanning Steam library…</div>

      {:else if filtered.length === 0}
        <div class="empty-state">
          {$steamGames.length === 0
            ? "No Steam games found. Is Steam installed?"
            : "No games match your search."}
        </div>

      {:else}
        {#each filtered as game (game.app_id)}
          <!-- svelte-ignore a11y-click-events-have-key-events -->
          <div
            class="game-row"
            class:selected={selected.has(game.app_id)}
            on:click={() => toggleSelect(game.app_id)}
            role="checkbox"
            aria-checked={selected.has(game.app_id)}
            tabindex="0"
            on:keydown={(e) => e.key === " " && toggleSelect(game.app_id)}
          >
            <div class="checkbox" aria-hidden="true">
              {#if selected.has(game.app_id)}✓{/if}
            </div>
            <div class="game-info">
              <span class="game-name">{game.name}</span>
              <span class="game-meta">
                AppID {game.app_id} · {formatSize(game.size_on_disk)}
              </span>
            </div>
            <div class="app-id-badge">{game.app_id}</div>
          </div>
        {/each}
      {/if}
    </div>

    <!-- Footer actions -->
    <div class="panel-footer">
      <button class="btn btn--cancel" on:click={onClose}>Cancel</button>
      <button
        class="btn btn--import"
        on:click={importSelected}
        disabled={selected.size === 0 || importing}
      >
        {importing ? "Importing…" : `Import ${selected.size > 0 ? selected.size : ""} Game${selected.size === 1 ? "" : "s"}`}
      </button>
    </div>

  </div>
</div>

<style>
  .overlay {
    position:        fixed;
    inset:           0;
    background:      rgba(0, 0, 0, 0.6);
    display:         flex;
    align-items:     center;
    justify-content: center;
    z-index:         100;
    backdrop-filter: blur(4px);
  }

  .panel {
    width:          620px;
    max-height:     80vh;
    background:     var(--color-surface, #1e1e2e);
    border-radius:  14px;
    border:         1px solid var(--color-border, #333348);
    display:        flex;
    flex-direction: column;
    overflow:       hidden;
    box-shadow:     0 24px 64px rgba(0,0,0,0.5);
  }

  .panel-header {
    display:         flex;
    justify-content: space-between;
    align-items:     flex-start;
    padding:         20px 24px 16px;
    border-bottom:   1px solid var(--color-border, #333348);
  }

  .panel-header h2 {
    margin:      0 0 4px;
    font-size:   1.1rem;
    font-weight: 700;
    color:       var(--color-text, #e2e2f0);
  }

  .subtitle {
    margin:    0;
    font-size: 0.8rem;
    color:     var(--color-muted, #888899);
  }

  .btn-close {
    background: transparent;
    border:     none;
    color:      var(--color-muted, #888899);
    font-size:  1.1rem;
    cursor:     pointer;
    padding:    4px 8px;
    border-radius: 6px;
    transition: color 0.15s;
  }

  .btn-close:hover { color: var(--color-text, #e2e2f0); }

  /* Toolbar */
  .toolbar {
    display:  flex;
    gap:      10px;
    padding:  14px 24px;
    border-bottom: 1px solid var(--color-border, #333348);
  }

  .search {
    flex:          1;
    background:    var(--color-surface-2, #2a2a3e);
    border:        1px solid var(--color-border, #333348);
    border-radius: 8px;
    padding:       8px 12px;
    font-size:     0.85rem;
    color:         var(--color-text, #e2e2f0);
    outline:       none;
  }

  .search:focus {
    border-color: var(--color-accent, #7f5af0);
  }

  /* Selection bar */
  .selection-bar {
    display:     flex;
    gap:         8px;
    align-items: center;
    padding:     8px 24px;
    font-size:   0.75rem;
    color:       var(--color-muted, #888899);
    border-bottom: 1px solid var(--color-border, #333348);
  }

  .link-btn {
    background: none;
    border:     none;
    color:      var(--color-accent, #7f5af0);
    cursor:     pointer;
    font-size:  0.75rem;
    padding:    0;
  }

  /* Game list */
  .game-list {
    flex:       1;
    overflow-y: auto;
    padding:    8px 0;
  }

  .game-row {
    display:     flex;
    align-items: center;
    gap:         12px;
    padding:     10px 24px;
    cursor:      pointer;
    transition:  background 0.1s;
    outline:     none;
  }

  .game-row:hover          { background: rgba(255,255,255,0.04); }
  .game-row:focus-visible  { background: rgba(127,90,240,0.08); }
  .game-row.selected       { background: rgba(127,90,240,0.12); }

  .checkbox {
    width:           18px;
    height:          18px;
    border:          2px solid var(--color-border, #555570);
    border-radius:   4px;
    display:         flex;
    align-items:     center;
    justify-content: center;
    font-size:       0.75rem;
    color:           var(--color-accent, #7f5af0);
    flex-shrink:     0;
    transition:      border-color 0.1s;
  }

  .game-row.selected .checkbox {
    border-color: var(--color-accent, #7f5af0);
    background:   var(--color-accent, #7f5af0);
    color:        #fff;
  }

  .game-info {
    flex:           1;
    display:        flex;
    flex-direction: column;
    gap:            2px;
    min-width:      0;
  }

  .game-name {
    font-size:     0.85rem;
    font-weight:   600;
    color:         var(--color-text, #e2e2f0);
    white-space:   nowrap;
    overflow:      hidden;
    text-overflow: ellipsis;
  }

  .game-meta {
    font-size: 0.72rem;
    color:     var(--color-muted, #888899);
  }

  .app-id-badge {
    font-size:     0.68rem;
    color:         var(--color-muted, #888899);
    background:    var(--color-surface-2, #2a2a3e);
    padding:       2px 6px;
    border-radius: 4px;
    flex-shrink:   0;
  }

  .empty-state {
    text-align: center;
    padding:    40px 24px;
    color:      var(--color-muted, #888899);
    font-size:  0.85rem;
  }

  /* Footer */
  .panel-footer {
    display:         flex;
    justify-content: flex-end;
    gap:             10px;
    padding:         16px 24px;
    border-top:      1px solid var(--color-border, #333348);
  }

  .btn {
    padding:       8px 20px;
    border:        none;
    border-radius: 8px;
    font-size:     0.85rem;
    font-weight:   600;
    cursor:        pointer;
    transition:    background 0.15s, opacity 0.15s;
  }

  .btn:disabled { opacity: 0.45; cursor: not-allowed; }

  .btn--cancel  { background: var(--color-surface-2, #2a2a3e); color: var(--color-text, #e2e2f0); }
  .btn--scan    { background: var(--color-surface-2, #2a2a3e); color: var(--color-text, #e2e2f0); }
  .btn--import  { background: var(--color-accent, #7f5af0);    color: #fff; }

  .btn--import:hover:not(:disabled) { background: var(--color-accent-hover, #9d7ef5); }
  .btn--scan:hover:not(:disabled)   { background: rgba(255,255,255,0.08); }
</style>
