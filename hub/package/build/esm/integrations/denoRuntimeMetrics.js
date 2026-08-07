import { defineIntegration, _INTERNAL_safeDateNow, metrics } from '@sentry/core';

const INTEGRATION_NAME = "DenoRuntimeMetrics";
const DEFAULT_INTERVAL_MS = 3e4;
const MIN_INTERVAL_MS = 1e3;
const denoRuntimeMetricsIntegration = defineIntegration((options = {}) => {
  const rawInterval = options.collectionIntervalMs ?? DEFAULT_INTERVAL_MS;
  let collectionIntervalMs;
  if (!Number.isFinite(rawInterval)) {
    console.warn(
      `[Sentry] denoRuntimeMetricsIntegration: collectionIntervalMs (${rawInterval}) is invalid. Using default of ${DEFAULT_INTERVAL_MS}ms.`
    );
    collectionIntervalMs = DEFAULT_INTERVAL_MS;
  } else if (rawInterval < MIN_INTERVAL_MS) {
    console.warn(
      `[Sentry] denoRuntimeMetricsIntegration: collectionIntervalMs (${rawInterval}) is below the minimum of ${MIN_INTERVAL_MS}ms. Using minimum of ${MIN_INTERVAL_MS}ms.`
    );
    collectionIntervalMs = MIN_INTERVAL_MS;
  } else {
    collectionIntervalMs = rawInterval;
  }
  const collect = {
    // Default on
    memRss: true,
    memHeapUsed: true,
    memHeapTotal: true,
    uptime: true,
    // Default off
    memExternal: false,
    ...options.collect
  };
  let intervalId;
  let prevFlushTime = 0;
  const METRIC_ATTRIBUTES_BYTE = { unit: "byte", attributes: { "sentry.origin": "auto.deno.runtime_metrics" } };
  const METRIC_ATTRIBUTES_SECOND = { unit: "second", attributes: { "sentry.origin": "auto.deno.runtime_metrics" } };
  function collectMetrics() {
    const now = _INTERNAL_safeDateNow();
    const elapsed = now - prevFlushTime;
    if (collect.memRss || collect.memHeapUsed || collect.memHeapTotal || collect.memExternal) {
      const mem = Deno.memoryUsage();
      if (collect.memRss) {
        metrics.gauge("deno.runtime.mem.rss", mem.rss, METRIC_ATTRIBUTES_BYTE);
      }
      if (collect.memHeapUsed) {
        metrics.gauge("deno.runtime.mem.heap_used", mem.heapUsed, METRIC_ATTRIBUTES_BYTE);
      }
      if (collect.memHeapTotal) {
        metrics.gauge("deno.runtime.mem.heap_total", mem.heapTotal, METRIC_ATTRIBUTES_BYTE);
      }
      if (collect.memExternal) {
        metrics.gauge("deno.runtime.mem.external", mem.external, METRIC_ATTRIBUTES_BYTE);
      }
    }
    if (collect.uptime && elapsed > 0) {
      metrics.count("deno.runtime.process.uptime", elapsed / 1e3, METRIC_ATTRIBUTES_SECOND);
    }
    prevFlushTime = now;
  }
  return {
    name: INTEGRATION_NAME,
    setup() {
      prevFlushTime = _INTERNAL_safeDateNow();
      if (intervalId) {
        clearInterval(intervalId);
      }
      intervalId = setInterval(collectMetrics, collectionIntervalMs);
      Deno.unrefTimer(intervalId);
    },
    teardown() {
      if (intervalId) {
        clearInterval(intervalId);
        intervalId = void 0;
      }
    }
  };
});

export { denoRuntimeMetricsIntegration };
//# sourceMappingURL=denoRuntimeMetrics.js.map
