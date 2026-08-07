interface BreadcrumbsOptions {
    console: boolean;
    fetch: boolean;
    sentry: boolean;
}
/**
 * Adds a breadcrumbs for console, fetch, and sentry events.
 *
 * Enabled by default in the Deno SDK.
 *
 * ```js
 * Sentry.init({
 *   integrations: [
 *     Sentry.breadcrumbsIntegration(),
 *   ],
 * })
 * ```
 */
export declare const breadcrumbsIntegration: (options?: Partial<BreadcrumbsOptions> | undefined) => import("@sentry/core").Integration & {
    name: "Breadcrumbs";
};
export {};
