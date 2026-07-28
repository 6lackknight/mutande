/** Per-recipient content-key wrap (matches `proto/envelope.schema.json`). */
export interface Wrap {
  recipient: number[];
  ephemeral_public: number[];
  boxed_cek: number[];
}

export interface Envelope {
  version: number;
  content_nonce: number[];
  ciphertext: number[];
  wraps: Wrap[];
  blob_id?: string;
  sha256?: string;
  [key: string]: unknown;
}

export type UserRole = "org_admin" | "member";
export type DevicePlatform = "macos" | "ios" | "web";

export interface User {
  id: string;
  auth0_sub: string;
  email?: string;
  handle?: string;
  org_id?: string;
  role?: UserRole;
  pubkey?: string;
  created_at: string;
}

export interface Device {
  id: string;
  user_id: string;
  pubkey: string;
  platform: DevicePlatform;
  created_at: string;
}

export interface Org {
  id: string;
  slug: string;
  name: string;
  created_at: string;
}

export interface Invite {
  code: string;
  org_id: string;
  created_by?: string;
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
  pubkey: string | null;
  devices: Array<{ pubkey: string; platform: DevicePlatform }>;
}

export interface Auth0Claims { sub: string; email?: string; }

export interface AuthContext {
  userId: string;
  orgId: string;
  handle: string;
  role: UserRole;
  auth0Sub: string;
}

export interface RegisterInput {
  invite_code: string;
  handle: string;
  pubkey: string;
}

export interface CreateOrgInput {
  slug: string;
  name?: string;
  handle?: string;
}

export interface JoinOrgInput {
  invite_code: string;
  /** Defaults to email-local@org when omitted. */
  handle?: string;
}

export interface RegisterDeviceInput {
  pubkey: string;
  platform: DevicePlatform;
}

export interface MeResponse {
  auth0_sub: string;
  email?: string;
  needs_onboarding: boolean;
  /** Compat alias for !needs_onboarding. */
  onboarded?: boolean;
  user?: User;
  org?: Org;
}

export interface CreateThreadInput { to: string; envelope: Envelope; }
export interface ReplyInput { envelope: Envelope; }
export type ThreadFilter = "needs_action" | "open" | "closed";

export const MAX_ENVELOPE_BYTES = 60 * 1024;
export const ORG_BLOB_QUOTA_BYTES = 500 * 1024 * 1024;
export const BLOB_URL_BASE = "https://blobs.mutande.app";
