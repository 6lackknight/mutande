import { defineIntegration, safeSetSpanJSONAttributes } from '@sentry/core';

const INTEGRATION_NAME = "DenoContext";
function getOSName() {
  switch (Deno.build.os) {
    case "darwin":
      return "macOS";
    case "linux":
      return "Linux";
    case "windows":
      return "Windows";
    default:
      return Deno.build.os;
  }
}
async function getOSRelease() {
  return (await Deno.permissions.query({ name: "sys", kind: "osRelease" })).state === "granted" ? Deno.osRelease() : void 0;
}
const _denoContextIntegration = (() => {
  const appStartTime = new Date(Date.now() - performance.now()).toISOString();
  const osName = getOSName();
  const arch = Deno.build.arch;
  const processorCount = navigator.hardwareConcurrency;
  const v8Version = Deno.version.v8;
  const tsVersion = Deno.version.typescript;
  const cachedContext = {
    app: { app_start_time: appStartTime },
    device: { arch, processor_count: processorCount },
    os: { name: osName },
    v8: { name: "v8", version: v8Version },
    typescript: { name: "TypeScript", version: tsVersion }
  };
  const cachedSpanAttributes = {
    "app.start_time": appStartTime,
    // Convention uses 'device.archs' (string[]), but array attributes are not yet serialized.
    // Once array serialization lands, this will start appearing on spans automatically.
    "device.archs": [arch],
    "device.processor_count": processorCount,
    "os.name": osName,
    "process.runtime.engine.name": "v8",
    "process.runtime.engine.version": v8Version
  };
  getOSRelease().then((release) => {
    cachedContext.os.version = release;
    cachedSpanAttributes["os.version"] = release;
  }).catch(() => {
  });
  return {
    name: INTEGRATION_NAME,
    processEvent(event) {
      event.contexts = {
        ...cachedContext,
        ...event.contexts
      };
      return event;
    },
    processSegmentSpan(span) {
      safeSetSpanJSONAttributes(span, cachedSpanAttributes);
    }
  };
});
const denoContextIntegration = defineIntegration(_denoContextIntegration);

export { denoContextIntegration };
//# sourceMappingURL=context.js.map
