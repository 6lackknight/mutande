interface DenoPostgresIntegrationOptions {
    /** Whether to skip creating spans for `pg`/`pg-pool` connections. Defaults to `false`. */
    ignoreConnectSpans?: boolean;
}
export declare const denoPostgresIntegration: (options?: DenoPostgresIntegrationOptions | undefined) => import("@sentry/core").Integration & {
    name: "DenoPostgres";
};
export {};
