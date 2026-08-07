import { mongodbChannelIntegration } from '@sentry/server-utils/orchestrion';
import { defineIntegration, extendIntegration } from '@sentry/core';
import { setAsyncLocalStorageAsyncContextStrategy } from '../async.js';

const INTEGRATION_NAME = "DenoMongo";
const _denoMongoIntegration = (() => {
  const inner = mongodbChannelIntegration();
  return extendIntegration(inner, {
    name: INTEGRATION_NAME,
    setupOnce() {
      setAsyncLocalStorageAsyncContextStrategy();
    }
  });
});
const denoMongoIntegration = defineIntegration(_denoMongoIntegration);

export { denoMongoIntegration };
//# sourceMappingURL=mongo.js.map
