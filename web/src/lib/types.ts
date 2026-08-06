export type UserRole = "org_admin" | "member";

export interface HubUser {
  id: string;
  auth0_sub: string;
  handle?: string;
  org_id?: string;
  /** Prefer roles[]; hub may still emit singular role during migration. */
  roles?: UserRole[];
  role?: UserRole;
  created_at: string;
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
  return Boolean(me?.is_ops_admin);
}

export interface CreateOrgInput {
  slug: string;
  name?: string;
  handle?: string;
}

export interface JoinOrgInput {
  invite_code: string;
  handle: string;
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
