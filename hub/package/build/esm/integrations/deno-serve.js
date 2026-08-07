import { defineIntegration, debug } from '@sentry/core';
import { setAsyncLocalStorageAsyncContextStrategy } from '../async.js';
import { wrapDenoRequestHandler } from '../wrap-deno-request-handler.js';

const INTEGRATION_NAME = "DenoServe";
const isSimpleHandler = (p) => typeof p[0] === "function";
const isServeOptWithFunction = (p) => p.length >= 2 && typeof p[1] === "function" && !!p[0] && typeof p[0] === "object";
const isServeInitOptions = (p) => typeof p[0] === "object" && !!p[0] && !isServeOptWithFunction(p) && "handler" in p[0] && typeof p[0].handler === "function";
const applyHandlerWrap = (handler, serveOptions) => ((request, info) => wrapDenoRequestHandler(
  {
    request,
    info},
  () => handler(request, info)
));
const instrumentedDenoServe = (serve) => new Proxy(serve, {
  apply(target, thisArg, args) {
    if (isSimpleHandler(args)) {
      args[0] = applyHandlerWrap(args[0]);
    } else if (isServeOptWithFunction(args)) {
      args[1] = applyHandlerWrap(args[1], args[0]);
    } else if (isServeInitOptions(args)) {
      args[0].handler = applyHandlerWrap(args[0].handler, args[0]);
    }
    return target.apply(thisArg, args);
  }
});
const _denoServeIntegration = (() => {
  return {
    name: INTEGRATION_NAME,
    setupOnce() {
      setAsyncLocalStorageAsyncContextStrategy();
      const originalServe = Deno.serve;
      const wrappedServe = instrumentedDenoServe(originalServe);
      try {
        const descriptor = Object.getOwnPropertyDescriptor(Deno, "serve");
        Object.defineProperty(Deno, "serve", {
          configurable: descriptor?.configurable ?? true,
          enumerable: descriptor?.enumerable ?? true,
          // writable: true avoids other instrumentations on older Deno versions
          // from crashing if they used to do assignment
          writable: true,
          value: wrappedServe
        });
      } catch (error) {
        debug.warn("Could not instrument Deno.serve.", error);
      }
    }
  };
});
const denoServeIntegration = defineIntegration(_denoServeIntegration);

export { denoServeIntegration };
//# sourceMappingURL=deno-serve.js.map
