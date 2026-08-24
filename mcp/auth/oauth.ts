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

/**
 * Canonical MCP resource Indicator plus the `/mcp` path alias.
 * PRM advertises `https://mcp.mutande.online`; some hosts (e.g. Warp) send
 * `resource=https://mcp.mutande.online/mcp` (connector URL) instead.
 */
export function expandMcpAudiences(
  mcpAudience: string | null | undefined,
): string[] {
  if (!mcpAudience) return [];
  const base = mcpAudience.replace(/\/+$/, "");
  if (!base) return [];
  const out = [base];
  if (!base.endsWith("/mcp")) out.push(`${base}/mcp`);
  return out;
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
    ...new Set([
      config.auth0Audience,
      ...expandMcpAudiences(config.auth0McpAudience),
    ]),
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
export function protectedResourceMetadata(
  config: McpConfig,
  resource: string = config.publicUrl,
) {
  const authorizationServer = `https://${config.auth0Domain}/`;
  return {
    resource,
    authorization_servers: [authorizationServer],
    // Extra fields: Grok-style loaders look here for a sign-in URL and may
    // never fetch AS metadata. RFC 9728 clients ignore unknown properties.
    authorization_endpoint: `${authorizationServer}authorize`,
    token_endpoint: `${authorizationServer}oauth/token`,
    scopes_supported: ["openid", "profile", "email", "offline_access"],
    bearer_methods_supported: ["header"],
    resource_documentation: `${config.publicUrl}/`,
  };
}

/**
 * RFC 8414 Authorization Server Metadata served from the MCP origin.
 *
 * Auth0 is the real AS (authorize / token / JWKS). Hosted MCP is only the
 * resource server, but Grok Bot fetches well-known from the connector URL and
 * does not follow redirects — so this must be JSON, not a 307.
 *
 * RFC 8414 §3.3: `issuer` MUST match the URL used to fetch this document.
 * Advertising Auth0's issuer here makes strict clients discard the whole
 * document (no authorization_endpoint → “didn't provide a sign-in link”).
 *
 * Do not advertise `registration_endpoint` or CIMD: Auth0 DCR is disabled.
 * ChatGPT still discovers Auth0 via PRM `authorization_servers` and Auth0's
 * own well-known (which still lists DCR for the pre-registered tpc_ client).
 */
export function authorizationServerMetadata(
  config: McpConfig,
  issuer: string = config.publicUrl,
) {
  const auth0 = `https://${config.auth0Domain}/`;
  const iss = issuer.replace(/\/+$/, "");
  return {
    issuer: iss,
    authorization_endpoint: `${auth0}authorize`,
    token_endpoint: `${auth0}oauth/token`,
    jwks_uri: `${auth0}.well-known/jwks.json`,
    userinfo_endpoint: `${auth0}userinfo`,
    revocation_endpoint: `${auth0}oauth/revoke`,
    scopes_supported: ["openid", "profile", "email", "offline_access"],
    response_types_supported: ["code"],
    grant_types_supported: ["authorization_code", "refresh_token"],
    code_challenge_methods_supported: ["S256"],
    token_endpoint_auth_methods_supported: ["none", "client_secret_post"],
  };
}

function suffixAfterWellKnown(path: string, marker: string): string | null {
  const idx = path.indexOf(marker);
  if (idx < 0) return null;
  return path.slice(idx + marker.length).replace(/^\/+|\/+$/g, "");
}

/** Resolve RFC 9728 path-inserted resource from a PRM request path. */
export function resourceFromPrmPath(
  publicUrl: string,
  path: string,
): string {
  const base = publicUrl.replace(/\/+$/, "");
  if (path.startsWith("/mcp/") || path === "/mcp") return `${base}/mcp`;
  const after = suffixAfterWellKnown(
    path,
    "/.well-known/oauth-protected-resource",
  );
  if (after === null) return base;
  return after ? `${base}/${after}` : base;
}

/**
 * RFC 8414 §3.3 issuer for AS/OIDC metadata served on this origin.
 * Must equal the identifier the client used to build the well-known URL.
 */
export function issuerFromAsPath(publicUrl: string, path: string): string {
  const base = publicUrl.replace(/\/+$/, "");
  if (path.startsWith("/mcp/") || path === "/mcp") return `${base}/mcp`;
  for (
    const marker of [
      "/.well-known/oauth-authorization-server",
      "/.well-known/openid-configuration",
    ]
  ) {
    const after = suffixAfterWellKnown(path, marker);
    if (after === null) continue;
    return after ? `${base}/${after}` : base;
  }
  return base;
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

/** Hub-minted MCP connector secret (`mtc_…`), not an Auth0 access token. */
export const MCP_CONNECTOR_TOKEN_PREFIX = "mtc_";

export function isMcpConnectorToken(token: string): boolean {
  return (
    token.startsWith(MCP_CONNECTOR_TOKEN_PREFIX) &&
    token.length >= MCP_CONNECTOR_TOKEN_PREFIX.length + 16
  );
}

/**
 * Connector secret from Grok-style custom headers, or Bearer `mtc_…`.
 * Dedicated headers win so the Plugins form does not have to use OAuth.
 */
export function connectorTokenFromHeaders(opts: {
  authorization?: string;
  connector?: string;
  apiKey?: string;
}): string | null {
  const dedicated = opts.connector?.trim() || opts.apiKey?.trim() || "";
  if (dedicated) return dedicated;
  const bearer = bearerTokenFromHeader(opts.authorization);
  if (bearer && isMcpConnectorToken(bearer)) return bearer;
  return null;
}
