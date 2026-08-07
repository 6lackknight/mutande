import type { Span } from '@sentry/core';
export type StreamingGuess = {
    isStreaming: boolean;
};
/**
 * Classifies a Response as streaming or non-streaming.
 *
 * Heuristics:
 * - No body → not streaming
 * - Known streaming Content-Types → streaming (SSE, NDJSON, JSON streaming)
 * - text/plain without Content-Length → streaming (some AI APIs)
 * - Otherwise → not streaming (conservative default, including HTML/SSR)
 *
 * We avoid probing the stream to prevent blocking on transform streams (like injectTraceMetaTags)
 * or SSR streams that may not have data ready immediately.
 */
export declare function classifyResponseStreaming(res: Response): StreamingGuess;
/**
 * Tee a stream, and end the provided span when the stream ends.
 * Returns the other side of the tee, which can be used to send the
 * response to a client.
 */
export declare function streamResponse(span: Span, res: Response): Promise<Response>;
