import { assertEquals, assertRejects } from "jsr:@std/assert@1";
import {
  createTestTokenVerifier,
  protectedResourceMetadata,
  wwwAuthenticateHeader,
} from "./oauth.ts";
import type { McpConfig } from "../config.ts";

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
