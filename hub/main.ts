import { Hono } from "hono";
import { handleHubError } from "./middleware/auth.ts";
import { createAdminRoutes } from "./routes/admin.ts";
import { createAgentRoutes } from "./routes/agents.ts";
import { createAuthRoutes } from "./routes/auth.ts";
import { createBlobRoutes } from "./routes/blobs.ts";
import { createContactRoutes } from "./routes/contacts.ts";
import { createDeviceRoutes } from "./routes/devices.ts";
import { createDraftRoutes } from "./routes/drafts.ts";
import { createFeedbackRoutes } from "./routes/feedback.ts";
import { createWaitlistRoutes } from "./routes/waitlist.ts";
import { healthRoutes } from "./routes/health.ts";
import { createMeRoutes } from "./routes/me.ts";
import { createOnboardingRoutes } from "./routes/onboarding.ts";
import { createOrgRoutes } from "./routes/orgs.ts";
import { createRegistryRoutes } from "./routes/registry.ts";
import { createThreadRoutes } from "./routes/threads.ts";
import { createCollabRoutes } from "./routes/collabs.ts";
import { assertR2ConfiguredForDeploy } from "./store/r2.ts";
import {
  initHubSentry,
  runSentrySmoke,
  sentrySmokeEnabled,
} from "./store/sentry.ts";
import { createStore } from "./store/store.ts";
import type { TokenVerifier } from "./store/auth0.ts";

export async function createApp(
  kv?: Deno.Kv,
  storeOptions?: { verifier?: TokenVerifier },
) {
  assertR2ConfiguredForDeploy();
  const resolvedKv = kv ?? await Deno.openKv();
  const store = createStore(resolvedKv, storeOptions);

  const app = new Hono();
  app.onError((err) => handleHubError(err));

  app.route("/", healthRoutes);
  app.route("/v1/auth", createAuthRoutes(store));
  app.route("/v1/me", createMeRoutes(store));
  app.route("/v1/orgs", createOrgRoutes(store));
  app.route("/v1/onboarding", createOnboardingRoutes(store));
  app.route("/v1/devices", createDeviceRoutes(store));
  app.route("/v1/agents", createAgentRoutes(store));
  app.route("/v1/admin", createAdminRoutes(store));
  app.route("/v1/registry", createRegistryRoutes(store));
  app.route("/v1/contacts", createContactRoutes(store));
  app.route("/v1/threads", createThreadRoutes(store));
  app.route("/v1/collabs", createCollabRoutes(store));
  app.route("/v1/drafts", createDraftRoutes(store));
  app.route("/v1/blobs", createBlobRoutes(store));
  app.route("/v1/feedback", createFeedbackRoutes(store));
  app.route("/v1/waitlist", createWaitlistRoutes(store));

  return { app, kv: resolvedKv, store };
}

if (import.meta.main) {
  if (sentrySmokeEnabled()) {
    await runSentrySmoke();
    Deno.exit(0);
  }
  initHubSentry();
  const { app } = await createApp();
  Deno.serve(app.fetch);
}
