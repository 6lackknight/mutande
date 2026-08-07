/**
 * Normalises paths to the app root directory.
 *
 * Enabled by default in the Deno SDK.
 *
 * ```js
 * Sentry.init({
 *   integrations: [
 *     Sentry.normalizePathsIntegration(),
 *   ],
 * })
 * ```
 */
export declare const normalizePathsIntegration: () => import("@sentry/core").Integration & {
    name: "NormalizePaths";
};
