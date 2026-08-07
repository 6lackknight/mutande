export declare const DENO_VERSION: {
    major: number | undefined;
    minor: number | undefined;
    patch: number | undefined;
};
/** Whether `http.client.request.created` fires (Deno 2.7.13+). */
export declare const HTTP_CLIENT_DIAGNOSTICS_CHANNEL_SUPPORTED: boolean;
/** Whether `http.server.request.start` fires (Deno 2.8.0+). */
export declare const HTTP_SERVER_DIAGNOSTICS_CHANNEL_SUPPORTED: boolean;
/** Whether `node:diagnostics_channel.tracingChannel` exists (Deno 1.44.3+). */
export declare const TRACING_CHANNEL_SUPPORTED: boolean;
/**
 * Whether `Module.registerHooks` is available (Deno 2.8.0+), which the
 * orchestrion runtime hook (`@sentry/deno/import`) needs to transform libraries
 * like `mysql` so they publish to their tracing channels.
 */
export declare const MODULE_REGISTER_HOOKS_SUPPORTED: boolean;
