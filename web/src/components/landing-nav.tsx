import { TrackLink } from "@/components/track-link";
import { AnalyticsEvent } from "@/lib/analytics-events";
import { auth0 } from "@/lib/auth0";
import { loadMeOrNull, sessionShowsOps } from "@/lib/session";

const navLinkClass =
  "rounded-md px-3 py-2 text-sm text-stone-700 transition hover:bg-stone-200/40";

export async function LandingNav() {
  const session = await auth0.getSession();

  if (!session?.user) {
    return (
      <nav className="flex items-center gap-1 sm:gap-2">
        <a href="/docs" className={navLinkClass}>
          Docs
        </a>
        <TrackLink
          href="/download"
          event={AnalyticsEvent.DownloadNavClick}
          props={{ surface: "landing_nav" }}
          className={navLinkClass}
        >
          Try Alpha
        </TrackLink>
        <TrackLink
          href="/login"
          event={AnalyticsEvent.SignInClick}
          props={{ surface: "landing_nav" }}
          className={navLinkClass}
        >
          Sign in
        </TrackLink>
      </nav>
    );
  }

  const { me } = await loadMeOrNull();
  const onboarded = Boolean(me?.onboarded);
  const showOps = await sessionShowsOps(me);
  const accountHref = onboarded ? "/dashboard" : "/signup";
  const accountLabel = onboarded
    ? (me?.user?.handle ?? "Dashboard")
    : "Continue setup";

  return (
    <nav className="flex items-center gap-1 sm:gap-2">
      <a href="/docs" className={navLinkClass}>
        Docs
      </a>
      <TrackLink
        href="/download"
        event={AnalyticsEvent.DownloadNavClick}
        props={{ surface: "landing_nav" }}
        className={navLinkClass}
      >
        Try Alpha
      </TrackLink>
      {showOps ? (
        <a href="/admin/ops" className={navLinkClass}>
          Ops
        </a>
      ) : null}
      <a
        href={accountHref}
        className={`${navLinkClass} max-w-[12rem] truncate font-medium text-stone-900`}
        title={accountLabel}
      >
        {accountLabel}
      </a>
      <a href="/auth/logout" className={navLinkClass}>
        Sign out
      </a>
    </nav>
  );
}
