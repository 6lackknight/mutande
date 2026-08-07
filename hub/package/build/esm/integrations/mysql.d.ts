import type { Integration } from '@sentry/core';
export declare const denoMysqlIntegration: () => Integration & {
    name: "DenoMysql";
    setupOnce: () => void;
};
