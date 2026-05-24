import { defineConfig } from "vite";
import { svelte }       from "@sveltejs/vite-plugin-svelte";
import path             from "node:path";

// https://vitejs.dev/config/
export default defineConfig({
  plugins: [svelte()],

  // Dev server port must match tauri.conf.json → build.devUrl
  server: {
    port:       5173,
    strictPort: true,
    host:       "localhost",
  },

  // $lib alias — mirrors SvelteKit convention without requiring SvelteKit.
  // Components import from "$lib/..." and TS resolves via tsconfig paths too.
  resolve: {
    alias: {
      "$lib": path.resolve(__dirname, "src/lib"),
    },
  },

  // Keep Vite errors readable inside the Tauri window
  clearScreen: false,

  envPrefix: ["VITE_", "TAURI_"],

  build: {
    // WKWebView on macOS 14+ is fully evergreen
    target:    "esnext",
    outDir:    "dist",
    minify:    "esbuild",
    sourcemap: false,
  },
});
