import type { Integration } from '@sentry/core';
export declare const denoMongooseIntegration: () => Integration & {
    name: "DenoMongoose";
    setupOnce: () => void;
};
