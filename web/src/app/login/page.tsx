import { redirect } from "next/navigation";
import { BrandMark } from "@/components/ui";
import { TrackButtonLink } from "@/components/track-button-link";
import { AnalyticsEvent } from "@/lib/analytics-events";
import { auth0 } from "@/lib/auth0";

export const dynamic = "force-dynamic";
export const metadata = { title: "Sign in" };

export default async function LoginPage({
  searchParams,
}: {
  searchParams: Promise<{ returnTo?: string }>;
}) {
  const session = await auth0.getSession();
  const { returnTo } = await searchParams;
  if (session) {
    redirect(returnTo || "/dashboard");
  }

  const loginHref = `/auth/login?returnTo=${encodeURIComponent(returnTo || "/signup")}`;
  const signupHref = `/auth/login?screen_hint=signup&returnTo=${encodeURIComponent(returnTo || "/signup")}`;

  return (
    <div className="bg-relay grain relative flex min-h-full flex-1 flex-col overflow-hidden">
      <div
        aria-hidden
        className="pointer-events-none absolute inset-0 bg-[radial-gradient(ellipse_60%_45%_at_50%_0%,color-mix(in_oklch,var(--accent)_9%,transparent),transparent_65%)]"
      />

      <header className="relative z-10 flex items-center justify-between px-6 py-5 sm:px-8">
        <BrandMark />
        <nav className="flex items-center gap-1 sm:gap-2">
          <a
            href="/docs"
            className="rounded-md px-3 py-2 text-sm text-stone-700 transition hover:bg-stone-200/40 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-accent/35"
          >
            Docs
          </a>
          <a
            href="/download"
            className="rounded-md px-3 py-2 text-sm text-stone-700 transition hover:bg-stone-200/40 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-accent/35"
          >
            Try Alpha
          </a>
        </nav>
      </header>

      <main className="relative z-10 flex flex-1 flex-col justify-center px-6 pb-16 pt-4 sm:px-8">
        <div className="mx-auto w-full max-w-[22rem]">
          <header className="fade-up mb-8">
            <h1 className="font-display text-[2rem] font-semibold tracking-[-0.03em] text-stone-900 sm:text-[2.25rem]">
              Sign in
            </h1>
            <p className="mt-2.5 text-[15px] leading-relaxed text-muted">
              Continue to your team. Next you’ll create an org or redeem an
              invite — agent mail stays sealed on your devices.
            </p>
          </header>

          <div className="fade-up-delay flex flex-col gap-2.5">
            <TrackButtonLink
              href={loginHref}
              event={AnalyticsEvent.SignInClick}
              props={{ surface: "login" }}
              className="w-full"
            >
              Sign in
            </TrackButtonLink>
            <TrackButtonLink
              href={signupHref}
              event={AnalyticsEvent.CreateAccountClick}
              props={{ surface: "login" }}
              variant="secondary"
              className="w-full"
            >
              Create account
            </TrackButtonLink>
          </div>

          <p className="fade-up-late mt-8 text-sm leading-relaxed text-muted">
            Joining a team?{" "}
            <a
              href="/join"
              className="font-medium text-stone-800 underline decoration-stone-300 underline-offset-[3px] transition hover:decoration-stone-600 focus-visible:rounded-sm focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-accent/35"
            >
              Enter invite code
            </a>
          </p>
        </div>
      </main>
    </div>
  );
}
