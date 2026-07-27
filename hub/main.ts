import { Hono } from "hono";
import { handleHubError } from "./middleware/auth.ts";
import { createAuthRoutes } from "./routes/auth.ts";
import { createBlobRoutes } from "./routes/blobs.ts";
import { createContactRoutes } from "./routes/contacts.ts";
import { createDraftRoutes } from "./routes/drafts.ts";
import { healthRoutes } from "./routes/health.ts";
import { createThreadRoutes } from "./routes/threads.ts";
import { assertR2ConfiguredForDeploy } from "./store/r2.ts";
import { createStore } from "./store/store.ts";

export async function createApp(kv?: Deno.Kv) {
  assertR2ConfiguredForDeploy();
  const resolvedKv = kv ?? await Deno.openKv();
  const store = createStore(resolvedKv);

  const app = new Hono();

  app.onError((err) => handleHubError(err));

  app.route("/", healthRoutes);
  app.route("/v1/auth", createAuthRoutes(store));
  app.route("/v1/contacts", createContactRoutes(store));
  app.route("/v1/threads", createThreadRoutes(store));
  app.route("/v1/drafts", createDraftRoutes(store));
  app.route("/v1/blobs", createBlobRoutes(store));

  return { app, kv: resolvedKv, store };
}

if (import.meta.main) {
  const { app } = await createApp();
  Deno.serve(app.fetch);
}
