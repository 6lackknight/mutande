import type { Integration } from '@sentry/core';
export declare const denoAmqplibIntegration: () => Integration & {
    name: "DenoAmqplib";
    setupOnce: () => void;
};
