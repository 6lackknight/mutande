import { defineIntegration, getClient, eventFromUnknownInput, captureEvent, flush, isPrimitive } from '@sentry/core';

const INTEGRATION_NAME = "GlobalHandlers";
let isExiting = false;
const _globalHandlersIntegration = ((options) => {
  const _options = {
    error: true,
    unhandledrejection: true,
    ...options
  };
  return {
    name: INTEGRATION_NAME,
    setup(client) {
      if (_options.error) {
        installGlobalErrorHandler(client);
      }
      if (_options.unhandledrejection) {
        installGlobalUnhandledRejectionHandler(client);
      }
    }
  };
});
const globalHandlersIntegration = defineIntegration(_globalHandlersIntegration);
function installGlobalErrorHandler(client) {
  globalThis.addEventListener("error", (data) => {
    if (getClient() !== client || isExiting) {
      return;
    }
    const stackParser = getStackParser();
    const { message, error } = data;
    const event = eventFromUnknownInput(client, stackParser, error || message);
    event.level = "fatal";
    captureEvent(event, {
      originalException: error,
      mechanism: {
        handled: false,
        type: "auto.deno.global_handlers.error"
      }
    });
    data.preventDefault();
    isExiting = true;
    flush().then(
      () => {
        throw error;
      },
      () => {
        throw error;
      }
    );
  });
}
function installGlobalUnhandledRejectionHandler(client) {
  globalThis.addEventListener("unhandledrejection", (e) => {
    if (getClient() !== client || isExiting) {
      return;
    }
    const stackParser = getStackParser();
    let error = e;
    try {
      if ("reason" in e) {
        error = e.reason;
      }
    } catch {
    }
    const event = isPrimitive(error) ? eventFromRejectionWithPrimitive(error) : eventFromUnknownInput(client, stackParser, error, void 0);
    event.level = "fatal";
    captureEvent(event, {
      originalException: error,
      mechanism: {
        handled: false,
        type: "auto.deno.global_handlers.unhandledrejection"
      }
    });
    e.preventDefault();
    isExiting = true;
    flush().then(
      () => {
        throw error;
      },
      () => {
        throw error;
      }
    );
  });
}
function eventFromRejectionWithPrimitive(reason) {
  return {
    exception: {
      values: [
        {
          type: "UnhandledRejection",
          // String() is needed because the Primitive type includes symbols (which can't be automatically stringified)
          value: `Non-Error promise rejection captured with value: ${String(reason)}`
        }
      ]
    }
  };
}
function getStackParser() {
  const client = getClient();
  if (!client) {
    return () => [];
  }
  return client.getOptions().stackParser;
}

export { globalHandlersIntegration };
//# sourceMappingURL=globalhandlers.js.map
