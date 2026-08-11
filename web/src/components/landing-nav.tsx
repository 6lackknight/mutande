import { AccountMenu } from "@/components/account-menu";
import { TrackLink } from "@/components/track-link";
import { AnalyticsEvent } from "@/lib/analytics-events";
import { auth0 } from "@/lib/auth0";
import { loadMeOrNull, sessionShowsOps } from "@/lib/session";
import { isOrgAdmin } from "@/lib/types";

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

  return (
    <nav className="flex items-center gap-1 sm:gap-2">
      <a href="/docs" className={navLinkClass}>
        Docs
      </a>
      {showOps ? (
        <a href="/admin/ops" className={navLinkClass}>
          Ops
        </a>
      ) : null}
      {onboarded ? (
        <AccountMenu
          label={me?.user?.handle ?? "Account"}
          showOrganization={isOrgAdmin(me?.user)}
        />
      ) : (
        <>
          <a
            href="/signup"
            className={`${navLinkClass} font-medium text-stone-900`}
          >
            Continue setup
          </a>
          <a href="/auth/logout" className={navLinkClass}>
            Sign out
          </a>
        </>
      )}
    </nav>
  );
}
