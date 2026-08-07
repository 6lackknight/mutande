type GlobalHandlersIntegrationsOptionKeys = 'error' | 'unhandledrejection';
type GlobalHandlersIntegrations = Record<GlobalHandlersIntegrationsOptionKeys, boolean>;
/**
 * Instruments global `error` and `unhandledrejection` listeners in Deno.
 *
 * Enabled by default in the Deno SDK.
 *
 * ```js
 * Sentry.init({
 *   integrations: [
 *     Sentry.globalHandlersIntegration(),
 *   ],
 * })
 * ```
 */
export declare const globalHandlersIntegration: (options?: GlobalHandlersIntegrations | undefined) => import("@sentry/core").Integration & {
    name: "GlobalHandlers";
};
export {};
