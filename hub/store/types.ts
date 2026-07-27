/** Per-recipient content-key wrap (matches `proto/envelope.schema.json`). */
export interface Wrap {
  recipient: number[];
  ephemeral_public: number[];
  boxed_cek: number[];
}

/**
 * Hub-visible wire envelope — opaque to the hub (size-checked JSON only).
 * Shape matches `proto/envelope.schema.json` / mutande-core serde (byte arrays).
 */
export interface Envelope {
  version: number;
  content_nonce: number[];
  /** Inline AEAD ciphertext; empty when content lives in R2 (`blob_id`). */
  ciphertext: number[];
  wraps: Wrap[];
  /** R2 object id when payload is a blob (ciphertext uploaded separately). */
  blob_id?: string;
  /** Hex SHA-256 of the blob ciphertext bytes. */
  sha256?: string;
  [key: string]: unknown;
}

export interface User {
  id: string;
  handle: string;
  org_id: string;
  pubkey: string;
  created_at: string;
}

export interface Org {
  id: string;
  slug: string;
  created_at: string;
}

export interface Invite {
  code: string;
  org_id: string;
  created_at: string;
  used_by?: string;
}

export interface ThreadMeta {
  id: string;
  kind: "direct" | "broadcast";
  status: "open" | "closed";
  from: string;
  from_user_id: string;
  audience: string;
  org_id: string;
  participant_count: number;
  reply_count: number;
  your_status?: "pending" | "replied";
  created_at: string;
  updated_at: string;
}

export interface InboxEntry {
  thread_id: string;
  your_status: "pending" | "replied";
  role: "sender" | "recipient";
  updated_at: string;
}

export interface ThreadMessage {
  id: string;
  thread_id: string;
  from_user_id: string;
  from_handle: string;
  envelope: Envelope;
  created_at: string;
  /** Broadcast replies visible to sender only (v1). */
  sender_only?: boolean;
}

export interface Draft {
  id: string;
  user_id: string;
  org_id: string;
  envelope: Envelope;
  created_at: string;
  updated_at: string;
}

export interface BlobMeta {
  id: string;
  org_id: string;
  owner_user_id: string;
  size_bytes: number;
  content_type?: string;
  created_at: string;
}

export interface Contact {
  handle: string;
  /** Omitted for synthetic broadcast handle `@all@org`. */
  pubkey: string | null;
}

export interface AuthContext {
  userId: string;
  orgId: string;
  handle: string;
}

export interface RegisterInput {
  invite_code: string;
  handle: string;
  pubkey: string;
}

export interface CreateThreadInput {
  to: string;
  envelope: Envelope;
}

export interface ReplyInput {
  envelope: Envelope;
}

export type ThreadFilter = "needs_action" | "open" | "closed";

export const MAX_ENVELOPE_BYTES = 60 * 1024;
export const ORG_BLOB_QUOTA_BYTES = 500 * 1024 * 1024;
export const BLOB_URL_BASE = "https://blobs.mutande.app";
