import { NextResponse } from "next/server";
import { auth0 } from "@/lib/auth0";

export const dynamic = "force-dynamic";

/** Auth0 `sub` for client-side Mixpanel identify — no email/handle. */
export async function GET() {
  const session = await auth0.getSession();
  const sub = session?.user?.sub;
  if (typeof sub !== "string" || !sub.trim()) {
    return NextResponse.json({ auth0_sub: null });
  }
  return NextResponse.json({ auth0_sub: sub.trim() });
}
