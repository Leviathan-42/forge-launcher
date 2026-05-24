<!--
  GameCard.svelte

  Single game tile in the library grid.

  States:
    · Normal      — has an exe_path, ready to launch
    · Setup needed — no exe_path (downloaded but not configured yet)
    · Running     — process is live
    · Launching   — waiting for spawn confirmation

  Interactions:
    · Click card       — select (shows detail panel)
    · Delete key       — remove from library (while card is focused/selected)
    · Hover delete btn — top-right ✕ appears on hover
    · Launch / Stop    — primary action button
-->

<script lang="ts">
  import { convertFileSrc }               from "@tauri-apps/api/core";
  import type { Game }                    from "../types";
  import { launchGame, killGame, notify } from "../stores";
  import { selectedGameId, removeGame }   from "../stores/games";

  // Convert a raw filesystem path to a Tauri asset:// URL for WKWebView
  function assetUrl(path: string | null): string | null {
    if (!path) return null;
    return convertFileSrc(path);
  }

  export let game:   Game;
  export let active: boolean = false;

  let launching  = false;
  let confirming = false;  // true while waiting for delete confirm
  let hovered    = false;

  $: needsSetup = !game.exe_path;
  $: isSelected = $selectedGameId === game.id;

  function formatPlaytime(secs: number): string {
    if (secs < 60)  return "< 1 min";
    const h = Math.floor(secs / 3600);
    const m = Math.floor((secs % 3600) / 60);
    return h > 0 ? `${h}h ${m}m` : `${m}m`;
  }

  async function handleLaunch(e: MouseEvent) {
    e.stopPropagation();
    if (needsSetup) return;
    launching = true;
    try {
      await launchGame(game.id);
    } catch { /* toast in store */ } finally {
      launching = false;
    }
  }

  async function handleKill(e: MouseEvent) {
    e.stopPropagation();
    try { await killGame(game.id); } catch { /* toast in store */ }
  }

  async function handleDelete(e: MouseEvent) {
    e.stopPropagation();
    if (!confirming) {
      // First press: show confirmation state for 2 s
      confirming = true;
      setTimeout(() => { confirming = false; }, 2000);
      return;
    }
    // Second press within 2 s: actually delete
    confirming = false;
    try {
      await removeGame(game.id);
      notify("info", `"${game.name}" removed from library`);
    } catch (err) {
      notify("error", `Remove failed: ${err}`);
    }
  }

  function selectGame() {
    selectedGameId.set(game.id);
  }

  function handleKeydown(e: KeyboardEvent) {
    if (e.key === "Enter" || e.key === " ") {
      e.preventDefault();
      selectGame();
    }
    if ((e.key === "Delete" || e.key === "Backspace") && isSelected) {
      e.preventDefault();
      // Simulate a delete click
      if (!confirming) {
        confirming = true;
        notify("warning", `Press Delete again to remove "${game.name}"`);
        setTimeout(() => { confirming = false; }, 2000);
      } else {
        confirming = false;
        removeGame(game.id).then(() => {
          notify("info", `"${game.name}" removed`);
        });
      }
    }
  }
</script>

<!-- svelte-ignore a11y-no-static-element-interactions -->
<div
  class="game-card"
  class:active
  class:selected={isSelected}
  class:needs-setup={needsSetup}
  on:click={selectGame}
  on:mouseenter={() => (hovered = true)}
  on:mouseleave={() => { hovered = false; confirming = false; }}
  on:keydown={handleKeydown}
  role="button"
  tabindex="0"
  aria-label="Select {game.name}"
  aria-pressed={isSelected}
