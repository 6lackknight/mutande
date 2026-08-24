import { assertEquals, assertRejects } from "jsr:@std/assert@1";
import {
  authorizationServerMetadata,
  createTestTokenVerifier,
  expandMcpAudiences,
  protectedResourceMetadata,
  resourceFromPrmPath,
  wwwAuthenticateHeader,
} from "./oauth.ts";
import { loadConfig, type McpConfig } from "../config.ts";
import { createOauthRoutes } from "../routes/oauth.ts";

const sampleConfig: McpConfig = {
  publicUrl: "https://mcp.mutande.online",
  auth0Domain: "auth.mutande.online",
  auth0Audience: "https://hub.mutande.app",
  auth0McpAudience: null,
  issuerAliases: [],
  hubUrl: "https://hub.mutande.online",
  defaultAgentSlug: "chatgpt",
  port: 3849,
  openaiAppsChallenge: null,
};

Deno.test("protected resource metadata points at Auth0", () => {
  const meta = protectedResourceMetadata(sampleConfig);
  assertEquals(meta.resource, "https://mcp.mutande.online");
  assertEquals(meta.authorization_servers, ["https://auth.mutande.online/"]);
  assertEquals(meta.bearer_methods_supported, ["header"]);
});

Deno.test("www-authenticate includes resource_metadata URL", () => {
  const header = wwwAuthenticateHeader(sampleConfig);
  assertEquals(
    header.includes(
      'resource_metadata="https://mcp.mutande.online/.well-known/oauth-protected-resource"',
    ),
    true,
  );
});

Deno.test("www-authenticate can include invalid_token error", () => {
  const header = wwwAuthenticateHeader(sampleConfig, {
    error: "invalid_token",
    description: "Invalid or expired token",
  });
  assertEquals(header.includes('error="invalid_token"'), true);
  assertEquals(header.includes("Invalid or expired token"), true);
});

Deno.test("test verifier accepts signed tokens", async () => {
  const { verifier, signToken } = await createTestTokenVerifier({
    audience: "https://hub.mutande.app",
  });
  const token = await signToken({ sub: "auth0|user1", email: "a@b.co" });
  const claims = await verifier.verifyAccessToken(token);
  assertEquals(claims.sub, "auth0|user1");
  assertEquals(claims.email, "a@b.co");
});

Deno.test("test verifier rejects garbage", async () => {
  const { verifier } = await createTestTokenVerifier();
  await assertRejects(() => verifier.verifyAccessToken("not.a.jwt"));
});

Deno.test(
  "dual audience accepts ChatGPT-shaped MCP resource token",
  async () => {
    // Mimics Auth0 access token after ChatGPT DCR: aud = PRM resource,
    // iss = custom domain, azp = third-party client_id (tpc_…).
    const mcpAud = "https://mcp.mutande.online";
    const hubAud = "https://hub.mutande.app";
    const { verifier, signToken } = await createTestTokenVerifier({
      issuer: "https://auth.mutande.online/",
      audience: [hubAud, mcpAud],
    });
    const token = await signToken(
      { sub: "auth0|chatgpt-user", email: "u@acme.co" },
      { audience: mcpAud, azp: "tpc_chatgpt_connector" },
    );
    const claims = await verifier.verifyAccessToken(token);
    assertEquals(claims.sub, "auth0|chatgpt-user");
    assertEquals(claims.email, "u@acme.co");
  },
);

Deno.test("dual audience rejects unrelated aud", async () => {
  const { verifier, signToken } = await createTestTokenVerifier({
    issuer: "https://auth.mutande.online/",
    audience: ["https://hub.mutande.app", "https://mcp.mutande.online"],
  });
  const token = await signToken(
    { sub: "auth0|x" },
    { audience: "https://chevrondigital.auth0.com/userinfo" },
  );
  await assertRejects(() => verifier.verifyAccessToken(token));
});

Deno.test("expandMcpAudiences adds /mcp path alias", () => {
  assertEquals(expandMcpAudiences(null), []);
  assertEquals(expandMcpAudiences(""), []);
  assertEquals(expandMcpAudiences("https://mcp.mutande.online"), [
    "https://mcp.mutande.online",
    "https://mcp.mutande.online/mcp",
  ]);
  assertEquals(expandMcpAudiences("https://mcp.mutande.online/"), [
    "https://mcp.mutande.online",
    "https://mcp.mutande.online/mcp",
  ]);
  // Already path-shaped — do not double-append.
  assertEquals(expandMcpAudiences("https://mcp.mutande.online/mcp"), [
    "https://mcp.mutande.online/mcp",
  ]);
});

