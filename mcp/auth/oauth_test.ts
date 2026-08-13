import { assertEquals, assertRejects } from "jsr:@std/assert@1";
import {
  createTestTokenVerifier,
  expandMcpAudiences,
  protectedResourceMetadata,
  wwwAuthenticateHeader,
} from "./oauth.ts";
import { loadConfig, type McpConfig } from "../config.ts";

const sampleConfig: McpConfig = {
  publicUrl: "https://mcp.mutande.online",
  auth0Domain: "auth.mutande.online",
  auth0Audience: "https://hub.mutande.app",
  auth0McpAudience: null,
  issuerAliases: [],
  hubUrl: "https://hub.mutande.online",
  defaultAgentSlug: "chatgpt",
  port: 3849,
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
