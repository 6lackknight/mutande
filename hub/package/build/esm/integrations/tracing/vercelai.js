import { defineIntegration, extendIntegration, addVercelAiProcessors } from '@sentry/core';
import { vercelAiIntegration } from '@sentry/server-utils';

const _vercelAIIntegration = ((options = {}) => {
  const inner = vercelAiIntegration(options);
  return extendIntegration(inner, {
    options,
    setup(client) {
      addVercelAiProcessors(client);
    }
  });
});
const vercelAIIntegration = defineIntegration(_vercelAIIntegration);

export { vercelAIIntegration };
//# sourceMappingURL=vercelai.js.map
