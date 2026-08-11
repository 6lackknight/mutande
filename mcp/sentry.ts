/**
 * GlitchTip (Sentry-compatible) reporting for the hosted MCP service.
 *
 * Dedicated project 26806 — do not reuse Flutter (26609), core (26610), or hub (26611).
 * Env MUTANDE_SENTRY_DSN / SENTRY_DSN overrides; empty string disables.
 */

import * as Sentry from "@sentry/deno";

/** Production GlitchTip DSN for the Deno MCP project. */
export const DEFAULT_SENTRY_DSN =
  "https://41612157a4f24fb28b28ab44c373a27a@app.glitchtip.com/26806";

export const MCP_RELEASE = "mutande-mcp@0.1.0";

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

/** Shared init options. Never send PII or HTTP bodies (tokens / MCP payloads). */
export function mcpSentryOptions(opts?: {
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
    release: MCP_RELEASE,
    tracesSampleRate: smoke ? 1.0 : 0.01,
    sendDefaultPii: false,
    environment: smoke ? "smoke" : onDeploy ? "production" : "development",
    debug: smoke,
    // Strip bodies/cookies — MCP may carry Bearer tokens and tool args.
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
export function initMcpSentry(opts?: {
  smoke?: boolean;
  env?: { get(key: string): string | undefined };
}): boolean {
  const env = opts?.env ?? Deno.env;
  const dsn = resolveSentryDsn(env);
  if (!dsn) return false;
  Sentry.init(mcpSentryOptions({ smoke: opts?.smoke, dsn, env }));
  return true;
}

/**
 * Report unexpected failures (not expected auth / HubClientError paths).
 * Safe when Sentry is disabled.
 */
export function captureMcpException(err: unknown): void {
  if (!Sentry.getClient()) return;
  Sentry.captureException(err);
}

/** Hono onError handler — expected client errors stay local; unexpected → GlitchTip. */
export function handleMcpError(err: unknown): Response {
  console.error(err);
  captureMcpException(err);
  return Response.json(
    { error: "internal", message: "Internal server error" },
    { status: 500 },
  );
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

  Sentry.init(mcpSentryOptions({ smoke: true, dsn, env }));

  await Sentry.startSpan(
    { name: "glitchtip.smoke", op: "smoke" },
    () => {
      Sentry.captureMessage(
        `mutande-mcp GlitchTip smoke (${MCP_RELEASE})`,
        "info",
      );
    },
  );

  await Sentry.flush(5000);
  await Sentry.close(2000);
  console.log("SENTRY_SMOKE: message + transaction flushed");
  return "flushed";
}
