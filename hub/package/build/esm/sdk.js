import { createStackParser, nodeStackLineParser, inboundFiltersIntegration, requestDataIntegration, functionToStringIntegration, linkedErrorsIntegration, dedupeIntegration, getIntegrationsToSetup, stackParserFromStackParserOptions, initAndBind } from '@sentry/core';
import { DenoClient } from './client.js';
import { breadcrumbsIntegration } from './integrations/breadcrumbs.js';
import { denoContextIntegration } from './integrations/context.js';
import { contextLinesIntegration } from './integrations/contextlines.js';
import { HTTP_CLIENT_DIAGNOSTICS_CHANNEL_SUPPORTED, HTTP_SERVER_DIAGNOSTICS_CHANNEL_SUPPORTED, TRACING_CHANNEL_SUPPORTED, MODULE_REGISTER_HOOKS_SUPPORTED } from './denoVersion.js';
import { denoServeIntegration } from './integrations/deno-serve.js';
import { denoHttpIntegration } from './integrations/http.js';
import { denoAmqplibIntegration } from './integrations/amqplib.js';
import { denoKoaIntegration } from './integrations/koa.js';
import { denoMongoIntegration } from './integrations/mongo.js';
import { denoMongooseIntegration } from './integrations/mongoose.js';
import { denoMysqlIntegration } from './integrations/mysql.js';
import { denoPostgresIntegration } from './integrations/postgres.js';
import { denoRedisIntegration } from './integrations/redis.js';
import { globalHandlersIntegration } from './integrations/globalhandlers.js';
import { normalizePathsIntegration } from './integrations/normalizepaths.js';
import { setupOpenTelemetryTracer } from './opentelemetry/tracer.js';
import { makeFetchTransport } from './transports/index.js';

function getDefaultIntegrations(_options) {
  return [
    // Common
    // TODO(v11): Replace with `eventFiltersIntegration` once we remove the deprecated `inboundFiltersIntegration`
    // eslint-disable-next-line typescript/no-deprecated
    inboundFiltersIntegration(),
    requestDataIntegration(),
    functionToStringIntegration(),
    linkedErrorsIntegration(),
    dedupeIntegration(),
    // Deno Specific
    breadcrumbsIntegration(),
    denoContextIntegration(),
    denoServeIntegration(),
    // node:http client diagnostics channels fire on Deno 2.7.13+
    // server channels arrive at 2.8.0+
    // Include in defaults if at least one is available
    ...HTTP_CLIENT_DIAGNOSTICS_CHANNEL_SUPPORTED || HTTP_SERVER_DIAGNOSTICS_CHANNEL_SUPPORTED ? [denoHttpIntegration()] : [],
    // node:diagnostics_channel.tracingChannel exists on Deno 1.44.3+.
    ...TRACING_CHANNEL_SUPPORTED ? [denoRedisIntegration()] : [],
    // orchestrion-based instrumentations.
    // It's possible that the orchestrion channels will be injected AFTER
    // (or in parallel to) loading the SDK, so we only gate on whether the
    // feature is possible. If they're never loaded, it'll just be a no-op.
    ...MODULE_REGISTER_HOOKS_SUPPORTED ? [
      denoAmqplibIntegration(),
      denoKoaIntegration(),
      denoMongoIntegration(),
      denoMongooseIntegration(),
      denoMysqlIntegration(),
      denoPostgresIntegration()
    ] : [],
    contextLinesIntegration(),
    normalizePathsIntegration(),
    globalHandlersIntegration()
  ];
}
const defaultStackParser = createStackParser(nodeStackLineParser());
function init(options = {}) {
  if (options.defaultIntegrations === void 0) {
    options.defaultIntegrations = getDefaultIntegrations();
  }
  const clientOptions = {
    ...options,
    stackParser: stackParserFromStackParserOptions(options.stackParser || defaultStackParser),
    integrations: getIntegrationsToSetup(options),
    transport: options.transport || makeFetchTransport
  };
  const client = initAndBind(DenoClient, clientOptions);
  if (!options.skipOpenTelemetrySetup) {
    setupOpenTelemetryTracer();
  }
  return client;
}

export { getDefaultIntegrations, init };
//# sourceMappingURL=sdk.js.map
