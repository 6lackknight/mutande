/**
 * app_envelope split store (directory.prd §4.2.1 / §4.6).
 *
 * Separate from the blind E2E envelope path. Payloads are hub-readable for
 * web/MCP delivery. Retention hard upper bound: APP_ENVELOPE_RETENTION_MS.
 *
 * Encryption at rest: AES-256-GCM with hub-held key from APP_ENVELOPE_KEY
 * (base64 32 bytes). Protects against storage compromise, NOT the hub operator.
 *
 * TODO(§4.6): when APP_ENVELOPE_KEY is unset, payloads are stored plaintext at
 * rest (local/dev interim). Prod must set APP_ENVELOPE_KEY. Formalize ops
 * incident-access logging before L2 ships to production traffic.
 */

import { HubError } from "./errors.ts";
import type {
  Agent,
  AppEnvelopePayload,
  ThreadEncryptionMode,
} from "./types.ts";
import {
  APP_ENVELOPE_RETENTION_MS,
  MAX_APP_ENVELOPE_BYTES,
} from "./types.ts";

export { APP_ENVELOPE_RETENTION_MS, APP_ENVELOPE_RETENTION_DAYS } from "./types.ts";

/** Stored row under `["app_envelopes", threadId, messageId]`. */
export interface AppEnvelopeRecord {
  thread_id: string;
  message_id: string;
  from_user_id: string;
  from_agent_id?: string;
  created_at: string;
  /** ISO expiry (= created_at + 30d); also enforced via KV expireIn. */
  expires_at: string;
  /**
   * `"aes-gcm"` when sealed with hub key; `"plaintext"` interim when key unset.
   */
  at_rest: "aes-gcm" | "plaintext";
  /** UTF-8 JSON plaintext (interim) or base64(nonce||ciphertext||tag). */
  body: string;
}

export function appEnvelopeKey(threadId: string, messageId: string): Deno.KvKey {
  return ["app_envelopes", threadId, messageId];
}

export function appEnvelopesPrefix(threadId: string): Deno.KvKey {
  return ["app_envelopes", threadId];
}

export function assertAppEnvelopeSize(payload: AppEnvelopePayload): void {
  const size = new TextEncoder().encode(JSON.stringify(payload)).byteLength;
  if (size > MAX_APP_ENVELOPE_BYTES) {
    throw new HubError(
      `app_envelope too large (${size} bytes, max ${MAX_APP_ENVELOPE_BYTES})`,
      "envelope_too_large",
      413,
    );
  }
}

export function assertExclusiveWireUnit(input: {
  envelope?: unknown;
  app_envelope?: unknown;
}): "e2e" | "app_envelope" {
  const hasE2e = input.envelope != null;
  const hasApp = input.app_envelope != null;
  if (hasE2e && hasApp) {
    throw new HubError(
      "Never mix E2E envelope and app_envelope in one wire unit",
      "invalid_argument",
      400,
    );
  }
  if (!hasE2e && !hasApp) {
    throw new HubError(
      "Either envelope or app_envelope is required",
      "invalid_argument",
      400,
    );
  }
  return hasApp ? "app_envelope" : "e2e";
}

/**
 * Resolve thread mode from participant agents + L3/L4 flags (§4.2 / §7.3).
 * Web (mcp) / external / enterprise → app_envelope; all-sidecar same-org → e2e.
 */
export function resolveThreadEncryptionMode(opts: {
  sender: Agent;
  /** Direct audience agent; omitted for broadcast/my-agents fan-in. */
  audience?: Agent | null;
  /** Extra agents that will see the thread (e.g. my-agents roster). */
  extraParticipants?: Agent[];
  /** L3 — true when any participant is an approved external contact. */
  hasExternalContact?: boolean;
  /** L4 — true when any participant is a public enterprise listing. */
  hasEnterpriseAgent?: boolean;
}): ThreadEncryptionMode {
  // External contact / enterprise listing always force app_envelope.
  if (opts.hasExternalContact || opts.hasEnterpriseAgent) {
    return "app_envelope";
  }

  const agents = [
    opts.sender,
    ...(opts.audience ? [opts.audience] : []),
    ...(opts.extraParticipants ?? []),
  ];

  for (const a of agents) {
    if (a.transport === "mcp") return "app_envelope";
    if (a.trust_tier === "external" || a.trust_tier === "enterprise") {
      return "app_envelope";
    }
  }

  // Web slots can only start non-E2E threads (§4.2 rule 2) — covered by sender.transport.
  return "e2e";
}

/** L3: use HubStore.hasApprovedExternalContact / pairing APIs instead. */
export function isExternalContactStub(_handle: string): boolean {
  return false;
}

/** L4: enterprise registry agents carry trust_tier enterprise after publish. */
export function isEnterpriseAgentStub(agent: Agent | null | undefined): boolean {
  return agent?.trust_tier === "enterprise";
}

