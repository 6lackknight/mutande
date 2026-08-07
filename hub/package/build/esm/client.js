import { ServerRuntimeClient, SDK_VERSION, _INTERNAL_flushLogsBuffer } from '@sentry/core';

function getHostName() {
  if (!Deno.permissions.querySync) {
    return void 0;
  }
  const result = Deno.permissions.querySync({ name: "sys", kind: "hostname" });
  return result.state === "granted" ? Deno.hostname() : void 0;
}
class DenoClient extends ServerRuntimeClient {
  /**
   * Creates a new Deno SDK instance.
   * @param options Configuration options for this SDK.
   */
  constructor(options) {
    options._metadata = options._metadata || {};
    options._metadata.sdk = options._metadata.sdk || {
      name: "sentry.javascript.deno",
      packages: [
        {
          name: "denoland:sentry",
          version: SDK_VERSION
        }
      ],
      version: SDK_VERSION
    };
    const serverName = options.serverName || getHostName();
    const clientOptions = {
      ...options,
      platform: "javascript",
      runtime: { name: "deno", version: Deno.version.deno },
      serverName
    };
    super(clientOptions);
    if (this.getOptions().enableLogs) {
      this._logOnExitFlushListener = () => {
        _INTERNAL_flushLogsBuffer(this);
      };
      if (serverName) {
        this.on("beforeCaptureLog", (log) => {
          log.attributes = {
            ...log.attributes,
            "server.address": serverName
          };
        });
      }
      globalThis.addEventListener("unload", this._logOnExitFlushListener);
    }
  }
  /** @inheritDoc */
  // @ts-expect-error - PromiseLike is a subset of Promise
  async close(timeout) {
    if (this._logOnExitFlushListener) {
      globalThis.removeEventListener("unload", this._logOnExitFlushListener);
    }
    return super.close(timeout);
  }
}

export { DenoClient };
//# sourceMappingURL=client.js.map
