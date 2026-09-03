// Pure proxy routing rules — no next/ or @/lib imports so this stays
// testable with plain `node --test`.

const protectedPrefixes = [
  "/signup",
  "/onboarding",
  "/dashboard",
  "/connectors",
  "/admin",
  "/join",
];

// The deck is public static output; keeping the check here (decoded pathname)
// instead of the matcher avoids coupling auth coverage to platform normalization.
export function isPitchPath(pathname: string): boolean {
  return pathname === "/pitch" || pathname.startsWith("/pitch/");
}

export function needsAuth(pathname: string): boolean {
  return protectedPrefixes.some(
    (p) => pathname === p || pathname.startsWith(`${p}/`),
  );
}
