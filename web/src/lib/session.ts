import { redirect } from "next/navigation";
import { auth0 } from "@/lib/auth0";
import { formatHubError, getMe, seedProfile } from "@/lib/hub";
import {
  extractAuth0Roles,
  isPlatformOpsAdmin,
  rolesFromJwt,
  SESSION_AUTH0_ROLES_KEY,
  SESSION_OPS_ADMIN_KEY,
} from "@/lib/platform-admin";
import { isOpsAdmin, type MeResponse } from "@/lib/types";

export async function requireSession(returnTo = "/signup") {
  const session = await auth0.getSession();
  if (!session?.user) {
    redirect(`/auth/login?returnTo=${encodeURIComponent(returnTo)}`);
  }
  return session;
}

export async function loadMeOrNull(): Promise<{
  me: MeResponse | null;
  error: string | null;
}> {
  try {
    const me = await getMe();
    return { me, error: null };
  } catch (err) {
    return { me: null, error: formatHubError(err) };
  }
}

function opsFromSessionUser(user: Record<string, unknown>): boolean {
  if (user[SESSION_OPS_ADMIN_KEY] === true) return true;
  const saved = user[SESSION_AUTH0_ROLES_KEY];
  if (Array.isArray(saved) && isPlatformOpsAdmin(saved as string[])) return true;
  return isPlatformOpsAdmin(extractAuth0Roles(user));
}

/**
 * SuperAdmin for nav chrome: hub `/me`, access-token roles, ID token, or
 * persisted session.user roles (Auth0 v4 strips custom claims unless saved).
 */
export async function sessionShowsOps(me?: MeResponse | null): Promise<boolean> {
  if (isOpsAdmin(me)) return true;

  try {
    const session = await auth0.getSession();
    const user = session?.user;
    if (user && typeof user === "object" && opsFromSessionUser(user as Record<string, unknown>)) {
      return true;
    }
    if (session?.tokenSet?.accessToken) {
      if (isPlatformOpsAdmin(rolesFromJwt(session.tokenSet.accessToken))) return true;
    }
    if (session?.tokenSet?.idToken) {
      if (isPlatformOpsAdmin(rolesFromJwt(session.tokenSet.idToken))) return true;
    }
  } catch {
    // ignore
  }

  try {
    const { token } = await auth0.getAccessToken();
    if (isPlatformOpsAdmin(rolesFromJwt(token))) return true;
  } catch {
    // No token / refresh failed.
  }

  return false;
}

function auth0SessionProfile(user: Record<string, unknown>): {
  email?: string;
  display_name?: string;
  avatar_url?: string;
} {
  const email = typeof user.email === "string" ? user.email : undefined;
  const display_name = typeof user.name === "string" ? user.name : undefined;
  const avatar_url = typeof user.picture === "string" ? user.picture : undefined;
  return {
    ...(email ? { email } : {}),
    ...(display_name ? { display_name } : {}),
    ...(avatar_url ? { avatar_url } : {}),
  };
}

function needsAuth0ProfileSeed(me: MeResponse): boolean {
  if (!me.email && !me.user?.email) return true;
  if (me.user?.auth0_profile_seeded_at) return false;
  return !me.user?.display_name || !me.user?.avatar_url;
}

/** Push ID-token name/email/picture into empty hub profile fields (once). */
async function seedMeFromAuth0Session(
  me: MeResponse,
  sessionUser: Record<string, unknown>,
): Promise<MeResponse> {
  if (!needsAuth0ProfileSeed(me)) return me;
  const seed = auth0SessionProfile(sessionUser);
  if (!seed.email && !seed.display_name && !seed.avatar_url) return me;
  try {
    return await seedProfile(seed);
  } catch {
    return me;
  }
}

export async function requireOnboarded(): Promise<MeResponse> {
  const session = await requireSession();
  const { me, error } = await loadMeOrNull();
  if (error || !me) {
    redirect(
      `/signup?hub_error=${encodeURIComponent(error ?? "Hub unavailable")}`,
    );
  }
  if (!me.onboarded) {
    redirect("/signup");
  }
  const user = session.user as Record<string, unknown> | undefined;
  if (user && typeof user === "object") {
    return seedMeFromAuth0Session(me, user);
  }
  return me;
}

export function defaultHandleFromEmail(
  email: string | undefined,
  orgSlug: string,
): string {
  const local = (email ?? "user").split("@")[0]?.toLowerCase() || "user";
  const safe = local.replace(/[^a-z0-9._-]/g, "").slice(0, 32) || "user";
  return `${safe}@${orgSlug}`;
}

export function appBaseUrl(): string {
  const configured = process.env.APP_BASE_URL?.replace(/\/$/, "");
  if (configured) return configured;
  if (process.env.VERCEL_URL) return `https://${process.env.VERCEL_URL}`;
  return "http://localhost:3000";
}

export function joinUrlForCode(code: string): string {
  return `${appBaseUrl()}/join?invite=${encodeURIComponent(code)}`;
}
