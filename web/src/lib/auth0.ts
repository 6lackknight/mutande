import { Auth0Client } from "@auth0/nextjs-auth0/server";
import {
  AUTH0_ROLES_CLAIM_KEYS,
  isPlatformOpsAdmin,
  rolesFromJwt,
  SESSION_AUTH0_ROLES_KEY,
  SESSION_OPS_ADMIN_KEY,
} from "@/lib/platform-admin";

/** Custom login host — never the tenant `*.auth0.com` (authorize + JWKS). */
const AUTH0_DOMAIN = process.env.AUTH0_DOMAIN?.trim() || "auth.mutande.online";

/**
 * Auth0 Regular Web Application client.
 * Requires AUTH0_CLIENT_ID, AUTH0_CLIENT_SECRET, AUTH0_SECRET.
 * Audience must match hub AUTH0_AUDIENCE so access tokens validate on the API.
 */
export const auth0 = new Auth0Client({
  domain: AUTH0_DOMAIN,
  authorizationParameters: {
    audience: process.env.AUTH0_AUDIENCE ?? "https://hub.mutande.app",
    scope: "openid profile email offline_access",
  },
  /**
   * v4 drops custom ID claims from session.user — persist SuperAdmin roles using
   * cookie-safe keys. Use the idToken parameter (tokenSet may not round-trip).
   */
  async beforeSessionSaved(session, idToken) {
    const token = idToken ?? session.tokenSet?.idToken;
    const roles = rolesFromJwt(token);
    if (!roles.length) return session;
    const isOps = isPlatformOpsAdmin(roles);
    return {
      ...session,
      user: {
        ...session.user,
        [SESSION_AUTH0_ROLES_KEY]: roles,
        [SESSION_OPS_ADMIN_KEY]: isOps,
        [AUTH0_ROLES_CLAIM_KEYS[0]]: roles,
      },
    };
  },
});
