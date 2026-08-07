import { mongooseChannelIntegration } from '@sentry/server-utils/orchestrion';
import { defineIntegration, extendIntegration } from '@sentry/core';
import { setAsyncLocalStorageAsyncContextStrategy } from '../async.js';

const INTEGRATION_NAME = "DenoMongoose";
const _denoMongooseIntegration = (() => {
  const inner = mongooseChannelIntegration();
  return extendIntegration(inner, {
    name: INTEGRATION_NAME,
    setupOnce() {
      setAsyncLocalStorageAsyncContextStrategy();
    }
  });
});
const denoMongooseIntegration = defineIntegration(_denoMongooseIntegration);

export { denoMongooseIntegration };
//# sourceMappingURL=mongoose.js.map
