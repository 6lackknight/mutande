import { ServerRuntimeClient } from '@sentry/core';
import type { DenoClientOptions } from './types';
/**
 * The Sentry Deno SDK Client.
 *
 * @see DenoClientOptions for documentation on configuration options.
 * @see SentryClient for usage documentation.
 */
export declare class DenoClient extends ServerRuntimeClient<DenoClientOptions> {
    private _logOnExitFlushListener;
    /**
     * Creates a new Deno SDK instance.
     * @param options Configuration options for this SDK.
     */
    constructor(options: DenoClientOptions);
    /** @inheritDoc */
    close(timeout?: number | undefined): PromiseLike<boolean>;
}
