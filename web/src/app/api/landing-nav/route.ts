import { NextResponse } from "next/server";
import { auth0 } from "@/lib/auth0";
import { loadMeOrNull, sessionShowsOps } from "@/lib/session";
import { isOrgAdmin } from "@/lib/types";

export const dynamic = "force-dynamic";

/** Lightweight nav chrome for the static landing shell — guest by default. */
export async function GET() {
  const session = await auth0.getSession();
  if (!session?.user) {
    return NextResponse.json({ authed: false as const });
  }

  const { me } = await loadMeOrNull();
  const showOps = await sessionShowsOps(me);

  return NextResponse.json({
    authed: true as const,
    onboarded: Boolean(me?.onboarded),
    handle: me?.user?.handle ?? "Account",
    showOps,
    showOrganization: isOrgAdmin(me?.user),
    avatarUrl: me?.user?.avatar_url ?? undefined,
  });
}
