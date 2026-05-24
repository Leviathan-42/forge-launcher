import { vitePreprocess } from "@sveltejs/vite-plugin-svelte";

/** @type {import('@sveltejs/vite-plugin-svelte').SvelteConfig} */
export default {
  // Enables TypeScript, PostCSS, etc. inside <script> and <style> blocks
  preprocess: vitePreprocess(),

  compilerOptions: {
    // Use Svelte 5 runes mode
    runes: false,
  },
};
