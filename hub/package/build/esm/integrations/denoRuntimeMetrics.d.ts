export interface DenoRuntimeMetricsOptions {
    /**
     * Which metrics to collect.
     *
     * Default on (4 metrics):
     * - `memRss` — Resident Set Size (actual memory footprint)
     * - `memHeapUsed` — V8 heap currently in use
     * - `memHeapTotal` — total V8 heap allocated
     * - `uptime` — process uptime (detect restarts/crashes)
     *
     * Default off (opt-in):
     * - `memExternal` — external memory (JS objects outside the V8 isolate)
     *
     * Note: CPU utilization and event loop metrics are not available in Deno.
     */
    collect?: {
        memRss?: boolean;
        memHeapUsed?: boolean;
        memHeapTotal?: boolean;
        memExternal?: boolean;
        uptime?: boolean;
    };
    /**
     * How often to collect metrics, in milliseconds.
     * Minimum allowed value is 1000ms.
     * @default 30000
     * @minimum 1000
     */
    collectionIntervalMs?: number;
}
/**
 * Automatically collects Deno runtime metrics and emits them to Sentry.
 *
 * @example
 * ```ts
 * Sentry.init({
 *   integrations: [
 *     Sentry.denoRuntimeMetricsIntegration(),
 *   ],
 * });
 * ```
 */
export declare const denoRuntimeMetricsIntegration: (options?: DenoRuntimeMetricsOptions | undefined) => import("@sentry/core").Integration & {
    name: "DenoRuntimeMetrics";
};
