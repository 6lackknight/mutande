import { amqplibChannelIntegration } from '@sentry/server-utils/orchestrion';
import { defineIntegration, extendIntegration } from '@sentry/core';
import { setAsyncLocalStorageAsyncContextStrategy } from '../async.js';

const INTEGRATION_NAME = "DenoAmqplib";
const _denoAmqplibIntegration = (() => {
  const inner = amqplibChannelIntegration();
  return extendIntegration(inner, {
    name: INTEGRATION_NAME,
    setupOnce() {
      setAsyncLocalStorageAsyncContextStrategy();
    }
  });
});
const denoAmqplibIntegration = defineIntegration(_denoAmqplibIntegration);

export { denoAmqplibIntegration };
//# sourceMappingURL=amqplib.js.map
