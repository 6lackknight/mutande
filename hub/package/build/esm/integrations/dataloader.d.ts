import type { Integration } from '@sentry/core';
export declare const denoDataloaderIntegration: () => Integration & {
    name: "DenoDataloader";
    setupOnce: () => void;
};
