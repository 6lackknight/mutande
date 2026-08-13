import { assertEquals, assertRejects } from "jsr:@std/assert@1";
import { createTestTokenVerifier, expandMcpAudiences } from "./auth0.ts";
import { HubError } from "./errors.ts";

Deno.test("test token verifier accepts signed Auth0-shaped JWT", async () => {
  const { verifier, signToken } = await createTestTokenVerifier();
  const token = await signToken({ sub: "auth0|alice", email: "alice@example.com" });
  const claims = await verifier.verifyAccessToken(token);
  assertEquals(claims.sub, "auth0|alice");
  assertEquals(claims.email, "alice@example.com");
});

Deno.test("test token verifier rejects garbage token", async () => {
  const { verifier } = await createTestTokenVerifier();
  await assertRejects(
    () => verifier.verifyAccessToken("not.a.jwt"),
    HubError,
    "Invalid or expired token",
  );
});

Deno.test("test token verifier rejects wrong audience", async () => {
  const a = await createTestTokenVerifier({ audience: "https://hub.a" });
  const b = await createTestTokenVerifier({ audience: "https://hub.b" });
  const token = await a.signToken({ sub: "auth0|x" });
  await assertRejects(() => b.verifier.verifyAccessToken(token), HubError);
});

Deno.test("createAuth0Verifier dual aud accepts MCP resource claim", async () => {
  // Mirror hub createAuth0Verifier audience list construction + jose verify.
  const jose = await import("jose");
  const hubAud = "https://hub.mutande.app";
  const mcpAud = "https://mcp.mutande.online";
  const issuer = "https://auth.mutande.online/";
  const { publicKey, privateKey } = await jose.generateKeyPair("RS256");
  const jwk = await jose.exportJWK(publicKey);
  jwk.alg = "RS256";
  jwk.use = "sig";
  jwk.kid = "test-key";
  const jwks = jose.createLocalJWKSet({ keys: [jwk] });

  const token = await new jose.SignJWT({ azp: "tpc_chatgpt" })
    .setProtectedHeader({ alg: "RS256", kid: "test-key" })
    .setSubject("auth0|u")
    .setIssuer(issuer)
    .setAudience(mcpAud)
    .setIssuedAt()
    .setExpirationTime("1h")
    .sign(privateKey);

  const { payload } = await jose.jwtVerify(token, jwks, {
    issuer,
    audience: [hubAud, mcpAud],
  });
  assertEquals(payload.sub, "auth0|u");
  assertEquals(payload.aud, mcpAud);
});

Deno.test("expandMcpAudiences adds /mcp path alias", () => {
  assertEquals(expandMcpAudiences("https://mcp.mutande.online"), [
    "https://mcp.mutande.online",
    "https://mcp.mutande.online/mcp",
  ]);
  assertEquals(expandMcpAudiences("https://mcp.mutande.online/mcp"), [
    "https://mcp.mutande.online/mcp",
  ]);
});

Deno.test("createAuth0Verifier accepts Warp /mcp resource claim", async () => {
  const jose = await import("jose");
  const hubAud = "https://hub.mutande.app";
  const mcpAud = "https://mcp.mutande.online";
  const warpAud = "https://mcp.mutande.online/mcp";
  const issuer = "https://auth.mutande.online/";
  const { publicKey, privateKey } = await jose.generateKeyPair("RS256");
  const jwk = await jose.exportJWK(publicKey);
  jwk.alg = "RS256";
  jwk.use = "sig";
  jwk.kid = "test-key";
  const jwks = jose.createLocalJWKSet({ keys: [jwk] });

  const token = await new jose.SignJWT({ azp: "tpc_warp" })
    .setProtectedHeader({ alg: "RS256", kid: "test-key" })
    .setSubject("auth0|warp")
    .setIssuer(issuer)
    .setAudience(warpAud)
    .setIssuedAt()
    .setExpirationTime("1h")
    .sign(privateKey);

  const { payload } = await jose.jwtVerify(token, jwks, {
    issuer,
    audience: [hubAud, ...expandMcpAudiences(mcpAud)],
  });
  assertEquals(payload.sub, "auth0|warp");
  assertEquals(payload.aud, warpAud);
});