Deno.test(
  "triple audience accepts Warp-shaped MCP /mcp resource token",
  async () => {
    const hubAud = "https://hub.mutande.app";
    const mcpAud = "https://mcp.mutande.online";
    const warpAud = "https://mcp.mutande.online/mcp";
    const { verifier, signToken } = await createTestTokenVerifier({
      issuer: "https://auth.mutande.online/",
      audience: [hubAud, ...expandMcpAudiences(mcpAud)],
    });
    const token = await signToken(
      { sub: "auth0|warp-user", email: "u@acme.co" },
      { audience: warpAud, azp: "tpc_warp_connector" },
    );
    const claims = await verifier.verifyAccessToken(token);
    assertEquals(claims.sub, "auth0|warp-user");
    assertEquals(claims.email, "u@acme.co");
  },
);

Deno.test("loadConfig defaults AUTH0_MCP_AUDIENCE to publicUrl", () => {
  const cfg = loadConfig({
    get(key: string) {
      const map: Record<string, string> = {
        MCP_PUBLIC_URL: "https://mcp.mutande.online",
        AUTH0_DOMAIN: "auth.mutande.online",
        AUTH0_AUDIENCE: "https://hub.mutande.app",
      };
      return map[key];
    },
  });
  assertEquals(cfg.auth0McpAudience, "https://mcp.mutande.online");
  assertEquals(cfg.issuerAliases.includes("chevrondigital.auth0.com"), true);
  assertEquals(cfg.openaiAppsChallenge, null);
});

Deno.test("loadConfig empty AUTH0_MCP_AUDIENCE disables extra aud", () => {
  const cfg = loadConfig({
    get(key: string) {
      const map: Record<string, string> = {
        MCP_PUBLIC_URL: "https://mcp.mutande.online",
        AUTH0_DOMAIN: "auth.mutande.online",
        AUTH0_AUDIENCE: "https://hub.mutande.app",
        AUTH0_MCP_AUDIENCE: "",
      };
      return map[key];
    },
  });
  assertEquals(cfg.auth0McpAudience, null);
});

Deno.test("authorization server metadata is Auth0 JSON, not a redirect", () => {
  const meta = authorizationServerMetadata(sampleConfig);
  assertEquals(meta.issuer, "https://auth.mutande.online/");
  assertEquals(meta.authorization_endpoint, "https://auth.mutande.online/authorize");
  assertEquals(
    meta.registration_endpoint,
    "https://auth.mutande.online/oidc/register",
  );
  assertEquals(meta.code_challenge_methods_supported, ["S256"]);
  assertEquals(meta.client_id_metadata_document_supported, true);
});

Deno.test("resourceFromPrmPath keeps origin PRM, suffixes /mcp", () => {
  const base = "https://mcp.mutande.online";
  assertEquals(
    resourceFromPrmPath(base, "/.well-known/oauth-protected-resource"),
    base,
  );
  assertEquals(
    resourceFromPrmPath(base, "/.well-known/oauth-protected-resource/mcp"),
    `${base}/mcp`,
  );
  assertEquals(
    resourceFromPrmPath(base, "/mcp/.well-known/oauth-protected-resource"),
    `${base}/mcp`,
  );
});

Deno.test("AS metadata routes return JSON with registration_endpoint", async () => {
  const routes = createOauthRoutes(sampleConfig);
  for (
    const path of [
      "/.well-known/oauth-authorization-server",
      "/.well-known/oauth-authorization-server/mcp",
      "/mcp/.well-known/oauth-authorization-server",
      "/.well-known/openid-configuration",
      "/mcp/.well-known/openid-configuration",
    ]
  ) {
    const hit = await routes.request(path);
    assertEquals(hit.status, 200, path);
    assertEquals(hit.headers.get("access-control-allow-origin"), "*");
    const body = await hit.json() as { registration_endpoint?: string };
    assertEquals(
      body.registration_endpoint,
      "https://auth.mutande.online/oidc/register",
      path,
    );
  }
});

Deno.test("path-aware PRM resource matches /mcp connector URL", async () => {
  const routes = createOauthRoutes(sampleConfig);
  const origin = await routes.request("/.well-known/oauth-protected-resource");
  assertEquals((await origin.json() as { resource: string }).resource, sampleConfig.publicUrl);

  const pathAware = await routes.request(
    "/.well-known/oauth-protected-resource/mcp",
  );
  assertEquals(
    (await pathAware.json() as { resource: string }).resource,
    "https://mcp.mutande.online/mcp",
  );

  const underMcp = await routes.request(
    "/mcp/.well-known/oauth-protected-resource",
  );
  assertEquals(
    (await underMcp.json() as { resource: string }).resource,
    "https://mcp.mutande.online/mcp",
  );
});

Deno.test("openai-apps-challenge serves the exact token", async () => {
  const routes = createOauthRoutes({
    ...sampleConfig,
    openaiAppsChallenge: "tok_review_only",
  });
  const hit = await routes.request("/.well-known/openai-apps-challenge");
  assertEquals(hit.status, 200);
  assertEquals(await hit.text(), "tok_review_only");
  assertEquals(hit.headers.get("content-type")?.includes("text/plain"), true);

  const missing = await createOauthRoutes(sampleConfig).request(
    "/.well-known/openai-apps-challenge",
  );
  assertEquals(missing.status, 404);
});
