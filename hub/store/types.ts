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
  display_name?: string;
  /** Small avatar — base64 image data URL (client-resized) or https URL. */
  avatar_url?: string;
  /**
   * Set after the one-shot Auth0 name/photo seed. Later clears/edits stay on
   * mutande — empty display_name/avatar_url are not re-filled from Auth0.
   */
  auth0_profile_seeded_at?: string;
}

/** Web profile management — omit a field to leave it unchanged; empty/null clears. */
export interface UpdateProfileInput {
  display_name?: string | null;
  avatar_url?: string | null;
  /**
   * Local part or full `local@org`. Org must match the user's current org.
   * Empty/null is rejected (handle cannot be cleared).
   */
  handle?: string | null;
}

/**
 * Fill empty profile fields from Auth0 (ID-token session or access-token claims).
 * Never overwrites mutande edits; name/photo seed runs at most once per user.
 */
export interface SeedProfileInput {
  email?: string;
  display_name?: string;
  avatar_url?: string;
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

/** Hub-assigned agent transport (never accepted from client capability bundle). */
export type AgentTransport = "sidecar" | "mcp";

/** Hub-assigned visibility (ops/registry; never from client wire). */
export type AgentVisibility = "private" | "public";

/** Hub-assigned trust tier (ops/registry; never from client wire). */
export type AgentTrustTier = "org" | "external" | "enterprise";

/**
 * Client-declared capability bundle on connect (§5.3).
 * Security fields (trust_tier / visibility / billing / transport) are hub-assigned only.
 */
export interface AgentCapabilities {
  models?: string[];
  default_model?: string;
  modalities?: string[];
  message_types?: string[];
}

/** Enterprise billing config — L4 only; always null for L1 private slots. */
export interface AgentBilling {
  methods: string[];
  price_usd: string;
  currency: string;
}

/**
 * Agent slot record. Same display slug may have two rows (sidecar + mcp).
 * Routing/audit use `id` + `transport`, not slug alone.
 */
export interface Agent {
  id: string;
  user_id: string;
  slug: string;
  created_at: string;
  /** Hub-assigned from authenticated connection type. Legacy rows omit → treat as sidecar. */
  transport: AgentTransport;
  /** Hub-assigned; private for org slots. Public reserved for L4 registry. */
  visibility: AgentVisibility;
  /** Hub-assigned; org for same-org slots. */
  trust_tier: AgentTrustTier;
  /** Hub/registry; null until L4 enterprise listings. */
  billing: AgentBilling | null;
  /** Hub-assigned for mcp transport; null for sidecar. Hosted MCP is L0. */
  mcp_endpoint: string | null;
  /** Last client-declared capability bundle (cached on connect). */
  capabilities: AgentCapabilities | null;
  /** ISO time of last capability refresh; used for 15m "active now" freshness only. */
  capabilities_updated_at: string | null;
}

/** 15-minute capability freshness TTL — never blocks routing (§5.1 / §13). */
export const CAPABILITY_STALE_TTL_MS = 15 * 60 * 1000;

/** Hosted MCP endpoint (L0); assigned on mcp transport rows even before L0 ships. */
export const MCP_ENDPOINT_DEFAULT = "https://mcp.mutande.online";

/** Per-user preferred transport for bare-slug resolution (Settings). */
export interface AgentTransportPrefs {
  /** slug → preferred transport; missing slug defaults to sidecar. */
  defaults: Record<string, AgentTransport>;
}

/** Thread-level encryption mode — fixed at creation; L5 one-way downgrade only (§4.2). */
export type ThreadEncryptionMode = "e2e" | "app_envelope";

/** Records where E2E ended after unanimous approve (§6.5 / L5). */
export interface ThreadDowngradePoint {
  message_id: string;
  /** Approving agent_ids (sidecar participants). */
  approvers: string[];
}

export type ThreadDowngradeProposalStatus = "pending" | "approved" | "denied";

/**
 * Pending/resolved proposal to add a web (mcp) agent to an E2E thread (§6.5).
 * Unanimous sidecar-participant approval required; one-way ratchet.
 */
export interface ThreadDowngradeProposal {
  id: string;
  thread_id: string;
  /** Web (mcp) agent to add after approve. */
  proposed_agent_id: string;
  proposed_slug: string;
  proposer_user_id: string;
  proposer_agent_id?: string;
  status: ThreadDowngradeProposalStatus;
  /** Sidecar agent_ids that must approve. */
  required_approvers: string[];
  /** Sidecar agent_ids that have approved so far. */
  approvals: string[];
  /** Sidecar agent_ids (or user marker) that denied — any deny rejects. */
  denials: string[];
  created_at: string;
  resolved_at?: string;
  /** Set when status becomes approved — system divider message id. */
  divider_message_id?: string;
}

export interface ProposeThreadDowngradeInput {
  /** Display slug of the web agent to add (mcp slot). */
  agent_slug: string;
  /** Optional proposing agent slug (attribution). */
  from_agent?: string;
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
  /**
   * Thread encryption mode (§4.2). Legacy rows omit → treat as `e2e`.
   * Fixed at creation; never silent-downgrade.
   */
  encryption_mode: ThreadEncryptionMode;
  /** Set after L5 unanimous downgrade; pre-point history stays sealed. */
  downgrade_point?: ThreadDowngradePoint;
  /**
   * When set, thread is billed enterprise mail (§7.2 / §9).
   * Enterprise agents may reply only within these threads (no new outbound).
   */
  enterprise_listing_id?: string;
  /** Bilateral external contact link when this is cross-org mail (§6.2). */
  external_link_id?: string;
  /** Explicit participants — required for cross-org inbox ACL (different org_ids). */
  participant_user_ids?: string[];
  /** Daemon-only after local open — not stored on hub. */
  last_from?: string;
  /** Daemon-only after local open — list title subject (latest, else OP). */
  last_subject?: string;
  /** Daemon-only after local open — list body preview (notes/etc). */
  last_preview?: string;
  /**
   * Post-merge awaiting holders declared by sender core.
   * `your_status` is pending iff the viewer’s user_id appears here.
   */
  awaiting?: HubAwaitingEntry[];
}

/** Hub mirror of E2E `next_turn` (user-scoped; actor distinguishes needs-you vs agent mail). */
export interface HubAwaitingEntry {
  user_id: string;
  actor: "agent" | "human";
}

/**
 * Hub-readable application-layer payload (directory.prd §4.2.1 / §4.6).
 * Never coexists with E2E `envelope` on the same message.
 * Shape mirrors a subset of the plaintext bundle for web/MCP delivery.
 */
export interface AppEnvelopePayload {
  version: number;
  subject?: string;
  context?: string;
  notes?: string;
  ping_kind?: "health" | "thread";
  intent?: "question" | "answer" | "handoff" | "status" | "fyi";
  questions?: unknown[];
  answers?: unknown[];
  resources?: unknown[];
  resource_requests?: unknown[];
  in_reply_to?: string;
  next_turn?: unknown[];
  task?: unknown;
  hints?: unknown[];
  [key: string]: unknown;
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
  from_agent_id?: string;
  /**
   * E2E blind envelope. Present only when thread `encryption_mode` is `e2e`
   * (or pre-downgrade history). Never set alongside `app_envelope`.
   */
  envelope?: Envelope;
  /**
   * Hub-readable app_envelope content. Present only for `app_envelope` mode
   * messages after authorized fetch/decrypt. Never set alongside `envelope`.
   */
  app_envelope?: AppEnvelopePayload;
  /**
   * True when body lives in the app_envelope store (not the E2E message blob).
   * Hub-internal; clients use `encryption_mode` + `app_envelope` / `envelope`.
   */
  content_store?: "e2e" | "app_envelope";
  created_at: string;
  sender_only?: boolean;
  /** Hub-visible reply target (plaintext bundle may also carry in_reply_to). */
  parent_message_id?: string;
  /** Populated on read — agent upvotes for multi-agent coordination. */
  upvotes?: MessageUpvoteSummary;
  /** Populated on read — processed receipts (informational; never clear turns). */
  receipts?: MessageReceiptSummary;
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
  from_agent_id?: string;
}

export interface ToggleUpvoteResult {
  upvoted: boolean;
  upvotes: MessageUpvoteSummary;
}

export interface MessageReceipt {
  agent_id: string;
  from_handle: string;
  created_at: string;
}

export interface MessageReceiptSummary {
  count: number;
  receipts: MessageReceipt[];
  your_receipts?: string[];
}

export interface PostReceiptInput {
  from_agent?: string;
  from_agent_id?: string;
}

export interface PostReceiptResult {
  receipts: MessageReceiptSummary;
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
  /** `org` (default) or `external` for cross-org links. */
  kind?: "org" | "external" | "broadcast";
  /** Profile photo when the contact has one. */
  avatar_url?: string;
  /** Profile display name when the contact has one. */
  display_name?: string;
  /** Hub user id (org members) — used for awaiting turns mirror. */
  user_id?: string;
  /** External link id when kind === external. */
  external_link_id?: string;
  linked_at?: string;
  /** Connection-ping thread created on approve. */
  thread_id?: string;
}

/** Alice's rotating pairing PIN (Settings → Pair external contact). */
export interface PairingPin {
  user_id: string;
  handle: string;
  pin: string;
  created_at: string;
  expires_at: string;
}

export interface PairingPinResponse {
  pin: string;
  handle: string;
  expires_at: string;
  /** `mutande://pair?handle=…&pin=…` for QR. */
  qr_uri: string;
}

export type PairRequestStatus = "pending" | "approved" | "denied";

export interface PairRequest {
  id: string;
  requester_user_id: string;
  requester_handle: string;
  target_user_id: string;
  target_handle: string;
  intro?: string;
  status: PairRequestStatus;
  created_at: string;
  resolved_at?: string;
}

export interface SubmitPairRequestInput {
  handle: string;
  pin: string;
  intro?: string;
}

export interface ExternalContactLink {
  id: string;
  user_a_id: string;
  user_a_handle: string;
  user_b_id: string;
  user_b_handle: string;
  created_at: string;
  thread_id: string;
}

/** Ops signal: ≥5 denies from different users in 7d on same target (§6.3.1). */
export interface PairingOpsFlag {
  id: string;
  type: "pairing_harassment";
  target_handle: string;
  target_user_id: string;
  deny_count: number;
  distinct_requesters: string[];
  created_at: string;
  window_days: 7;
}

/** Locked §13 pairing / flood constants. */
export const PAIR_PIN_LENGTH = 6;
export const PAIR_PIN_TTL_MS = 7 * 24 * 60 * 60 * 1000;
export const PAIR_WRONG_PIN_LIMIT = 5;
export const PAIR_WRONG_PIN_LOCK_MS = 60 * 60 * 1000;
export const PAIR_SUBMISSIONS_PER_REQUESTER_DAY = 10;
export const PAIR_SUBMISSIONS_PER_TARGET_DAY = 20;
export const PAIR_DENY_OPS_THRESHOLD = 5;
export const PAIR_DENY_OPS_WINDOW_MS = 7 * 24 * 60 * 60 * 1000;
export const EXTERNAL_LINK_MSGS_PER_DAY = 200;

export interface Auth0Claims {
  sub: string;
  email?: string;
  /** Auth0 `profile` scope — often on ID token; may be on access token via Action. */
  name?: string;
  picture?: string;
  /** Auth0 RBAC role names/ids from access-token custom claims. */
  roles?: string[];
}

export interface AuthContext {
  userId: string;
  orgId: string;
  handle: string;
  role: UserRole;
  auth0Sub: string;
  auth0Roles: string[];
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

/** Org admin typo fix — rewrites live org slug + member handles. */
export interface UpdateOrgInput {
  slug: string;
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
  /** Product-owner ops (Auth0 SuperAdmin), not org_admin. */
  is_ops_admin?: boolean;
  auth0_roles?: string[];
}

export interface CreateThreadInput {
  to: string;
  /** E2E wire unit — required when resolved mode is `e2e`. Mutually exclusive with `app_envelope`. */
  envelope?: Envelope;
  /** Hub-readable payload — required when resolved mode is `app_envelope`. Mutually exclusive with `envelope`. */
  app_envelope?: AppEnvelopePayload;
  /** Sender agent slug; defaults to user's default agent. */
  from_agent?: string;
  /**
   * Bound sender agent_id (hosted MCP dual-slot). Wins over `from_agent` slug
   * so web sessions are not remapped to a preferred sidecar row.
   */
  from_agent_id?: string;
  /** Post-merge awaiting set computed by sender core (E2E answers stay sealed). */
  turns?: HubAwaitingEntry[];
}

export interface ReplyInput {
  /** E2E wire unit — required for `e2e` threads. Mutually exclusive with `app_envelope`. */
  envelope?: Envelope;
  /** Hub-readable payload — required for `app_envelope` threads. Mutually exclusive with `envelope`. */
  app_envelope?: AppEnvelopePayload;
  /** Reply-from agent slug; defaults to user's default agent. */
  from_agent?: string;
  /** Bound sender agent_id — same semantics as create (`from_agent_id`). */
  from_agent_id?: string;
  /** Self-handoff: route thread to another of your agent slots. */
  to_agent?: string;
  /** Nested reply target message id in this thread. */
  parent_message_id?: string;
  /** Post-merge awaiting set computed by sender core. */
  turns?: HubAwaitingEntry[];
}

/** Fetch options for web/MCP pull of app_envelope content. */
export interface FetchAppMessagesInput {
  /** Optional agent slot that must belong to the caller (attribution). */
  agent_id?: string;
}

export interface RegisterAgentInput {
  slug: string;
}

/**
 * Capability handshake body (client-declared fields only).
 * Hub ignores/logs trust_tier, visibility, billing, transport, agent_id if present.
 */
export interface ConnectAgentInput {
  slug: string;
  models?: string[];
  default_model?: string;
  modalities?: string[];
  message_types?: string[];
  /** Ignored — hub-assigned. */
  trust_tier?: unknown;
  /** Ignored — hub-assigned. */
  visibility?: unknown;
  /** Ignored — hub-assigned. */
  billing?: unknown;
  /** Ignored — hub-assigned from connection type. */
  transport?: unknown;
  /** Ignored — hub-assigned. */
  agent_id?: unknown;
  [key: string]: unknown;
}

export interface SetDefaultAgentInput {
  agent_id: string;
}

export interface RenameAgentInput {
  slug: string;
}

/** Settings: preferred transport for a display slug. */
export interface SetTransportDefaultInput {
  slug: string;
  transport: AgentTransport;
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
/** Same KV-friendly ceiling as E2E inline envelopes (§4.2.1 size awareness). */
export const MAX_APP_ENVELOPE_BYTES = 60 * 1024;
/** Hard upper bound — 30 days (§4.2.1 / §13). Applied via Deno KV expireIn. */
export const APP_ENVELOPE_RETENTION_MS = 30 * 24 * 60 * 60 * 1000;
export const APP_ENVELOPE_RETENTION_DAYS = 30;
export const ORG_BLOB_QUOTA_BYTES = 500 * 1024 * 1024;
export const BLOB_URL_BASE = "https://blobs.mutande.app";

// ── L4 Enterprise registry + billing ──────────────────────────────────────

/** Listing lifecycle (§8.3). Draft = submitter-only; published = discoverable. */
export type RegistryListingStatus = "draft" | "published" | "suspended";

/** Ops review SLA target (§13): draft → publish. */
export const REGISTRY_REVIEW_SLA_BUSINESS_DAYS = 5;

/** Loop guard: billed messages per thread per UTC day (§9.3 / §13). */
export const ENTERPRISE_BILLED_MSGS_PER_DAY_THREAD = 50;

export interface RegistryListingBilling {
  methods: ["per_message"];
  /** Decimal USD string set by listing owner (e.g. "0.05"). */
  price_usd: string;
  currency: "USD";
}

/**
 * Public enterprise registry record (§8.2).
 * `trust_tier` is always hub-assigned `"enterprise"` — never from the wire.
 */
export interface RegistryListing {
  id: string;
  /** Agent address, e.g. `assistant@openai`. */
  address: string;
  /** Stable routing id for the public enterprise agent slot. */
  agent_id: string;
  /** Submitter's customer org (owner of the draft). */
  org_id: string;
  submitter_user_id: string;
  status: RegistryListingStatus;
  trust_tier: "enterprise";
  visibility: "public" | "private";
  capabilities: AgentCapabilities;
  billing: RegistryListingBilling;
  /** Domain/brand verification stub — ops marks verified (§8.3). */
  domain_verified: boolean;
  /**
   * Org slug reserved at verification (e.g. `openai`).
   * Collides with customer `createOrg` until reserved by the same legal entity.
   */
  reserved_org_slug: string | null;
  created_at: string;
  updated_at: string;
  published_at?: string;
  suspended_at?: string;
}

export interface CreateRegistryDraftInput {
  address: string;
  capabilities?: AgentCapabilities;
  /** Owner-set per_message price in USD (decimal string). */
  price_usd: string;
}

export interface UpdateRegistryDraftInput {
  capabilities?: AgentCapabilities;
  price_usd?: string;
}

export interface ReservedOrgSlug {
  slug: string;
  listing_id: string;
  reserved_at: string;
  org_id: string;
}

/** Hub-managed credit ledger per sender org (§9.2). Amounts in USD cents. */
export interface BillingLedger {
  org_id: string;
  balance_cents: number;
  updated_at: string;
}

export type BillingLedgerEntryKind = "credit" | "debit";

export interface BillingLedgerEntry {
  id: string;
  org_id: string;
  kind: BillingLedgerEntryKind;
  amount_cents: number;
  balance_after_cents: number;
  listing_id?: string;
  thread_id?: string;
  /** Ops note on top-up; never PII from mail. */
  note?: string;
  created_at: string;
  /** Ops auth0_sub for credits; sender user_id for debits. */
  actor_id?: string;
}

export interface TopUpCreditsInput {
  org_id: string;
  /** Positive USD decimal string (e.g. "25.00"). */
  amount_usd: string;
  note?: string;
}

/**
 * Debit-on-store request (§9.3). Call immediately before committing an
 * `app_envelope` to a public enterprise agent. L2 should invoke this inside
 * the store path; until then it is the clear billing gate interface.
 */
export interface EnterpriseDebitOnStoreInput {
  /** Published listing id, or resolve via `address`. */
  listing_id?: string;
  address?: string;
  thread_id: string;
  payload_bytes: number;
  /** Optional; hub estimates from payload_bytes when omitted. */
  estimated_tokens?: number;
  blob_count?: number;
  /** Caller-measured end-to-end latency for metrics. */
  latency_ms?: number;
}

export interface EnterpriseDebitOnStoreResult {
  listing: RegistryListing;
  entry: BillingLedgerEntry;
  metric: EnterpriseDeliveryMetric;
  /** Remaining balance after debit (cents). */
  balance_cents: number;
}

/** No-PII delivery metric for ops / enterprise dashboards (§9.4). */
export interface EnterpriseDeliveryMetric {
  id: string;
  created_at: string;
  listing_id: string;
  sender_org_id: string;
  payload_bytes: number;
  estimated_tokens: number;
  blob_count: number;
  latency_ms: number;
  price_cents: number;
}

/** Warn-banner payload: clients show enterprise warning when trust_tier is enterprise. */
export interface EnterpriseWarnBanner {
  trust_tier: "enterprise";
  message: string;
}

export const ENTERPRISE_WARN_BANNER: EnterpriseWarnBanner = {
  trust_tier: "enterprise",
  message: "Enterprise agent — not E2E; provider may retain data",
};
