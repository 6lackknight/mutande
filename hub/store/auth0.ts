import * as jose from "jose";
import { unauthorized } from "./errors.ts";
import { AUTH0_ROLES_CLAIM_KEYS, extractAuth0Roles } from "./platform_admin.ts";
import type { Auth0Claims } from "./types.ts";

export interface TokenVerifier {
  verifyAccessToken(token: string): Promise<Auth0Claims>;
}

function claimsFromPayload(payload: jose.JWTPayload): Auth0Claims {
  const sub = payload.sub;
  if (typeof sub !== "string" || !sub) {
    throw unauthorized("Invalid token: missing sub");
  }
  const email = typeof payload.email === "string" ? payload.email : undefined;
  const roles = extractAuth0Roles(payload as Record<string, unknown>);
  return { sub, email, ...(roles.length ? { roles } : {}) };
}

export function createAuth0Verifier(config: {
  /** Host for JWKS (custom domain preferred). */
  domain: string;
  /** Primary API audience (hub Identifier). */
  audience: string;
  /**
   * Optional extra audience (hosted MCP resource Indicator).
   * ChatGPT DCR sends `resource=https://mcp.mutande.online`; Auth0 issues
   * that aud — hub accepts it so MCP can forward the same Bearer without OBO.
   */
  mcpAudience?: string | null;
  /**
   * Extra Auth0 hosts whose `iss` is also accepted (same JWKS keys).
   * Used while Mac/web use `auth.mutande.online` and Deploy still has the tenant host.
   */
  issuerAliases?: string[];
}): TokenVerifier {
  const hosts = [
    config.domain,
    ...(config.issuerAliases ?? []).map((h) => h.trim()).filter(Boolean),
  ];
  const issuers = [...new Set(hosts.map((h) => `https://${h.replace(/\/+$/, "")}/`))];
  const audiences = [
    config.audience,
    ...(config.mcpAudience && config.mcpAudience !== config.audience
      ? [config.mcpAudience]
      : []),
  ];
  const jwks = jose.createRemoteJWKSet(
    new URL(`https://${config.domain}/.well-known/jwks.json`),
  );

  return {
    async verifyAccessToken(token: string): Promise<Auth0Claims> {
      try {
        const { payload } = await jose.jwtVerify(token, jwks, {
          issuer: issuers.length === 1 ? issuers[0] : issuers,
          audience: audiences.length === 1 ? audiences[0] : audiences,
        });
        return claimsFromPayload(payload);
      } catch (e) {
        if (e instanceof Error && e.message.includes("missing sub")) throw e;
        throw unauthorized("Invalid or expired token");
      }
    },
  };
}

/** Test helper: local RSA keypair + signer for Auth0-shaped access tokens. */
export async function createTestTokenVerifier(config: {
  issuer?: string;
  audience?: string;
} = {}): Promise<{
  verifier: TokenVerifier;
  signToken: (claims: Auth0Claims) => Promise<string>;
}> {
  const issuer = config.issuer ?? "https://test.auth0.local/";
  const audience = config.audience ?? "https://hub.mutande.test";
  const { publicKey, privateKey } = await jose.generateKeyPair("RS256");
  const jwk = await jose.exportJWK(publicKey);
  jwk.alg = "RS256";
  jwk.use = "sig";
  jwk.kid = "test-key";
  const jwks = jose.createLocalJWKSet({ keys: [jwk] });

  const verifier: TokenVerifier = {
    async verifyAccessToken(token: string): Promise<Auth0Claims> {
      try {
        const { payload } = await jose.jwtVerify(token, jwks, { issuer, audience });
        return claimsFromPayload(payload);
      } catch (e) {
        if (e instanceof Error && e.message.includes("missing sub")) throw e;
        throw unauthorized("Invalid or expired token");
      }
    },
  };

  const signToken = async (claims: Auth0Claims): Promise<string> => {
    const body: Record<string, unknown> = {};
    if (claims.email) body.email = claims.email;
    if (claims.roles?.length) {
      body[AUTH0_ROLES_CLAIM_KEYS[0]] = claims.roles;
    }
    const builder = new jose.SignJWT(body)
      .setProtectedHeader({ alg: "RS256", kid: "test-key" })
      .setSubject(claims.sub)
      .setIssuer(issuer)
      .setAudience(audience)
      .setIssuedAt()
      .setExpirationTime("1h");
    return builder.sign(privateKey);
  };

  return { verifier, signToken };
}
