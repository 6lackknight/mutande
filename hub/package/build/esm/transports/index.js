import { consoleSandbox, debug, createTransport, suppressTracing } from '@sentry/core';

function makeFetchTransport(options) {
  const url = new URL(options.url);
  Deno.permissions.query({ name: "net", host: url.host }).then(({ state }) => {
    if (state !== "granted") {
      consoleSandbox(() => {
        console.warn(`Sentry SDK requires 'net' permission to send events.
    Run with '--allow-net=${url.host}' to grant the required permissions.`);
      });
    }
  }).catch(() => {
    debug.warn('Failed to read the "net" permission.');
  });
  function makeRequest(request) {
    const requestOptions = {
      body: request.body,
      method: "POST",
      referrerPolicy: "strict-origin",
      headers: options.headers
    };
    try {
      return suppressTracing(() => {
        return fetch(options.url, requestOptions).then((response) => {
          return {
            statusCode: response.status,
            headers: {
              "x-sentry-rate-limits": response.headers.get("X-Sentry-Rate-Limits"),
              "retry-after": response.headers.get("Retry-After")
            }
          };
        });
      });
    } catch (e) {
      return Promise.reject(e);
    }
  }
  return createTransport(options, makeRequest);
}

export { makeFetchTransport };
//# sourceMappingURL=index.js.map
