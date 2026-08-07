import { mysqlChannelIntegration } from '@sentry/server-utils/orchestrion';
import { defineIntegration, extendIntegration } from '@sentry/core';
import { setAsyncLocalStorageAsyncContextStrategy } from '../async.js';

const INTEGRATION_NAME = "DenoMysql";
const _denoMysqlIntegration = (() => {
  const inner = mysqlChannelIntegration();
  return extendIntegration(inner, {
    name: INTEGRATION_NAME,
    setupOnce() {
      setAsyncLocalStorageAsyncContextStrategy();
    }
  });
});
const denoMysqlIntegration = defineIntegration(_denoMysqlIntegration);

export { denoMysqlIntegration };
//# sourceMappingURL=mysql.js.map
