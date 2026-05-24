/**
 * main.ts — Svelte app entry point.
 *
 * Mounts the root App component into the <body>.
 * Tauri's webview injects `window.__TAURI_INTERNALS__` before this runs,
 * so all `invoke` calls in stores are safe to make from onMount onwards.
 */

import { mount } from "svelte";
import App       from "./App.svelte";

const app = mount(App, { target: document.getElementById("app")! });

export default app;
