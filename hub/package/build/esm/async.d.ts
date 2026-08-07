/**
 * Sets the async context strategy to use AsyncLocalStorage.
 *
 * Idempotent: multiple integrations each call this from their `setupOnce`,
 * but they must all share a single `AsyncLocalStorage` so context propagates
 * between them. The first call wins, later calls are no-ops. This prevents
 * orphaning an in-flight context if an integration is set up asynchronously.
 *
 * @internal Only exported to be used in higher-level Sentry packages
 * @hidden Only exported to be used in higher-level Sentry packages
 */
export declare function setAsyncLocalStorageAsyncContextStrategy(): void;
