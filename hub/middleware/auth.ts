import type { Context, Next } from "hono";
import { HubError, unauthorized } from "../store/errors.ts";
import { captureHubException } from "../store/sentry.ts";
import type { HubStore } from "../store/store.ts";
import type { Auth0Claims, AuthContext } from "../store/types.ts";

export type HubVariables = {
  auth0: Auth0Claims;
  auth: AuthContext;
};

export type HubEnv = {
  Variables: HubVariables;
};

export function auth0Middleware(store: HubStore) {
  return async (c: Context<HubEnv>, next: Next) => {
    const header = c.req.header("Authorization");
    if (!header?.startsWith("Bearer ")) throw unauthorized("Missing Bearer token");
    const token = header.slice("Bearer ".length);
    try {
      const claims = await store.verifyAuth0Claims(token);
      c.set("auth0", claims);
      await next();
    } catch (e) {
      if (e instanceof HubError) throw e;
      throw unauthorized("Invalid or expired token");
    }
  };
}

export function authMiddleware(store: HubStore) {
  return async (c: Context<HubEnv>, next: Next) => {
    const header = c.req.header("Authorization");
    if (!header?.startsWith("Bearer ")) throw unauthorized("Missing Bearer token");
    const token = header.slice("Bearer ".length);
    try {
      const auth = await store.verifyAccessToken(token);
      c.set("auth", auth);
      await next();
    } catch (e) {
      if (e instanceof HubError) throw e;
      throw unauthorized("Invalid or expired token");
    }
  };
}

export function handleHubError(err: unknown): Response {
  if (err instanceof HubError) {
    return Response.json({ error: err.code, message: err.message }, { status: err.status });
  }
  console.error(err);
  // Unexpected only — never HubError / never request bodies or mail plaintext.
  captureHubException(err);
  return Response.json({ error: "internal", message: "Internal server error" }, { status: 500 });
}
