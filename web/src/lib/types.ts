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
}

export function isOrgAdmin(user?: HubUser | null): boolean {
  if (!user) return false;
  if (user.roles?.includes("org_admin")) return true;
  return user.role === "org_admin";
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
