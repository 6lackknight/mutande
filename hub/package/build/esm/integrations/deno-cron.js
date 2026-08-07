import { defineIntegration, getClient, withMonitor } from '@sentry/core';
import { parseScheduleToString } from './deno-cron-format.js';

const INTEGRATION_NAME = "DenoCron";
const SETUP_CLIENTS = /* @__PURE__ */ new WeakMap();
const _denoCronIntegration = (() => {
  return {
    name: INTEGRATION_NAME,
    setupOnce() {
      if (!Deno.cron) {
        return;
      }
      Deno.cron = new Proxy(Deno.cron, {
        apply(target, thisArg, argArray) {
          const [monitorSlug, schedule, opt1, opt2] = argArray;
          let options;
          let fn;
          if (typeof opt1 === "function" && typeof opt2 !== "function") {
            fn = opt1;
            options = opt2;
          } else if (typeof opt1 !== "function" && typeof opt2 === "function") {
            fn = opt2;
            options = opt1;
          }
          async function cronCalled() {
            if (!SETUP_CLIENTS.has(getClient())) {
              return fn();
            }
            await withMonitor(monitorSlug, async () => fn(), {
              schedule: { type: "crontab", value: parseScheduleToString(schedule) },
              // (minutes) so 12 hours - just a very high arbitrary number since we don't know the actual duration of the users cron job
              maxRuntime: 60 * 12,
              // Deno Deploy docs say that the cron job will be called within 1 minute of the scheduled time
              checkinMargin: 1
            });
          }
          return target.call(thisArg, monitorSlug, schedule, options || {}, cronCalled);
        }
      });
    },
    setup(client) {
      SETUP_CLIENTS.set(client, true);
    }
  };
});
const denoCronIntegration = defineIntegration(_denoCronIntegration);

export { denoCronIntegration };
//# sourceMappingURL=deno-cron.js.map
