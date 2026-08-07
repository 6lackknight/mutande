import type { RequestOptions } from 'node:http';
import type { HttpIncomingMessage, Integration, Span } from '@sentry/core';
export interface DenoHttpIntegrationOptions {
    /**
     * Whether breadcrumbs should be recorded for outgoing requests.
     *
     * @default `true`
     */
    breadcrumbs?: boolean;
    /**
     * Whether to create spans for incoming and outgoing HTTP requests.
     * Defaults to the client's tracing configuration (`hasSpansEnabled`).
     */
    spans?: boolean;
    /**
     * Whether to inject trace propagation headers (sentry-trace, baggage) into outgoing HTTP requests.
     *
     * When set to `false`, Sentry will not inject any trace propagation headers, but will still create breadcrumbs
     * (if `breadcrumbs` is enabled).
     *
     * @default `true`
     */
    tracePropagation?: boolean;
    /**
     * Whether to automatically ignore common static asset requests (favicon.ico, robots.txt, etc.)
     * when creating server spans.
     *
     * @default `true`
     */
    ignoreStaticAssets?: boolean;
    /**
     * Controls the maximum size of incoming HTTP request bodies attached to events.
     *
     * @default 'medium'
     */
    maxRequestBodySize?: 'none' | 'small' | 'medium' | 'always';
    /**
     * Do not capture the request body for incoming HTTP requests to URLs where the given callback returns `true`.
     *
     * The `request` parameter is the incoming `node:http` {@link IncomingMessage} — use `request.url`,
     * `request.method`, `request.headers`, etc.
     */
    ignoreRequestBody?: (url: string, request: HttpIncomingMessage) => boolean;
    /**
     * Do not capture server spans for incoming HTTP requests whose URL path makes the given callback return `true`.
     *
     * The `request` parameter is the incoming `node:http` {@link IncomingMessage} — use `request.url`,
     * `request.method`, `request.headers`, etc.
     */
    ignoreIncomingRequests?: (urlPath: string, request: HttpIncomingMessage) => boolean;
    /**
     * Do not capture breadcrumbs, spans, or propagate trace headers for outgoing HTTP requests where the given callback returns `true`.
     *
     * The `request` parameter is the outgoing {@link RequestOptions} — use `request.hostname`, `request.path`,
     * `request.method`, `request.headers`, etc.
     */
    ignoreOutgoingRequests?: (url: string, request: RequestOptions) => boolean;
    /**
     * Hook invoked after the server span is created but before the request is handled.
     */
    onIncomingSpanCreated?: (span: Span, request: unknown, response: unknown) => void;
    /**
     * Hook invoked when the server span ends, before it is recorded.
     */
    onIncomingSpanEnd?: (span: Span, request: unknown, response: unknown) => void;
}
/**
 * Instruments incoming and outgoing HTTP requests handled via the `node:http` module in Deno.
 *
 * Listens on Deno's `node:diagnostics_channel` for `http.server.request.start` and
 * `http.client.request.created`, then routes them through Sentry core's portable subscription
 * helpers (`getHttpServerSubscriptions`, `getHttpClientSubscriptions`) to create root server
 * spans, instrument client requests, and propagate distributed trace headers.
 *
 * For Deno-native `Deno.serve(...)` instrumentation, see {@link denoServeIntegration}.
 */
export declare const denoHttpIntegration: (options?: DenoHttpIntegrationOptions) => Integration & {
    name: "DenoHttp";
    setupOnce: () => void;
};
