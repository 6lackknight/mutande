import { assertEquals, assertStringIncludes, assertThrows } from "jsr:@std/assert@1";
import {
  assertR2ConfiguredForDeploy,
  loadR2Config,
  mockBlobUrl,
  objectKey,
  presignR2Url,
  r2ObjectUrl,
} from "./r2.ts";

Deno.test("loadR2Config returns null when credentials incomplete", () => {
  const env = new Map<string, string>([
    ["R2_ACCOUNT_ID", "acct"],
    ["R2_ACCESS_KEY_ID", "key"],
    // secret + bucket missing
  ]);
  assertEquals(
    loadR2Config({ get: (k) => env.get(k) }),
    null,
  );
});

Deno.test("assertR2ConfiguredForDeploy hard-fails on deploy without R2", () => {
  const env = new Map<string, string>([["DENO_DEPLOYMENT_ID", "dep-1"]]);
  assertThrows(
    () => assertR2ConfiguredForDeploy({ get: (k) => env.get(k) }),
    Error,
    "R2 credentials must be set in production",
  );
});

Deno.test("assertR2ConfiguredForDeploy allows mock locally", () => {
  const env = new Map<string, string>();
  assertR2ConfiguredForDeploy({ get: (k) => env.get(k) });
});

Deno.test("loadR2Config loads full env", () => {
  const env = new Map<string, string>([
    ["R2_ACCOUNT_ID", "acct123"],
    ["R2_ACCESS_KEY_ID", "AKIA"],
    ["R2_SECRET_ACCESS_KEY", "secret"],
    ["R2_BUCKET", "mutande-blobs"],
    ["R2_PUBLIC_BASE", "https://cdn.example.com"],
  ]);
  const cfg = loadR2Config({ get: (k) => env.get(k) });
  assertEquals(cfg, {
    accountId: "acct123",
    accessKeyId: "AKIA",
    secretAccessKey: "secret",
    bucket: "mutande-blobs",
    publicBase: "https://cdn.example.com",
  });
});

Deno.test("mockBlobUrl shape matches store contract", () => {
  const put = mockBlobUrl("blob-uuid", "PUT");
  assertStringIncludes(put, "blob-uuid");
  assertStringIncludes(put, "upload=1");
  const get = mockBlobUrl("blob-uuid", "GET");
  assertStringIncludes(get, "blob-uuid");
  assertEquals(get.includes("upload="), false);
});

Deno.test("presignR2Url produces AWS4 query shape without network", async () => {
  const cfg = {
    accountId: "deadbeefdeadbeefdeadbeefdeadbeef",
    accessKeyId: "test-access-key",
    secretAccessKey: "test-secret-key-with-enough-length",
    bucket: "mutande-blobs",
  };
  const blobId = "11111111-2222-3333-4444-555555555555";
  const putUrl = await presignR2Url(cfg, blobId, "PUT", {
    contentType: "application/octet-stream",
    expiresIn: 900,
  });
  assertStringIncludes(putUrl, r2ObjectUrl(cfg, blobId));
  assertStringIncludes(putUrl, objectKey(blobId));
  assertStringIncludes(putUrl, "X-Amz-Algorithm=AWS4-HMAC-SHA256");
  assertStringIncludes(putUrl, "X-Amz-Credential=");
  assertStringIncludes(putUrl, "X-Amz-Signature=");
  assertStringIncludes(putUrl, "X-Amz-Expires=900");

  const getUrl = await presignR2Url(cfg, blobId, "GET");
  assertStringIncludes(getUrl, "X-Amz-Algorithm=AWS4-HMAC-SHA256");
  assertStringIncludes(getUrl, "X-Amz-Signature=");
  assertEquals(new URL(getUrl).pathname.includes(objectKey(blobId)), true);
});
