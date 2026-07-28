import { redirect } from "next/navigation";
import { auth0 } from "@/lib/auth0";
import { formatHubError, getMe } from "@/lib/hub";
import type { MeResponse } from "@/lib/types";

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

export async function requireOnboarded(): Promise<MeResponse> {
  await requireSession();
  const { me, error } = await loadMeOrNull();
  if (error || !me) {
    redirect(
      `/signup?hub_error=${encodeURIComponent(error ?? "Hub unavailable")}`,
    );
  }
  if (!me.onboarded) {
    redirect("/signup");
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
