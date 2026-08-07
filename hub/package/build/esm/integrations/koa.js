import { koaChannelIntegration } from '@sentry/server-utils/orchestrion';
import { defineIntegration, extendIntegration } from '@sentry/core';
import { setAsyncLocalStorageAsyncContextStrategy } from '../async.js';

const INTEGRATION_NAME = "DenoKoa";
const _denoKoaIntegration = ((options = {}) => {
  const inner = koaChannelIntegration(options);
  return extendIntegration(inner, {
    name: INTEGRATION_NAME,
    setupOnce() {
      setAsyncLocalStorageAsyncContextStrategy();
    }
  });
});
const denoKoaIntegration = defineIntegration(_denoKoaIntegration);

export { denoKoaIntegration };
//# sourceMappingURL=koa.js.map
