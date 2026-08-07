import { trace, SpanKind } from '@opentelemetry/api';
import { startInactiveSpan, SEMANTIC_ATTRIBUTE_SENTRY_OP, SEMANTIC_ATTRIBUTE_SENTRY_ORIGIN, startSpanManual } from '@sentry/core';

function setupOpenTelemetryTracer() {
  trace.disable();
  trace.setGlobalTracerProvider(new SentryDenoTraceProvider());
}
class SentryDenoTraceProvider {
  constructor() {
    this._tracers = /* @__PURE__ */ new Map();
  }
  getTracer(name, version, options) {
    const key = `${name}@${version || ""}:${options?.schemaUrl || ""}`;
    if (!this._tracers.has(key)) {
      this._tracers.set(key, new SentryDenoTracer());
    }
    return this._tracers.get(key);
  }
}
class SentryDenoTracer {
  startSpan(name, options) {
    const op = this._mapSpanKindToOp(options?.kind);
    return startInactiveSpan({
      ...options,
      name,
      attributes: {
        ...options?.attributes,
        [SEMANTIC_ATTRIBUTE_SENTRY_ORIGIN]: "manual",
        ...op ? { [SEMANTIC_ATTRIBUTE_SENTRY_OP]: op } : {},
        "sentry.deno_tracer": true
      }
    });
  }
  startActiveSpan(name, options, context, fn) {
    const opts = typeof options === "object" && options !== null ? options : {};
    const op = this._mapSpanKindToOp(opts.kind);
    const spanOpts = {
      ...opts,
      name,
      attributes: {
        ...opts.attributes,
        [SEMANTIC_ATTRIBUTE_SENTRY_ORIGIN]: "manual",
        ...op ? { [SEMANTIC_ATTRIBUTE_SENTRY_OP]: op } : {},
        "sentry.deno_tracer": true
      }
    };
    const callback = typeof options === "function" ? options : typeof context === "function" ? context : typeof fn === "function" ? fn : () => {
    };
    return startSpanManual(spanOpts, callback);
  }
  _mapSpanKindToOp(kind) {
    switch (kind) {
      case SpanKind.CLIENT:
        return "http.client";
      case SpanKind.SERVER:
        return "http.server";
      case SpanKind.PRODUCER:
        return "message.produce";
      case SpanKind.CONSUMER:
        return "message.consume";
      default:
        return void 0;
    }
  }
}

export { setupOpenTelemetryTracer };
//# sourceMappingURL=tracer.js.map
