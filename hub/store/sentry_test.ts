import { assertEquals } from "jsr:@std/assert@^1";
import {
  DEFAULT_SENTRY_DSN,
  hubSentryOptions,
  resolveSentryDsn,
  sentrySmokeEnabled,
} from "./sentry.ts";

Deno.test("resolveSentryDsn falls back to hub project 26611", () => {
  const env = new Map<string, string>();
  assertEquals(
    resolveSentryDsn({ get: (k) => env.get(k) }),
    DEFAULT_SENTRY_DSN,
  );
  assertEquals(DEFAULT_SENTRY_DSN.includes("/26611"), true);
});

Deno.test("resolveSentryDsn prefers MUTANDE_SENTRY_DSN then SENTRY_DSN", () => {
  const env = new Map<string, string>([
    ["SENTRY_DSN", "https://b@app.glitchtip.com/2"],
    ["MUTANDE_SENTRY_DSN", "https://a@app.glitchtip.com/1"],
  ]);
  assertEquals(
    resolveSentryDsn({ get: (k) => env.get(k) }),
    "https://a@app.glitchtip.com/1",
  );
});

Deno.test("resolveSentryDsn empty env disables reporting", () => {
  const env = new Map<string, string>([["SENTRY_DSN", "  "]]);
  assertEquals(resolveSentryDsn({ get: (k) => env.get(k) }), undefined);
});

Deno.test("hubSentryOptions keeps traces light and no PII", () => {
  const opts = hubSentryOptions({
    dsn: DEFAULT_SENTRY_DSN,
    env: { get: () => undefined },
  });
  assertEquals(opts.tracesSampleRate, 0.01);
  assertEquals(opts.sendDefaultPii, false);
  assertEquals(typeof opts.beforeSend, "function");
});

Deno.test("sentrySmokeEnabled accepts 1/true/yes", () => {
  assertEquals(
    sentrySmokeEnabled({ get: (k) => (k === "SENTRY_SMOKE" ? "1" : undefined) }),
    true,
  );
  assertEquals(
    sentrySmokeEnabled({ get: (k) => (k === "SENTRY_SMOKE" ? "true" : undefined) }),
    true,
  );
  assertEquals(
    sentrySmokeEnabled({ get: () => undefined }),
    false,
  );
});
