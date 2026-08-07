import type { Integration } from '@sentry/core';
export declare const denoMongoIntegration: () => Integration & {
    name: "DenoMongo";
    setupOnce: () => void;
};
