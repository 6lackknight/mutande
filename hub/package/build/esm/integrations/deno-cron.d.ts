/**
 * Instruments Deno.cron to automatically capture cron check-ins.
 *
 * Enabled by default in the Deno SDK.
 *
 * ```js
 * Sentry.init({
 *   integrations: [
 *     Sentry.denoCronIntegration(),
 *   ],
 * })
 * ```
 */
export declare const denoCronIntegration: () => import("@sentry/core").Integration & {
    name: "DenoCron";
};
