/**
 * Adds Deno related context to events. This includes contexts about app, device, os, v8, and TypeScript.
 *
 * Enabled by default in the Deno SDK.
 *
 * ```js
 * Sentry.init({
 *   integrations: [
 *     Sentry.denoContextIntegration(),
 *   ],
 * })
 * ```
 */
export declare const denoContextIntegration: () => import("@sentry/core").Integration & {
    name: "DenoContext";
};
