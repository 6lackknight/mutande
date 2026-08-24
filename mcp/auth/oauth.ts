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
    scopes_supported: ["openid", "profile", "email", "offline_access"],
    bearer_methods_supported: ["header"],
    resource_documentation: `${config.publicUrl}/`,
  };
}

/**
 * RFC 8414 Authorization Server Metadata for Auth0.
 *
 * Hosted MCP is the resource server; Auth0 is the AS. Some MCP loaders
 * (Grok Bot) fetch this from the MCP origin and do not follow redirects, so
 * this must be JSON — not a 307 to Auth0.
 */
export function authorizationServerMetadata(config: McpConfig) {
  const issuer = `https://${config.auth0Domain}/`;
  return {
    issuer,
    authorization_endpoint: `${issuer}authorize`,
    token_endpoint: `${issuer}oauth/token`,
    registration_endpoint: `${issuer}oidc/register`,
    jwks_uri: `${issuer}.well-known/jwks.json`,
    userinfo_endpoint: `${issuer}userinfo`,
    revocation_endpoint: `${issuer}oauth/revoke`,
    scopes_supported: ["openid", "profile", "email", "offline_access"],
    response_types_supported: ["code"],
    grant_types_supported: ["authorization_code", "refresh_token"],
    code_challenge_methods_supported: ["S256"],
    token_endpoint_auth_methods_supported: ["none", "client_secret_post"],
    client_id_metadata_document_supported: true,
  };
}

/** Resolve RFC 9728 path-inserted resource from a PRM request path. */
export function resourceFromPrmPath(
  publicUrl: string,
  path: string,
): string {
  const base = publicUrl.replace(/\/+$/, "");
  if (path.startsWith("/mcp/") || path === "/mcp") return `${base}/mcp`;
  const marker = "/.well-known/oauth-protected-resource";
  const idx = path.indexOf(marker);
  if (idx < 0) return base;
  const after = path.slice(idx + marker.length).replace(/^\/+|\/+$/g, "");
  return after ? `${base}/${after}` : base;
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
