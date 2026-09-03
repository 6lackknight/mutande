import type { NextRequest } from "next/server";
import { NextResponse } from "next/server";
import { auth0 } from "@/lib/auth0";
import { isPitchPath, needsAuth } from "@/lib/proxy-rules";

export async function proxy(request: NextRequest) {
  const authRes = await auth0.middleware(request);
  const { pathname } = request.nextUrl;

  // Let Auth0 mount /auth/* routes unchanged.
  if (pathname.startsWith("/auth")) {
    return authRes;
  }

  // The Slidev deck is public static output; skip auth on the decoded pathname.
  if (isPitchPath(pathname)) {
    return authRes;
  }

  if (needsAuth(pathname)) {
    const session = await auth0.getSession(request);
    if (!session) {
      const login = new URL("/auth/login", request.url);
      login.searchParams.set("returnTo", `${pathname}${request.nextUrl.search}`);
      return NextResponse.redirect(login);
    }
  }

  return authRes;
}

export const config = {
  matcher: [
    "/((?!_next/static|_next/image|favicon.ico|sitemap.xml|robots.txt).*)",
  ],
};
