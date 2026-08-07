import { defineIntegration, createStackParser, nodeStackLineParser, dirname } from '@sentry/core';

const INTEGRATION_NAME = "NormalizePaths";
function appRootFromErrorStack(error) {
  const frames = createStackParser(nodeStackLineParser())(error.stack || "");
  const paths = frames.filter((f) => f.in_app && f.filename).map(
    (f) => f.filename.replace(/^[A-Z]:/, "").replace(/\\/g, "/").split("/").filter((seg) => seg !== "")
    // remove empty segments
  );
  const firstPath = paths[0];
  if (!firstPath) {
    return void 0;
  }
  if (paths.length == 1) {
    return dirname(firstPath.join("/"));
  }
  let i = 0;
  while (firstPath[i] && paths.every((w) => w[i] === firstPath[i])) {
    i++;
  }
  return firstPath.slice(0, i).join("/");
}
function getCwd() {
  if (!Deno.permissions.querySync) {
    return void 0;
  }
  const permission = Deno.permissions.querySync({ name: "read", path: "./" });
  try {
    if (permission.state == "granted") {
      return Deno.cwd();
    }
  } catch {
  }
  return void 0;
}
const _normalizePathsIntegration = (() => {
  let appRoot;
  function getAppRoot(error) {
    if (appRoot === void 0) {
      appRoot = getCwd() || appRootFromErrorStack(error);
    }
    return appRoot;
  }
  return {
    name: INTEGRATION_NAME,
    processEvent(event) {
      const error = new Error();
      const appRoot2 = getAppRoot(error);
      if (appRoot2) {
        for (const exception of event.exception?.values || []) {
          for (const frame of exception.stacktrace?.frames || []) {
            if (frame.filename && frame.in_app) {
              const startIndex = frame.filename.indexOf(appRoot2);
              if (startIndex > -1) {
                const endIndex = startIndex + appRoot2.length;
                frame.filename = `app://${frame.filename.substring(endIndex)}`;
              }
            }
          }
        }
      }
      return event;
    }
  };
});
const normalizePathsIntegration = defineIntegration(_normalizePathsIntegration);

export { normalizePathsIntegration };
//# sourceMappingURL=normalizepaths.js.map
