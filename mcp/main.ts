import { Hono } from "hono";
import { loadConfig, requireAuth0OnDeploy } from "./config.ts";
import { createAuth0Verifier } from "./auth/oauth.ts";
import { HubClient } from "./hub/client.ts";
import { createHealthRoutes } from "./routes/health.ts";
import { createOauthRoutes } from "./routes/oauth.ts";
import { createMcpRoutes } from "./routes/mcp.ts";
import {
  initGlobalSessionStore,
  type SessionStore,
} from "./transport/sessions.ts";
import {
  handleMcpError,
  initMcpSentry,
  runSentrySmoke,
  sentrySmokeEnabled,
} from "./sentry.ts";

export function createApp(options?: {
  config?: ReturnType<typeof loadConfig>;
  verifier?: ReturnType<typeof createAuth0Verifier>;
  hub?: HubClient;
  sessions?: SessionStore;
}) {
  const config = options?.config ?? loadConfig();
  requireAuth0OnDeploy(config);
  const verifier = options?.verifier ?? createAuth0Verifier(config);
  const hub = options?.hub ?? new HubClient(config.hubUrl);

  const app = new Hono();
  app.onError((err) => handleMcpError(err));

  app.get("/", (c) =>
    c.json({
      service: "mutande-mcp",
      version: "0.1.0",
      mcp: `${config.publicUrl}/mcp`,
      oauth_protected_resource:
        `${config.publicUrl}/.well-known/oauth-protected-resource`,
      docs: "See mcp/README.md — ChatGPT / Claude.ai connect here as MCP clients.",
    })
  );

  app.route("/", createHealthRoutes(config));
  app.route("/", createOauthRoutes(config));
  app.route(
    "/",
    createMcpRoutes(config, verifier, hub, {
      sessions: options?.sessions,
    }),
  );

  return { app, config };
}

if (import.meta.main) {
  if (sentrySmokeEnabled()) {
    await runSentrySmoke();
    Deno.exit(0);
  }
  // Best-effort GlitchTip — must never block Deno.serve if SDK/init fails.
  await initMcpSentry();
  // Deno KV so Mcp-Session-Id survives isolate recycle on Deploy.
  const sessions = await initGlobalSessionStore();
  const { app, config } = createApp({ sessions });
  console.log(
    `[mutande-mcp] listening public=${config.publicUrl} hub=${config.hubUrl} port=${config.port} sessions=kv`,
  );
  Deno.serve({ port: config.port }, app.fetch);
}
