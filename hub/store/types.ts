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

/** In-app pilot / product feedback (not agent mail). */
export interface Feedback {
  id: string;
  created_at: string;
  user_id: string;
  handle: string;
  org_id: string;
  auth0_sub: string;
  email?: string;
  message: string;
  category?: string;
  app_version?: string;
  platform: "macos" | "ios" | "web";
}

/** Marketing waitlist survey (public; not agent mail). */
export interface WaitlistEntry {
  id: string;
  created_at: string;
  email: string;
  /** Selected AI tools (multi-select). */
  ai_hosts: string[];
  oses: string[];
  /** How often they move text/docs between AI tools. */
  share_frequency: string;
  /** How they usually move that material (multi-select). */
  share_methods: string[];
  source: "web";
}

export interface Invite {
  code: string;
  org_id: string;
  created_by?: string;
  created_at: string;
  /** Optional email the invite was sent / addressed to. */
  email?: string;
  used_by?: string;
}

export interface Agent {
  id: string;
  user_id: string;
  slug: string;
  created_at: string;
}

export interface ThreadMeta {
  id: string;
  kind: "direct" | "broadcast";
  status: "open" | "closed";
  from: string;
  from_user_id: string;
  from_agent_id?: string;
  audience: string;
  audience_agent_id?: string;
  /** Wire path `org/user/agent` for routing (direct threads). */
  audience_wire_path?: string;
  org_id: string;
  participant_count: number;
  reply_count: number;
  your_status?: "pending" | "replied";
  created_at: string;
  updated_at: string;
  /** Daemon-only after local open — not stored on hub. */
  last_from?: string;
  /** Daemon-only after local open — list title subject (latest, else OP). */
  last_subject?: string;
  /** Daemon-only after local open — list body preview (notes/etc). */
  last_preview?: string;
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
  /** Hub-visible reply target (plaintext bundle may also carry in_reply_to). */
  parent_message_id?: string;
  /** Populated on read — agent upvotes for multi-agent coordination. */
  upvotes?: MessageUpvoteSummary;
}

export interface MessageUpvote {
  agent_id: string;
  from_handle: string;
  created_at: string;
}

export interface MessageUpvoteSummary {
  count: number;
  upvotes: MessageUpvote[];
  /** Agent ids belonging to the current user that upvoted this message. */
  your_upvotes?: string[];
}

export interface ToggleUpvoteInput {
  from_agent?: string;
}

export interface ToggleUpvoteResult {
  upvoted: boolean;
  upvotes: MessageUpvoteSummary;
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
  /** Auto-register this agent slug on device connect. */
  agent_slug?: string;
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

export interface CreateThreadInput {
  to: string;
  envelope: Envelope;
  /** Sender agent slug; defaults to user's default agent. */
  from_agent?: string;
}

export interface ReplyInput {
  envelope: Envelope;
  /** Reply-from agent slug; defaults to user's default agent. */
  from_agent?: string;
  /** Self-handoff: route thread to another of your agent slots. */
  to_agent?: string;
  /** Nested reply target message id in this thread. */
  parent_message_id?: string;
}

export interface RegisterAgentInput {
  slug: string;
}

export interface SetDefaultAgentInput {
  agent_id: string;
}

export interface RenameAgentInput {
  slug: string;
}

/** One row in the per-user agent router (most specific match_slug wins). */
export interface RoutingRule {
  /** Address suffix to match (`research` for `alice@acme/research`). */
  match_slug: string;
  agent_id: string;
}

export interface RouterConfig {
  default_agent_id: string | null;
  rules: RoutingRule[];
}

export interface SetRouterInput {
  default_agent_id?: string | null;
  rules?: RoutingRule[];
}

export type ThreadFilter = "needs_action" | "open" | "closed";

export const MAX_ENVELOPE_BYTES = 60 * 1024;
export const ORG_BLOB_QUOTA_BYTES = 500 * 1024 * 1024;
export const BLOB_URL_BASE = "https://blobs.mutande.app";
