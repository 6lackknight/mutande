"use client";

import { useLayoutEffect, useState } from "react";
import { AnimatePresence, motion, useReducedMotion } from "motion/react";
import { AccountMenu } from "@/components/account-menu";
import { TrackLink } from "@/components/track-link";
import { AnalyticsEvent } from "@/lib/analytics-events";

const navLinkClass =
  "rounded-md px-3 py-2 text-sm text-stone-700 transition hover:bg-stone-200/40";

const CACHE_KEY = "mutande.landing-nav.v1";

type AuthedNavState = {
  authed: true;
  onboarded: boolean;
  handle: string;
  showOps: boolean;
  showOrganization: boolean;
  avatarUrl?: string;
};

type LandingNavState = { authed: false } | AuthedNavState;

function readCached(): AuthedNavState | null {
  if (typeof window === "undefined") return null;
  try {
    const raw = localStorage.getItem(CACHE_KEY);
    if (!raw) return null;
    const data = JSON.parse(raw) as LandingNavState;
    if (
      data?.authed === true &&
      typeof data.handle === "string" &&
      typeof data.onboarded === "boolean"
    ) {
      return {
        authed: true,
        onboarded: data.onboarded,
        handle: data.handle,
        showOps: Boolean(data.showOps),
        showOrganization: Boolean(data.showOrganization),
        ...(typeof data.avatarUrl === "string"
          ? { avatarUrl: data.avatarUrl }
          : {}),
      };
    }
  } catch {
    // Ignore bad cache.
  }
  return null;
}

function writeCached(state: LandingNavState) {
  try {
    if (state.authed) localStorage.setItem(CACHE_KEY, JSON.stringify(state));
    else localStorage.removeItem(CACHE_KEY);
  } catch {
    // Ignore quota / private mode.
  }
}

function normalize(data: LandingNavState): LandingNavState {
  if (data?.authed !== true) return { authed: false };
  return {
    authed: true,
    onboarded: Boolean(data.onboarded),
    handle: typeof data.handle === "string" ? data.handle : "Account",
    showOps: Boolean(data.showOps),
    showOrganization: Boolean(data.showOrganization),
    ...(typeof data.avatarUrl === "string" ? { avatarUrl: data.avatarUrl } : {}),
  };
}

function sameNav(a: LandingNavState, b: LandingNavState): boolean {
  if (a.authed !== b.authed) return false;
  if (!a.authed || !b.authed) return true;
  return (
    a.onboarded === b.onboarded &&
    a.handle === b.handle &&
    a.showOps === b.showOps &&
    a.showOrganization === b.showOrganization &&
    a.avatarUrl === b.avatarUrl
  );
}

function useNavMotion() {
  const reduce = useReducedMotion();
  if (reduce) {
    return {
      initial: { opacity: 0 },
      animate: { opacity: 1 },
      exit: { opacity: 0 },
      transition: { duration: 0.01 },
    };
  }
  return {
    initial: { opacity: 0, x: 6 },
    animate: { opacity: 1, x: 0 },
    exit: { opacity: 0, x: -4 },
    transition: { duration: 0.22, ease: [0.25, 1, 0.5, 1] as const },
  };
}

/**
 * One persistent nav bar. Docs always stays. Logged-in / Ops items animate onto
 * the bar and remain until auth or role actually changes (localStorage cache
 * avoids guest↔account teardown on remount).
 */
export function LandingNav() {
  // null = not resolved yet (SSR + first hydrate show Docs only — no Sign in flash).
  const [state, setState] = useState<LandingNavState | null>(null);
  const motionProps = useNavMotion();

  useLayoutEffect(() => {
    setState(readCached() ?? { authed: false });

    let cancelled = false;
    void fetch("/api/landing-nav", { credentials: "same-origin" })
      .then((res) => (res.ok ? res.json() : { authed: false as const }))
      .then((raw: LandingNavState) => {
        if (cancelled) return;
        const next = normalize(raw);
        writeCached(next);
        setState((prev) =>
          prev && sameNav(prev, next) ? prev : next,
        );
      })
      .catch(() => {
        // Keep current chrome on blips.
      });

    return () => {
      cancelled = true;
    };
  }, []);

  const showOps = Boolean(state?.authed && state.showOps);

  return (
    <nav className="flex items-center gap-1 sm:gap-2">
      <a href="/docs" className={navLinkClass}>
        Docs
      </a>

      {state ? (
        <>
          <AnimatePresence initial={false}>
            {showOps ? (
              <motion.a
                key="ops"
                href="/admin/ops"
                className={navLinkClass}
                {...motionProps}
              >
                Ops
              </motion.a>
            ) : null}
          </AnimatePresence>

          <AnimatePresence mode="wait" initial={false}>
            {state.authed && state.onboarded ? (
              <motion.div key="account" className="flex" {...motionProps}>
                <AccountMenu
                  label={state.handle}
                  showOrganization={state.showOrganization}
                  avatarUrl={state.avatarUrl}
                />
              </motion.div>
            ) : state.authed ? (
              <motion.div
                key="setup"
                className="flex items-center gap-1 sm:gap-2"
                {...motionProps}
              >
                <a
                  href="/signup"
                  className={`${navLinkClass} font-medium text-stone-900`}
                >
                  Continue setup
                </a>
                <a href="/auth/logout" className={navLinkClass}>
                  Sign out
                </a>
              </motion.div>
            ) : (
              <motion.div key="signin" className="flex" {...motionProps}>
                <TrackLink
                  href="/login"
                  event={AnalyticsEvent.SignInClick}
                  props={{ surface: "landing_nav" }}
                  className={navLinkClass}
                >
                  Sign in
                </TrackLink>
              </motion.div>
            )}
          </AnimatePresence>
        </>
      ) : null}
    </nav>
  );
}
