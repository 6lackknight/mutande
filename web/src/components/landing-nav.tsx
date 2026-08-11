"use client";

import { useEffect, useState } from "react";
import { AccountMenu } from "@/components/account-menu";
import { TrackLink } from "@/components/track-link";
import { AnalyticsEvent } from "@/lib/analytics-events";

const navLinkClass =
  "rounded-md px-3 py-2 text-sm text-stone-700 transition hover:bg-stone-200/40";

type LandingNavState =
  | { authed: false }
  | {
      authed: true;
      onboarded: boolean;
      handle: string;
      showOps: boolean;
      showOrganization: boolean;
      avatarUrl?: string;
    };

function GuestNav() {
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

/**
 * Guest chrome in the static HTML; upgrades after paint if a session exists.
 * Keeps the landing route cacheable (no Auth0 cookies on the document request).
 */
export function LandingNav() {
  const [state, setState] = useState<LandingNavState>({ authed: false });

  useEffect(() => {
    let cancelled = false;
    void fetch("/api/landing-nav", { credentials: "same-origin" })
      .then((res) => (res.ok ? res.json() : { authed: false }))
      .then((data: LandingNavState) => {
        if (!cancelled && data?.authed) setState(data);
      })
      .catch(() => {
        // Stay on guest chrome.
      });
    return () => {
      cancelled = true;
    };
  }, []);

  if (!state.authed) return <GuestNav />;

  return (
    <nav className="flex items-center gap-1 sm:gap-2">
      <a href="/docs" className={navLinkClass}>
        Docs
      </a>
      {state.showOps ? (
        <a href="/admin/ops" className={navLinkClass}>
          Ops
        </a>
      ) : null}
      {state.onboarded ? (
        <AccountMenu
          label={state.handle}
          showOrganization={state.showOrganization}
          avatarUrl={state.avatarUrl}
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
