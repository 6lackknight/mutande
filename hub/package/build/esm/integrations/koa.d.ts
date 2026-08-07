import type { KoaChannelIntegrationOptions } from '@sentry/server-utils/orchestrion';
import type { Integration } from '@sentry/core';
export declare const denoKoaIntegration: (options?: KoaChannelIntegrationOptions) => Integration & {
    name: "DenoKoa";
    setupOnce: () => void;
};
