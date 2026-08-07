import { defineIntegration, addConsoleInstrumentationHandler, addFetchInstrumentationHandler, getClient, safeJoin, severityLevelFromString, addBreadcrumb, getBreadcrumbLogLevelFromHttpStatusCode, getEventDescription } from '@sentry/core';

const INTEGRATION_NAME = "Breadcrumbs";
const _breadcrumbsIntegration = ((options = {}) => {
  const _options = {
    console: true,
    fetch: true,
    sentry: true,
    ...options
  };
  return {
    name: INTEGRATION_NAME,
    setup(client) {
      if (_options.console) {
        addConsoleInstrumentationHandler(_getConsoleBreadcrumbHandler(client));
      }
      if (_options.fetch) {
        addFetchInstrumentationHandler(_getFetchBreadcrumbHandler(client));
      }
      if (_options.sentry) {
        client.on("beforeSendEvent", _getSentryBreadcrumbHandler(client));
      }
    }
  };
});
const breadcrumbsIntegration = defineIntegration(_breadcrumbsIntegration);
function _getSentryBreadcrumbHandler(client) {
  return function addSentryBreadcrumb(event) {
    if (getClient() !== client) {
      return;
    }
    addBreadcrumb(
      {
        category: `sentry.${event.type === "transaction" ? "transaction" : "event"}`,
        event_id: event.event_id,
        level: event.level,
        message: getEventDescription(event)
      },
      {
        event
      }
    );
  };
}
function _getConsoleBreadcrumbHandler(client) {
  return function _consoleBreadcrumb(handlerData) {
    if (getClient() !== client) {
      return;
    }
    const breadcrumb = {
      category: "console",
      data: {
        arguments: handlerData.args,
        logger: "console"
      },
      level: severityLevelFromString(handlerData.level),
      message: safeJoin(handlerData.args, " ")
    };
    if (handlerData.level === "assert") {
      if (handlerData.args[0] === false) {
        breadcrumb.message = `Assertion failed: ${safeJoin(handlerData.args.slice(1), " ") || "console.assert"}`;
        breadcrumb.data.arguments = handlerData.args.slice(1);
      } else {
        return;
      }
    }
    addBreadcrumb(breadcrumb, {
      input: handlerData.args,
      level: handlerData.level
    });
  };
}
function _getFetchBreadcrumbHandler(client) {
  return function _fetchBreadcrumb(handlerData) {
    if (getClient() !== client) {
      return;
    }
    const { startTimestamp, endTimestamp } = handlerData;
    if (!endTimestamp) {
      return;
    }
    if (handlerData.fetchData.url.match(/sentry_key/) && handlerData.fetchData.method === "POST") {
      return;
    }
    const breadcrumbData = {
      method: handlerData.fetchData.method,
      url: handlerData.fetchData.url
    };
    if (handlerData.error) {
      const hint = {
        data: handlerData.error,
        input: handlerData.args,
        startTimestamp,
        endTimestamp
      };
      addBreadcrumb(
        {
          category: "fetch",
          data: breadcrumbData,
          level: "error",
          type: "http"
        },
        hint
      );
    } else {
      const response = handlerData.response;
      breadcrumbData.request_body_size = handlerData.fetchData.request_body_size;
      breadcrumbData.response_body_size = handlerData.fetchData.response_body_size;
      breadcrumbData.status_code = response?.status;
      const hint = {
        input: handlerData.args,
        response,
        startTimestamp,
        endTimestamp
      };
      const level = getBreadcrumbLogLevelFromHttpStatusCode(breadcrumbData.status_code);
      addBreadcrumb(
        {
          category: "fetch",
          data: breadcrumbData,
          type: "http",
          level
        },
        hint
      );
    }
  };
}

export { breadcrumbsIntegration };
//# sourceMappingURL=breadcrumbs.js.map
