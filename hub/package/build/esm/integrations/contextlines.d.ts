/**
 * Resets the file cache. Exists for testing purposes.
 * @hidden
 */
export declare function resetFileContentCache(): void;
interface ContextLinesOptions {
    /**
     * Sets the number of context lines for each frame when loading a file.
     * Defaults to 7.
     *
     * Set to 0 to disable loading and inclusion of source files.
     *
     * When set, this option takes precedence over `dataCollection.frameContextLines`.
     **/
    frameContextLines?: number;
}
/**
 * Adds source context to event stacktraces.
 *
 * Enabled by default in the Deno SDK.
 *
 * ```js
 * Sentry.init({
 *   integrations: [
 *     Sentry.contextLinesIntegration(),
 *   ],
 * })
 * ```
 */
export declare const contextLinesIntegration: (options?: ContextLinesOptions | undefined) => import("@sentry/core").Integration & {
    name: "ContextLines";
};
export {};
