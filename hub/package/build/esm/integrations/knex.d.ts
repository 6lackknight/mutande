import type { Integration } from '@sentry/core';
export declare const denoKnexIntegration: () => Integration & {
    name: "DenoKnex";
    setupOnce: () => void;
};
