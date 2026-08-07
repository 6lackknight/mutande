import { redisIntegration } from '@sentry/server-utils';
import { defineIntegration, extendIntegration } from '@sentry/core';
import { setAsyncLocalStorageAsyncContextStrategy } from '../async.js';

const INTEGRATION_NAME = "DenoRedis";
const _denoRedisIntegration = ((options = {}) => {
  return extendIntegration(redisIntegration({ responseHook: options.responseHook }), {
    name: INTEGRATION_NAME,
    setupOnce() {
      setAsyncLocalStorageAsyncContextStrategy();
    }
  });
});
const denoRedisIntegration = defineIntegration(_denoRedisIntegration);

export { denoRedisIntegration };
//# sourceMappingURL=redis.js.map
