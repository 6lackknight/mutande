import { isPlatformOpsAdmin } from "@/lib/platform-admin";

export type UserRole = "org_admin" | "member";

export interface HubUser {
  id: string;
  auth0_sub: string;
  email?: string;
  handle?: string;
  org_id?: string;
  /** Prefer roles[]; hub may still emit singular role during migration. */
  roles?: UserRole[];
  role?: UserRole;
  created_at: string;
  display_name?: string;
  /** Small avatar — base64 image data URL (client-resized) or https URL. */
  avatar_url?: string;
  /** Set after one-shot Auth0 name/photo seed. */
  auth0_profile_seeded_at?: string;
}

/** Omit a field to leave it unchanged; empty string clears. */
export interface UpdateProfileInput {
  display_name?: string;
  avatar_url?: string;
  /** Local part or full `local@org` (org must match). */
  handle?: string;
}

/** Empty-only Auth0 seed — never overwrites mutande profile edits. */
export interface SeedProfileInput {
  email?: string;
  display_name?: string;
  avatar_url?: string;
}

export interface HubOrg {
  id: string;
  slug: string;
  name: string;
  created_at: string;
}

export interface MeResponse {
  auth0_sub: string;
  email?: string;
  onboarded: boolean;
  /** Hub may emit needs_onboarding; normalized away in hub client. */
  needs_onboarding?: boolean;
  user?: HubUser;
  org?: HubOrg;
  /** Product-owner ops (Auth0 SuperAdmin), not org_admin. */
  is_ops_admin?: boolean;
  auth0_roles?: string[];
}

export function isOrgAdmin(user?: HubUser | null): boolean {
  if (!user) return false;
  if (user.roles?.includes("org_admin")) return true;
  return user.role === "org_admin";
}

export function isOpsAdmin(me?: MeResponse | null): boolean {
  if (!me) return false;
  if (me.is_ops_admin) return true;
  // Hub may omit the boolean on older deploys; still honor role claim array.
  return isPlatformOpsAdmin(me.auth0_roles);
}

export interface CreateOrgInput {
  slug: string;
  name?: string;
  handle?: string;
}

export interface UpdateOrgInput {
  slug: string;
}

export interface JoinOrgInput {
  invite_code: string;
  handle: string;
}

export type ContactKind = "org" | "external" | "broadcast";

export interface Contact {
  handle: string;
  pubkey: string | null;
  devices: Array<{ pubkey: string; platform: string }>;
  kind?: ContactKind;
  avatar_url?: string;
  external_link_id?: string;
  linked_at?: string;
  thread_id?: string;
}

export interface ListContactsResponse {
  contacts: Contact[];
}

export interface PairingPinResponse {
  pin: string;
  handle: string;
  expires_at: string;
  /** `mutande://pair?handle=…&pin=…` for QR / deeplink. */
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

export interface ListPendingPairRequestsResponse {
  incoming: PairRequest[];
  outgoing: PairRequest[];
}

export interface Invite {
  code: string;
  org_id: string;
  created_at: string;
  email?: string;
}

export interface CreateInviteResponse {
  invite: Invite;
}

export interface ListInvitesResponse {
  invites: Invite[];
}

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

export interface WaitlistEntry {
  id: string;
  created_at: string;
  email: string;
  ai_hosts: string[];
  oses: string[];
  share_frequency: string;
  share_methods: string[];
  source: "web";
}

export interface ListFeedbackResponse {
  feedback: Feedback[];
}

export interface ListWaitlistResponse {
  waitlist: WaitlistEntry[];
}

/** L4 registry listing (hub-assigned trust_tier always enterprise). */
export interface RegistryListing {
  id: string;
  address: string;
  agent_id: string;
  org_id: string;
  submitter_user_id: string;
  status: "draft" | "published" | "suspended";
  trust_tier: "enterprise";
  visibility: "public" | "private";
  billing: {
    methods: ["per_message"];
    price_usd: string;
    currency: "USD";
  };
  domain_verified: boolean;
  reserved_org_slug: string | null;
  created_at: string;
  updated_at: string;
  published_at?: string;
  suspended_at?: string;
}

export interface BillingLedger {
  org_id: string;
  balance_cents: number;
  updated_at: string;
}

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

export class HubError extends Error {
  readonly status: number;
  readonly body: unknown;

  constructor(message: string, status: number, body?: unknown) {
    super(message);
    this.name = "HubError";
    this.status = status;
    this.body = body;
  }
}
