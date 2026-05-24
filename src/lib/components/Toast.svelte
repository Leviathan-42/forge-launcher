<!--
  Toast.svelte

  Renders the notification queue from the launcher store.
  Mount once at the root of App.svelte — it manages its own positioning.
-->

<script lang="ts">
  import { notifications, dismiss } from "../stores/launcher";

  const iconMap: Record<string, string> = {
    info:    "ℹ",
    success: "✓",
    warning: "⚠",
    error:   "✕",
  };
</script>

<div class="toast-container" aria-live="polite" aria-atomic="false">
  {#each $notifications as toast (toast.id)}
    <div class="toast toast--{toast.type}" role="alert">
      <span class="toast-icon" aria-hidden="true">{iconMap[toast.type]}</span>
      <span class="toast-msg">{toast.message}</span>
      <button
        class="toast-close"
        on:click={() => dismiss(toast.id)}
        aria-label="Dismiss"
      >✕</button>
    </div>
  {/each}
</div>

<style>
  .toast-container {
    position:       fixed;
    bottom:         24px;
    right:          24px;
    display:        flex;
    flex-direction: column;
    gap:            10px;
    z-index:        9999;
    pointer-events: none;
  }

  .toast {
    display:         flex;
    align-items:     center;
    gap:             10px;
    padding:         12px 16px;
    border-radius:   10px;
    min-width:       280px;
    max-width:       420px;
    font-size:       0.85rem;
    font-weight:     500;
    pointer-events:  all;
    animation:       slide-in 0.2s ease;
    box-shadow:      0 4px 20px rgba(0,0,0,0.3);
    backdrop-filter: blur(12px);
  }

  @keyframes slide-in {
    from { transform: translateX(100%); opacity: 0; }
    to   { transform: translateX(0);    opacity: 1; }
  }

  .toast--info    { background: rgba(59,130,246,0.9);  color: #fff; }
  .toast--success { background: rgba(34,197,94,0.9);   color: #fff; }
  .toast--warning { background: rgba(234,179,8,0.9);   color: #000; }
  .toast--error   { background: rgba(220,38,38,0.9);   color: #fff; }

  .toast-icon  { font-weight: 700; flex-shrink: 0; }
  .toast-msg   { flex: 1; }

  .toast-close {
    background:    transparent;
    border:        none;
    color:         inherit;
    opacity:       0.7;
    cursor:        pointer;
    font-size:     0.8rem;
    padding:       0 4px;
    flex-shrink:   0;
    transition:    opacity 0.15s;
  }

  .toast-close:hover { opacity: 1; }
</style>
