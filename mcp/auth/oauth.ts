import * as jose from "jose";
import type { McpConfig } from "../config.ts";

export interface Auth0Claims {
  sub: string;
  email?: string;
}

export interface TokenVerifier {
  verifyAccessToken(token: string): Promise<Auth0Claims>;
}

function claimsFromPayload(payload: jose.JWTPayload): Auth0Claims {
  const sub = payload.sub;
  if (typeof sub !== "string" || !sub) {
    throw new Error("Invalid token: missing sub");
  }
  const email = typeof payload.email === "string" ? payload.email : undefined;
  return { sub, email };
}

/** Verify Auth0 access tokens (hub and/or MCP resource audience). */
export function createAuth0Verifier(config: McpConfig): TokenVerifier {
  const hosts = [
    config.auth0Domain,
    ...config.issuerAliases.map((h) => h.trim()).filter(Boolean),
  ];
  const issuers = [
    ...new Set(hosts.map((h) => `https://${h.replace(/\/+$/, "")}/`)),
  ];
  const audiences = [
    config.auth0Audience,
    ...(config.auth0McpAudience ? [config.auth0McpAudience] : []),
  ];
  const jwks = jose.createRemoteJWKSet(
    new URL(`https://${config.auth0Domain}/.well-known/jwks.json`),
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
        throw new Error("Invalid or expired token");
      }
    },
  };
}

/** Test helper: local RSA keypair + signer. */
export async function createTestTokenVerifier(config: {
  issuer?: string;
  audience?: string | string[];
} = {}): Promise<{
  verifier: TokenVerifier;
  signToken: (
    claims: Auth0Claims,
    opts?: { audience?: string; azp?: string },
  ) => Promise<string>;
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
        const { payload } = await jose.jwtVerify(token, jwks, {
          issuer,
          audience,
        });
        return claimsFromPayload(payload);
      } catch (e) {
        if (e instanceof Error && e.message.includes("missing sub")) throw e;
        throw new Error("Invalid or expired token");
      }
    },
  };

  const signToken = async (
    claims: Auth0Claims,
    opts?: { audience?: string; azp?: string },
  ): Promise<string> => {
    const body: Record<string, unknown> = {};
    if (claims.email) body.email = claims.email;
    if (opts?.azp) body.azp = opts.azp;
    const aud = opts?.audience ??
      (Array.isArray(audience) ? audience[0] : audience);
    return new jose.SignJWT(body)
      .setProtectedHeader({ alg: "RS256", kid: "test-key" })
      .setSubject(claims.sub)
      .setIssuer(issuer)
      .setAudience(aud)
      .setIssuedAt()
      .setExpirationTime("1h")
      .sign(privateKey);
  };

  return { verifier, signToken };
}

/** RFC 9728 Protected Resource Metadata. */
export function protectedResourceMetadata(config: McpConfig) {
  const authorizationServer = `https://${config.auth0Domain}/`;
  return {
    resource: config.publicUrl,
    authorization_servers: [authorizationServer],
    scopes_supported: ["openid", "profile", "email", "offline_access"],
    bearer_methods_supported: ["header"],
    resource_documentation: `${config.publicUrl}/`,
  };
}

/** WWW-Authenticate for 401 responses (MCP clients discover PRM from this). */
export function wwwAuthenticateHeader(
  config: McpConfig,
  opts?: { error?: "invalid_token" | "invalid_request"; description?: string },
): string {
  const metadataUrl =
    `${config.publicUrl}/.well-known/oauth-protected-resource`;
  const parts = [
    `Bearer realm="mutande"`,
    `resource_metadata="${metadataUrl}"`,
  ];
  if (opts?.error) {
    parts.push(`error="${opts.error}"`);
  }
  if (opts?.description) {
    const desc = opts.description.replace(/\\/g, "\\\\").replace(/"/g, '\\"');
    parts.push(`error_description="${desc}"`);
  }
  return parts.join(", ");
}

export function bearerTokenFromHeader(
  authorization: string | undefined,
): string | null {
  if (!authorization?.startsWith("Bearer ")) return null;
  const token = authorization.slice("Bearer ".length).trim();
  return token || null;
}
