import { knexChannelIntegration } from '@sentry/server-utils/orchestrion';
import { defineIntegration, extendIntegration } from '@sentry/core';
import { setAsyncLocalStorageAsyncContextStrategy } from '../async.js';

const INTEGRATION_NAME = "DenoKnex";
const _denoKnexIntegration = (() => {
  const inner = knexChannelIntegration();
  return extendIntegration(inner, {
    name: INTEGRATION_NAME,
    setupOnce() {
      setAsyncLocalStorageAsyncContextStrategy();
    }
  });
});
const denoKnexIntegration = defineIntegration(_denoKnexIntegration);

export { denoKnexIntegration };
//# sourceMappingURL=knex.js.map
