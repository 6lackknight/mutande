/**
 * Cloudflare R2 / S3-compatible presigned URLs (AWS Signature V4 via aws4fetch).
 * When credentials are missing, returns mock URLs with the same response shape.
 */

import { AwsClient } from "aws4fetch";
import { BLOB_URL_BASE } from "./types.ts";

export const PRESIGN_TTL_SECONDS = 15 * 60;

export interface R2Config {
  accountId: string;
  accessKeyId: string;
  secretAccessKey: string;
  bucket: string;
  /** Optional custom base; unused for signing (signing uses the S3 API host). */
  publicBase?: string;
}

export type PresignMethod = "PUT" | "GET";

export function loadR2Config(
  env: { get(key: string): string | undefined } = Deno.env,
): R2Config | null {
  const accountId = env.get("R2_ACCOUNT_ID")?.trim();
  const accessKeyId = env.get("R2_ACCESS_KEY_ID")?.trim();
  const secretAccessKey = env.get("R2_SECRET_ACCESS_KEY")?.trim();
  const bucket = env.get("R2_BUCKET")?.trim();
  if (!accountId || !accessKeyId || !secretAccessKey || !bucket) {
    return null;
  }
  const publicBase = env.get("R2_PUBLIC_BASE")?.trim() || undefined;
  return { accountId, accessKeyId, secretAccessKey, bucket, publicBase };
}

/** Hard-fail on Deno Deploy when R2 is unset (mirrors JWT_SECRET guard). */
export function assertR2ConfiguredForDeploy(
  env: { get(key: string): string | undefined } = Deno.env,
): void {
  if (env.get("DENO_DEPLOYMENT_ID") && !loadR2Config(env)) {
    throw new Error(
      "R2 credentials must be set in production (R2_ACCOUNT_ID, R2_ACCESS_KEY_ID, R2_SECRET_ACCESS_KEY, R2_BUCKET)",
    );
  }
}

export function mockBlobUrl(blobId: string, method: PresignMethod): string {
  const base = (Deno.env.get("R2_PUBLIC_BASE")?.trim() || BLOB_URL_BASE).replace(
    /\/$/,
    "",
  );
  if (method === "PUT") {
    return `${base}/${blobId}?upload=1`;
  }
  return `${base}/${blobId}`;
}

export function objectKey(blobId: string): string {
  return `blobs/${blobId}`;
}

export function r2ObjectUrl(cfg: R2Config, blobId: string): string {
  const key = objectKey(blobId);
  return `https://${cfg.accountId}.r2.cloudflarestorage.com/${cfg.bucket}/${key}`;
}

/** Presign PUT/GET. Pure crypto — no network. */
export async function presignR2Url(
  cfg: R2Config,
  blobId: string,
  method: PresignMethod,
  opts?: { contentType?: string; expiresIn?: number },
): Promise<string> {
  const expiresIn = opts?.expiresIn ?? PRESIGN_TTL_SECONDS;
  const client = new AwsClient({
    accessKeyId: cfg.accessKeyId,
    secretAccessKey: cfg.secretAccessKey,
    service: "s3",
    region: "auto",
  });

  const url = new URL(r2ObjectUrl(cfg, blobId));
  url.searchParams.set("X-Amz-Expires", String(expiresIn));

  const headers: Record<string, string> = {};
  if (method === "PUT" && opts?.contentType) {
    headers["Content-Type"] = opts.contentType;
  }

  const signed = await client.sign(
    new Request(url.toString(), { method, headers }),
    { aws: { signQuery: true } },
  );
  return signed.url;
}

export type BlobUrlMode = "r2" | "mock";

let mockWarningLogged = false;

export async function createBlobUrls(
  blobId: string,
  method: PresignMethod,
  opts?: { contentType?: string },
): Promise<{ url: string; mode: BlobUrlMode; expires_at: string }> {
  assertR2ConfiguredForDeploy();
  const expiresAt = new Date(Date.now() + PRESIGN_TTL_SECONDS * 1000).toISOString();
  const cfg = loadR2Config();
  if (!cfg) {
    if (!mockWarningLogged) {
      console.warn(
        "[mutande-hub] R2 credentials missing (need R2_ACCOUNT_ID, R2_ACCESS_KEY_ID, R2_SECRET_ACCESS_KEY, R2_BUCKET); using mock blob URLs",
      );
      mockWarningLogged = true;
    }
    return { url: mockBlobUrl(blobId, method), mode: "mock", expires_at: expiresAt };
  }

  const url = await presignR2Url(cfg, blobId, method, {
    contentType: opts?.contentType,
    expiresIn: PRESIGN_TTL_SECONDS,
  });
  return { url, mode: "r2", expires_at: expiresAt };
}
