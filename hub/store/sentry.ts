/**
 * GlitchTip (Sentry-compatible) reporting for the Deno hub.
 *
 * Dedicated project 26611 — do not reuse Flutter (26609) or core (26610).
 * Env MUTANDE_SENTRY_DSN / SENTRY_DSN overrides; empty string disables.
 */

import * as Sentry from "@sentry/deno";

/** Production GlitchTip DSN for the Deno hub project. */
export const DEFAULT_SENTRY_DSN =
  "https://51a674afd6bc4212b385cd6561b265fc@app.glitchtip.com/26611";

export const HUB_RELEASE = "mutande-hub@0.1.0";

/** Resolve DSN: MUTANDE_SENTRY_DSN → SENTRY_DSN → default. Empty disables. */
export function resolveSentryDsn(
  env: { get(key: string): string | undefined } = Deno.env,
): string | undefined {
  for (const key of ["MUTANDE_SENTRY_DSN", "SENTRY_DSN"]) {
    const raw = env.get(key);
    if (raw !== undefined) {
      const trimmed = raw.trim();
      return trimmed.length > 0 ? trimmed : undefined;
    }
  }
  const fallback = DEFAULT_SENTRY_DSN.trim();
  return fallback.length > 0 ? fallback : undefined;
}

export function sentrySmokeEnabled(
  env: { get(key: string): string | undefined } = Deno.env,
): boolean {
  const v = env.get("SENTRY_SMOKE")?.trim().toLowerCase();
  return v === "1" || v === "true" || v === "yes";
}

/** Shared init options. Never send PII or HTTP bodies (envelopes are ciphertext). */
export function hubSentryOptions(opts?: {
  smoke?: boolean;
  dsn?: string;
  env?: { get(key: string): string | undefined };
}): Sentry.DenoOptions {
  const env = opts?.env ?? Deno.env;
  const smoke = opts?.smoke ?? false;
  const dsn = opts?.dsn ?? resolveSentryDsn(env);
  const onDeploy = Boolean(env.get("DENO_DEPLOYMENT_ID"));

  return {
    dsn: dsn ?? "",
    release: HUB_RELEASE,
    tracesSampleRate: smoke ? 1.0 : 0.01,
    sendDefaultPii: false,
    environment: smoke ? "smoke" : onDeploy ? "production" : "development",
    debug: smoke,
    // Strip bodies/cookies — hub requests may carry ciphertext envelopes.
    integrations: [
      Sentry.requestDataIntegration({
        include: { data: false, cookies: false, ip: false },
      }),
      Sentry.denoHttpIntegration({ maxRequestBodySize: "none" }),
    ],
    beforeSend(event) {
      if (event.request) {
        delete event.request.data;
        delete event.request.cookies;
      }
      return event;
    },
  };
}

/** Init GlitchTip when a DSN is available. No-op when disabled. */
export function initHubSentry(opts?: {
  smoke?: boolean;
  env?: { get(key: string): string | undefined };
}): boolean {
  const env = opts?.env ?? Deno.env;
  const dsn = resolveSentryDsn(env);
  if (!dsn) return false;
  Sentry.init(hubSentryOptions({ smoke: opts?.smoke, dsn, env }));
  return true;
}

/** Report unexpected (non-HubError) failures. Safe when Sentry is disabled. */
export function captureHubException(err: unknown): void {
  if (!Sentry.getClient()) return;
  Sentry.captureException(err);
}

/**
 * Capture a smoke message + span, then flush.
 * No-ops (exit 0) when DSN is unset so CI without secrets stays green.
 */
export async function runSentrySmoke(
  env: { get(key: string): string | undefined } = Deno.env,
): Promise<"flushed" | "skipped"> {
  const dsn = resolveSentryDsn(env);
  if (!dsn) {
    console.error(
      "SENTRY_SMOKE: skipped (no DSN; set MUTANDE_SENTRY_DSN or SENTRY_DSN)",
    );
    return "skipped";
  }

  Sentry.init(hubSentryOptions({ smoke: true, dsn, env }));

  await Sentry.startSpan(
    { name: "glitchtip.smoke", op: "smoke" },
    () => {
      Sentry.captureMessage(
        `mutande-hub GlitchTip smoke (${HUB_RELEASE})`,
        "info",
      );
    },
  );

  await Sentry.flush(5000);
  await Sentry.close(2000);
  console.log("SENTRY_SMOKE: message + transaction flushed");
  return "flushed";
}
