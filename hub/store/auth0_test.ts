import { assertEquals, assertRejects } from "jsr:@std/assert@1";
import { createTestTokenVerifier } from "./auth0.ts";
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
