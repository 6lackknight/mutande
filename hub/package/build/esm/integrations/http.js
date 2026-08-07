import { subscribe } from 'node:diagnostics_channel';
import { errorMonitor } from 'node:events';
import { defineIntegration, debug, getHttpServerSubscriptions, HTTP_ON_SERVER_REQUEST, getHttpClientSubscriptions, getRequestOptions, HTTP_ON_CLIENT_REQUEST } from '@sentry/core';
import { setAsyncLocalStorageAsyncContextStrategy } from '../async.js';
import { DENO_VERSION, HTTP_CLIENT_DIAGNOSTICS_CHANNEL_SUPPORTED, HTTP_SERVER_DIAGNOSTICS_CHANNEL_SUPPORTED } from '../denoVersion.js';

const INTEGRATION_NAME = "DenoHttp";
const _denoHttpIntegration = ((options = {}) => {
  const breadcrumbs = options.breadcrumbs ?? true;
  const tracePropagation = options.tracePropagation ?? true;
  return {
    name: INTEGRATION_NAME,
    setupOnce() {
      const denoVersion = DENO_VERSION.major !== void 0 ? `${Deno.version.deno}` : "unknown";
      if (!HTTP_CLIENT_DIAGNOSTICS_CHANNEL_SUPPORTED && !HTTP_SERVER_DIAGNOSTICS_CHANNEL_SUPPORTED) {
        debug.warn(
          `denoHttpIntegration requires Deno 2.7.13+ (client) or 2.8.0+ (server) for node:http diagnostics channels; running on Deno ${denoVersion}. The integration is a no-op on this version.`
        );
        return;
      }
      setAsyncLocalStorageAsyncContextStrategy();
      if (HTTP_SERVER_DIAGNOSTICS_CHANNEL_SUPPORTED) {
        const { [HTTP_ON_SERVER_REQUEST]: onHttpServerRequest } = getHttpServerSubscriptions({
          // `spans` falls through to the client's tracing config when unset.
          spans: options.spans,
          ignoreStaticAssets: options.ignoreStaticAssets,
          ignoreIncomingRequests: options.ignoreIncomingRequests,
          maxRequestBodySize: options.maxRequestBodySize ?? "medium",
          ignoreRequestBody: options.ignoreRequestBody,
          onSpanCreated: options.onIncomingSpanCreated,
          onSpanEnd: options.onIncomingSpanEnd,
          errorMonitor,
          sessions: false
        });
        subscribe(HTTP_ON_SERVER_REQUEST, onHttpServerRequest);
      } else {
        debug.log(
          `denoHttpIntegration: server-side instrumentation requires Deno 2.8.0+; running on Deno ${denoVersion}. Client-side instrumentation is still active.`
        );
      }
      if (HTTP_CLIENT_DIAGNOSTICS_CHANNEL_SUPPORTED) {
        const { [HTTP_ON_CLIENT_REQUEST]: onHttpClientRequest } = getHttpClientSubscriptions({
          spans: options.spans,
          breadcrumbs,
          propagateTrace: tracePropagation,
          ignoreOutgoingRequests: options.ignoreOutgoingRequests ? (url, request) => options.ignoreOutgoingRequests(url, getRequestOptions(request)) : void 0,
          // Deno doesn't run OTel's http instrumentation, so there's no
          // double-wrap to detect; skip the warning to avoid loading the module.
          suppressOtelWarning: true,
          errorMonitor
        });
        subscribe(HTTP_ON_CLIENT_REQUEST, onHttpClientRequest);
      }
    }
  };
});
const denoHttpIntegration = defineIntegration(_denoHttpIntegration);

export { denoHttpIntegration };
//# sourceMappingURL=http.js.map
