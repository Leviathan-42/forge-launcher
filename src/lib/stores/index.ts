/**
 * stores/index.ts
 *
 * Re-exports every store and action so components can import from a single
 * path:
 *
 *   import { games, launchGame, appConfig } from "../stores";
 */

export * from "./games";
export * from "./launcher";
export * from "./config";
