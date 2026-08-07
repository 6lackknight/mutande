import { postgresChannelIntegration } from '@sentry/server-utils/orchestrion';
import { defineIntegration, extendIntegration } from '@sentry/core';
import { setAsyncLocalStorageAsyncContextStrategy } from '../async.js';

const INTEGRATION_NAME = "DenoPostgres";
const _denoPostgresIntegration = ((options) => {
  const inner = postgresChannelIntegration(options);
  return extendIntegration(inner, {
    name: INTEGRATION_NAME,
    setupOnce() {
      setAsyncLocalStorageAsyncContextStrategy();
    }
  });
});
const denoPostgresIntegration = defineIntegration(_denoPostgresIntegration);

export { denoPostgresIntegration };
//# sourceMappingURL=postgres.js.map
