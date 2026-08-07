import { dataloaderChannelIntegration } from '@sentry/server-utils/orchestrion';
import { defineIntegration, extendIntegration } from '@sentry/core';
import { setAsyncLocalStorageAsyncContextStrategy } from '../async.js';

const INTEGRATION_NAME = "DenoDataloader";
const _denoDataloaderIntegration = (() => {
  const inner = dataloaderChannelIntegration();
  return extendIntegration(inner, {
    name: INTEGRATION_NAME,
    setupOnce() {
      setAsyncLocalStorageAsyncContextStrategy();
    }
  });
});
const denoDataloaderIntegration = defineIntegration(_denoDataloaderIntegration);

export { denoDataloaderIntegration };
//# sourceMappingURL=dataloader.js.map
