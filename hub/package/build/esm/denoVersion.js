import { parseSemver } from '@sentry/core';

const DENO_VERSION = parseSemver(typeof Deno !== "undefined" ? Deno.version?.deno ?? "" : "");
function gte(major, minor, patch) {
  const { major: M, minor: m, patch: p } = DENO_VERSION;
  if (M === void 0 || m === void 0 || p === void 0) return false;
  if (M !== major) return M > major;
  if (m !== minor) return m > minor;
  return p >= patch;
}
const HTTP_CLIENT_DIAGNOSTICS_CHANNEL_SUPPORTED = gte(2, 7, 13);
const HTTP_SERVER_DIAGNOSTICS_CHANNEL_SUPPORTED = gte(2, 8, 0);
const TRACING_CHANNEL_SUPPORTED = gte(1, 44, 3);
const MODULE_REGISTER_HOOKS_SUPPORTED = gte(2, 8, 0);

export { DENO_VERSION, HTTP_CLIENT_DIAGNOSTICS_CHANNEL_SUPPORTED, HTTP_SERVER_DIAGNOSTICS_CHANNEL_SUPPORTED, MODULE_REGISTER_HOOKS_SUPPORTED, TRACING_CHANNEL_SUPPORTED };
//# sourceMappingURL=denoVersion.js.map
