import type { RedisDiagnosticChannelResponseHook } from '@sentry/server-utils';
import type { Integration } from '@sentry/core';
export interface DenoRedisIntegrationOptions {
    /**
     * Optional hook invoked once the redis command response arrives. Useful for
     * attaching response-derived attributes (e.g. cache hit/miss, payload size).
     */
    responseHook?: RedisDiagnosticChannelResponseHook;
}
/**
 * Creates spans for redis commands, batches, and connects under Deno via
 * `node:diagnostics_channel`. Subscribes to both node-redis (>= 5.12.0) and
 * ioredis (>= 5.11.0) channels — both libraries publish to dedicated channels
 * once they're new enough; on older releases the subscribers are inert.
 */
export declare const denoRedisIntegration: (options?: DenoRedisIntegrationOptions) => Integration & {
    name: "DenoRedis";
    setupOnce: () => void;
};
