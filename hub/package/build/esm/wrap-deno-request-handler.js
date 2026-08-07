import { withIsolationScope, getClient, captureException, parseStringToURLObject, getHttpSpanDetailsFromUrlObject, httpHeadersToSpanAttributes, winterCGHeadersToDict, SEMANTIC_ATTRIBUTE_SENTRY_OP, winterCGRequestToRequestData, continueTrace, startSpanManual, setHttpStatus } from '@sentry/core';
import { streamResponse } from './utils/streaming.js';

const assignIfSet = (obj, key, value) => {
  if (value !== void 0 && value !== null) obj[key] = value;
};
const wrapDenoRequestHandler = (wrapperOptions, handler) => {
  return withIsolationScope(async (isolationScope) => {
    const { request, info } = wrapperOptions;
    const client = getClient();
    if (!client) {
      throw new Error("could not get Deno client. Did you run Sentry.init?");
    }
    isolationScope.setClient(client);
    if (request.method === "OPTIONS" || request.method === "HEAD") {
      try {
        return await handler();
      } catch (e) {
        captureException(e, {
          mechanism: {
            handled: false,
            type: "auto.http.deno",
            data: { function: "serve" }
          }
        });
        throw e;
      }
    }
    const urlObject = parseStringToURLObject(request.url);
    const [name, attributes] = getHttpSpanDetailsFromUrlObject(urlObject, "server", "auto.http.deno", request);
    const contentLength = request.headers.get("content-length");
    assignIfSet(attributes, "http.request.body.size", contentLength && parseInt(contentLength, 10));
    assignIfSet(attributes, "user_agent.original", request.headers.get("user-agent"));
    const dataCollection = client.getDataCollectionOptions();
    if (dataCollection.userInfo) {
      assignIfSet(
        attributes,
        "client.address",
        info?.remoteAddr?.hostname ?? info?.remoteAddr?.path
      );
      assignIfSet(attributes, "client.port", info?.remoteAddr?.port);
    }
    Object.assign(attributes, httpHeadersToSpanAttributes(winterCGHeadersToDict(request.headers), dataCollection));
    attributes[SEMANTIC_ATTRIBUTE_SENTRY_OP] = "http.server";
    isolationScope.setSDKProcessingMetadata({
      normalizedRequest: winterCGRequestToRequestData(request)
    });
    return continueTrace(
      {
        sentryTrace: request.headers.get("sentry-trace") || "",
        baggage: request.headers.get("baggage")
      },
      () => {
        return startSpanManual({ name, attributes }, async (span) => {
          let res;
          try {
            res = await handler();
            setHttpStatus(span, res.status);
            isolationScope.setContext("response", {
              status_code: res.status
            });
            span.setAttributes(
              httpHeadersToSpanAttributes(Object.fromEntries(res.headers), dataCollection, "response")
            );
          } catch (e) {
            span.end();
            captureException(e, {
              mechanism: {
                handled: false,
                type: "auto.http.deno",
                data: { function: "serve" }
              }
            });
            throw e;
          }
          return streamResponse(span, res);
        });
      }
    );
  });
};

export { wrapDenoRequestHandler };
//# sourceMappingURL=wrap-deno-request-handler.js.map