>
  <!-- Cover area -->
  <div class="cover">
    {#if game.cover_art}
      <img src={assetUrl(game.cover_art)} alt="{game.name} cover" loading="lazy" />
    {:else}
      <div class="cover-placeholder">
        <span>{game.name[0]?.toUpperCase() ?? "?"}</span>
      </div>
    {/if}

    <!-- Source badge -->
    <span class="badge badge--source badge--{game.source}">
      {game.source === "steam" ? "Steam" : "Manual"}
    </span>

    <!-- Running pulse -->
    {#if active}
      <span class="badge badge--running">Running</span>
    {/if}

    <!-- Setup needed overlay -->
    {#if needsSetup && !active}
      <div class="setup-overlay">
        <span class="setup-text">Set .exe path</span>
      </div>
    {/if}

    <!-- Delete button — appears on hover -->
    {#if hovered || confirming}
      <button
        class="delete-btn"
        class:confirming
        on:click={handleDelete}
        aria-label="Remove {game.name} from library"
        title={confirming ? "Click again to confirm" : "Remove from library"}
      >
        {confirming ? "?" : "✕"}
      </button>
    {/if}
  </div>

  <!-- Name + playtime -->
  <div class="meta">
    <p class="name" title={game.name}>{game.name}</p>
    <p class="playtime">
      {#if needsSetup}
        <span class="setup-hint">Click to set up →</span>
      {:else}
        {formatPlaytime(game.playtime_secs)}
      {/if}
    </p>
  </div>

  <!-- Action button -->
  <div class="actions">
    {#if active}
      <button class="btn btn--stop" on:click={handleKill}>
        Stop
      </button>
    {:else if needsSetup}
      <button class="btn btn--setup" on:click={selectGame}>
        Set Up
      </button>
    {:else}
      <button
        class="btn btn--launch"
        on:click={handleLaunch}
        disabled={launching}
      >
        {launching ? "Launching…" : "Launch"}
      </button>
    {/if}
  </div>
</div>

<style>
  .game-card {
    display:        flex;
    flex-direction: column;
    border-radius:  10px;
    overflow:       hidden;
    background:     var(--color-surface, #1e1e2e);
    border:         1.5px solid transparent;
    cursor:         pointer;
    transition:     border-color 0.15s, transform 0.1s, box-shadow 0.15s;
    user-select:    none;
    outline:        none;
    position:       relative;
  }

  .game-card:hover,
  .game-card:focus-visible {
    border-color: var(--color-accent, #7f5af0);
    transform:    translateY(-2px);
    box-shadow:   0 6px 24px rgba(0,0,0,0.35);
  }

  .game-card.selected {
    border-color: var(--color-accent, #7f5af0);
    box-shadow:   0 0 0 2px var(--color-accent, #7f5af0);
  }

  .game-card.needs-setup {
    opacity: 0.8;
  }

  .game-card.needs-setup:hover {
    opacity: 1;
  }

  /* Cover */
  .cover {
    position:     relative;
    aspect-ratio: 2 / 3;
    background:   var(--color-surface-2, #2a2a3e);
    overflow:     hidden;
    flex-shrink:  0;
  }

  .cover img {
    width:      100%;
    height:     100%;
    object-fit: cover;
    display:    block;
  }

  .cover-placeholder {
    width:           100%;
    height:          100%;
    display:         flex;
    align-items:     center;
    justify-content: center;
    font-size:       3rem;
    font-weight:     700;
    color:           var(--color-muted, #555570);
    background:      linear-gradient(135deg, #1e1e2e, #2a2a3e);
  }

  /* Badges */
  .badge {
    position:       absolute;
    padding:        2px 7px;
    border-radius:  999px;
    font-size:      0.62rem;
    font-weight:    700;
    text-transform: uppercase;
    letter-spacing: 0.04em;
    backdrop-filter: blur(8px);
  }

  .badge--source { top: 6px; left: 6px; }
  .badge--steam  { background: rgba(23,93,155,0.85); color: #fff; }
  .badge--manual { background: rgba(40,40,60,0.85); color: #aaa; }

  .badge--running {
    top:       6px;
    right:     6px;
    background: #22c55e;
    color:     #fff;
    animation: pulse 2s ease-in-out infinite;
  }

  @keyframes pulse {
    0%, 100% { opacity: 1; }
    50%       { opacity: 0.6; }
  }

  /* Setup overlay */
  .setup-overlay {
    position:        absolute;
    inset:           0;
    background:      rgba(0,0,0,0.55);
    display:         flex;
    align-items:     center;
    justify-content: center;
    backdrop-filter: blur(2px);
  }

  .setup-text {
    font-size:      0.72rem;
    font-weight:    700;
    color:          #f59e0b;
    background:     rgba(245,158,11,0.15);
    border:         1px solid rgba(245,158,11,0.4);
    padding:        4px 10px;
    border-radius:  6px;
    text-transform: uppercase;
    letter-spacing: 0.05em;
  }

  /* Delete button */
  .delete-btn {
    position:        absolute;
    top:             5px;
    right:           5px;
    width:           22px;
    height:          22px;
    border-radius:   50%;
    border:          none;
    background:      rgba(220,38,38,0.85);
    color:           #fff;
    font-size:       0.7rem;
    font-weight:     700;
    cursor:          pointer;
    display:         flex;
    align-items:     center;
    justify-content: center;
    backdrop-filter: blur(4px);
    transition:      background 0.15s, transform 0.1s;
    z-index:         10;
    line-height:     1;
  }

  .delete-btn:hover {
    background: #ef4444;
    transform:  scale(1.1);
  }

  .delete-btn.confirming {
    background:  #f59e0b;
    animation:   confirm-pulse 0.4s ease-in-out infinite alternate;
  }

  @keyframes confirm-pulse {
    from { transform: scale(1); }
    to   { transform: scale(1.15); }
  }

  /* Metadata */
  .meta {
    padding: 7px 9px 3px;
    flex:    1;
  }

  .name {
    margin:        0;
    font-size:     0.83rem;
    font-weight:   600;
    white-space:   nowrap;
    overflow:      hidden;
    text-overflow: ellipsis;
    color:         var(--color-text, #e2e2f0);
  }

  .playtime {
    margin:    2px 0 0;
    font-size: 0.7rem;
    color:     var(--color-muted, #888899);
  }

  .setup-hint {
    color:      #f59e0b;
    font-size:  0.68rem;
    font-style: italic;
  }

  /* Action buttons */
  .actions { padding: 0 8px 8px; }

  .btn {
    width:         100%;
    padding:       6px 0;
    border:        none;
    border-radius: 6px;
    font-size:     0.78rem;
    font-weight:   600;
    cursor:        pointer;
    transition:    background 0.15s, opacity 0.15s;
  }

  .btn:disabled { opacity: 0.4; cursor: not-allowed; }

  .btn--launch { background: var(--color-accent, #7f5af0); color: #fff; }
  .btn--launch:hover:not(:disabled) { background: var(--color-accent-hover, #9d7ef5); }

  .btn--stop  { background: #dc2626; color: #fff; }
  .btn--stop:hover { background: #ef4444; }

  .btn--setup {
    background: rgba(245,158,11,0.15);
    color:      #f59e0b;
    border:     1px solid rgba(245,158,11,0.35);
  }
  .btn--setup:hover { background: rgba(245,158,11,0.25); }
</style>
