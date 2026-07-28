import { Auth0Client } from "@auth0/nextjs-auth0/server";

/**
 * Auth0 Regular Web Application client.
 * Requires AUTH0_DOMAIN, AUTH0_CLIENT_ID, AUTH0_CLIENT_SECRET, AUTH0_SECRET.
 * Audience must match hub AUTH0_AUDIENCE so access tokens validate on the API.
 */
export const auth0 = new Auth0Client({
  authorizationParameters: {
    audience: process.env.AUTH0_AUDIENCE ?? "https://hub.mutande.app",
    scope: "openid profile email offline_access",
  },
});