function envKeyBytes(): Uint8Array | null {
  const raw = Deno.env.get("APP_ENVELOPE_KEY")?.trim();
  if (!raw) return null;
  try {
    const bytes = Uint8Array.from(atob(raw), (c) => c.charCodeAt(0));
    if (bytes.byteLength !== 32) {
      console.warn(
        "[hub] APP_ENVELOPE_KEY must be base64 of 32 bytes; falling back to plaintext-at-rest",
      );
      return null;
    }
    return bytes;
  } catch {
    console.warn(
      "[hub] APP_ENVELOPE_KEY is not valid base64; falling back to plaintext-at-rest",
    );
    return null;
  }
}

let cachedCryptoKey: CryptoKey | null | undefined;

async function getCryptoKey(): Promise<CryptoKey | null> {
  if (cachedCryptoKey !== undefined) return cachedCryptoKey;
  const bytes = envKeyBytes();
  if (!bytes) {
    cachedCryptoKey = null;
    return null;
  }
  // Copy into a fresh ArrayBuffer for DOM BufferSource typing under Deno.
  const ab = new ArrayBuffer(bytes.byteLength);
  new Uint8Array(ab).set(bytes);
  cachedCryptoKey = await crypto.subtle.importKey(
    "raw",
    ab,
    { name: "AES-GCM" },
    false,
    ["encrypt", "decrypt"],
  );
  return cachedCryptoKey;
}

/** Test helper — clear cached key after env changes. */
export function resetAppEnvelopeKeyCache(): void {
  cachedCryptoKey = undefined;
}

function b64(bytes: Uint8Array): string {
  let s = "";
  for (const b of bytes) s += String.fromCharCode(b);
  return btoa(s);
}

function fromB64(s: string): Uint8Array {
  return Uint8Array.from(atob(s), (c) => c.charCodeAt(0));
}

export async function sealAppEnvelope(
  payload: AppEnvelopePayload,
): Promise<{ at_rest: "aes-gcm" | "plaintext"; body: string }> {
  assertAppEnvelopeSize(payload);
  const json = JSON.stringify(payload);
  const key = await getCryptoKey();
  if (!key) {
    // TODO(§4.6): plaintext-at-rest interim — set APP_ENVELOPE_KEY in prod.
    return { at_rest: "plaintext", body: json };
  }
  const nonce = crypto.getRandomValues(new Uint8Array(12));
  const plaintext = new TextEncoder().encode(json);
  const cipherBuf = await crypto.subtle.encrypt(
    { name: "AES-GCM", iv: nonce },
    key,
    plaintext,
  );
  const cipher = new Uint8Array(cipherBuf);
  const packed = new Uint8Array(nonce.length + cipher.length);
  packed.set(nonce, 0);
  packed.set(cipher, nonce.length);
  return { at_rest: "aes-gcm", body: b64(packed) };
}

export async function openAppEnvelope(
  record: AppEnvelopeRecord,
): Promise<AppEnvelopePayload> {
  if (record.at_rest === "plaintext") {
    return JSON.parse(record.body) as AppEnvelopePayload;
  }
  const key = await getCryptoKey();
  if (!key) {
    throw new HubError(
      "Cannot decrypt app_envelope: APP_ENVELOPE_KEY unset",
      "internal",
      500,
    );
  }
  const packed = fromB64(record.body);
  if (packed.byteLength < 13) {
    throw new HubError("Corrupt app_envelope record", "internal", 500);
  }
  const nonce = packed.slice(0, 12);
  const cipher = packed.slice(12);
  const plainBuf = await crypto.subtle.decrypt(
    { name: "AES-GCM", iv: nonce },
    key,
    cipher,
  );
  return JSON.parse(new TextDecoder().decode(plainBuf)) as AppEnvelopePayload;
}

export function retentionExpiresAt(createdAtIso: string): string {
  const t = Date.parse(createdAtIso);
  return new Date(t + APP_ENVELOPE_RETENTION_MS).toISOString();
}

export async function buildAppEnvelopeRecord(opts: {
  threadId: string;
  messageId: string;
  fromUserId: string;
  fromAgentId?: string;
  createdAt: string;
  payload: AppEnvelopePayload;
}): Promise<AppEnvelopeRecord> {
  const sealed = await sealAppEnvelope(opts.payload);
  return {
    thread_id: opts.threadId,
    message_id: opts.messageId,
    from_user_id: opts.fromUserId,
    from_agent_id: opts.fromAgentId,
    created_at: opts.createdAt,
    expires_at: retentionExpiresAt(opts.createdAt),
    at_rest: sealed.at_rest,
    body: sealed.body,
  };
}

/** Normalize legacy ThreadMeta rows that predate encryption_mode. */
export function normalizeEncryptionMode(
  mode: ThreadEncryptionMode | undefined | null,
): ThreadEncryptionMode {
  return mode === "app_envelope" ? "app_envelope" : "e2e";
}
