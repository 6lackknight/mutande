const encoder = new TextEncoder();
const decoder = new TextDecoder();

function base64UrlEncode(data: Uint8Array): string {
  const bin = Array.from(data, (b) => String.fromCharCode(b)).join("");
  return btoa(bin).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
}

function base64UrlDecode(str: string): Uint8Array {
  const pad = str.length % 4 === 0 ? "" : "=".repeat(4 - (str.length % 4));
  const base64 = str.replace(/-/g, "+").replace(/_/g, "/") + pad;
  const binary = atob(base64);
  return Uint8Array.from(binary, (c) => c.charCodeAt(0));
}

async function hmacKey(secret: string): Promise<CryptoKey> {
  return crypto.subtle.importKey(
    "raw",
    encoder.encode(secret),
    { name: "HMAC", hash: "SHA-256" },
    false,
    ["sign", "verify"],
  );
}

export async function signJwt(
  payload: Record<string, unknown>,
  secret: string,
  expiresInSec = 3600,
): Promise<string> {
  const header = { alg: "HS256", typ: "JWT" };
  const now = Math.floor(Date.now() / 1000);
  const body = { ...payload, iat: now, exp: now + expiresInSec };
  const segments = [
    base64UrlEncode(encoder.encode(JSON.stringify(header))),
    base64UrlEncode(encoder.encode(JSON.stringify(body))),
  ];
  const data = segments.join(".");
  const key = await hmacKey(secret);
  const sig = await crypto.subtle.sign("HMAC", key, encoder.encode(data));
  return `${data}.${base64UrlEncode(new Uint8Array(sig))}`;
}

export async function verifyJwt(
  token: string,
  secret: string,
): Promise<Record<string, unknown>> {
  const parts = token.split(".");
  if (parts.length !== 3) throw new Error("invalid token");
  const [h, p, s] = parts;
  const data = `${h}.${p}`;
  const key = await hmacKey(secret);
  const sigBytes = base64UrlDecode(s);
  const valid = await crypto.subtle.verify(
    "HMAC",
    key,
    new Uint8Array(sigBytes),
    encoder.encode(data),
  );
  if (!valid) throw new Error("invalid signature");
  const payload = JSON.parse(decoder.decode(base64UrlDecode(p)));
  if (typeof payload.exp === "number" && payload.exp < Math.floor(Date.now() / 1000)) {
    throw new Error("token expired");
  }
  return payload;
}

export function randomToken(): string {
  const bytes = new Uint8Array(32);
  crypto.getRandomValues(bytes);
  return base64UrlEncode(bytes);
}
