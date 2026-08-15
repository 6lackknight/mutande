"use client";

import { useLayoutEffect, useState } from "react";
import { AnimatePresence, motion, useReducedMotion } from "motion/react";
import { AccountMenu } from "@/components/account-menu";
import { TrackLink } from "@/components/track-link";
import { BrandMark } from "@/components/ui";
import { AnalyticsEvent } from "@/lib/analytics-events";

const navLinkClass =
  "rounded-md px-2.5 py-2 text-sm text-stone-700 transition hover:bg-stone-200/40 sm:px-3";

const CACHE_KEY = "mutande.landing-nav.v1";

type AuthedNavState = {
  authed: true;
  onboarded: boolean;
  handle: string;
  showOps: boolean;
  showOrganization: boolean;
  avatarUrl?: string;
};

type SiteNavState = { authed: false } | AuthedNavState;

function readCached(): AuthedNavState | null {
  if (typeof window === "undefined") return null;
  try {
    const raw = localStorage.getItem(CACHE_KEY);
    if (!raw) return null;
    const data = JSON.parse(raw) as SiteNavState;
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

function writeCached(state: SiteNavState) {
  try {
    if (state.authed) localStorage.setItem(CACHE_KEY, JSON.stringify(state));
    else localStorage.removeItem(CACHE_KEY);
  } catch {
    // Ignore quota / private mode.
  }
}

function normalize(data: SiteNavState): SiteNavState {
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

function sameNav(a: SiteNavState, b: SiteNavState): boolean {
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

function SiteNav() {
  // null = unresolved (SSR + first hydrate: stable links only, no Sign in flash).
  const [state, setState] = useState<SiteNavState | null>(null);
  const motionProps = useNavMotion();

  useLayoutEffect(() => {
    const cached = readCached();
    if (cached) setState(cached);

    let cancelled = false;
    void fetch("/api/landing-nav", { credentials: "same-origin" })
      .then((res) => (res.ok ? res.json() : null))
      .then((raw: SiteNavState | null) => {
        if (cancelled) return;
        if (!raw) {
          setState((prev) => prev ?? { authed: false });
          return;
        }
        const next = normalize(raw);
        writeCached(next);
        setState((prev) => (prev && sameNav(prev, next) ? prev : next));
      })
      .catch(() => {
        if (!cancelled) setState((prev) => prev ?? { authed: false });
      });

    return () => {
      cancelled = true;
    };
  }, []);

  const onboarded = Boolean(state?.authed && state.onboarded);
  const showOps = Boolean(state?.authed && state.showOps);
  const showInvites = Boolean(state?.authed && state.showOrganization);

  return (
    <nav className="flex flex-wrap items-center justify-end gap-0.5 sm:gap-1">
      <a href="/docs" className={navLinkClass}>
        Docs
      </a>
      <TrackLink
        href="/waitlist?next=/download"
        event={AnalyticsEvent.DownloadNavClick}
        props={{ surface: "site_nav" }}
        className={navLinkClass}
      >
        Try Alpha
      </TrackLink>

      {state ? (
        <>
          <AnimatePresence initial={false}>
            {onboarded ? (
              <motion.div
                key="app-links"
                className="flex flex-wrap items-center gap-0.5 sm:gap-1"
                {...motionProps}
              >
                <a href="/contacts" className={navLinkClass}>
                  Contacts
                </a>
                {showInvites ? (
                  <a href="/admin/invites" className={navLinkClass}>
                    Invites
                  </a>
                ) : null}
                {showOps ? (
                  <a href="/admin/ops" className={navLinkClass}>
                    Ops
                  </a>
                ) : null}
              </motion.div>
            ) : null}
          </AnimatePresence>

          <AnimatePresence mode="wait" initial={false}>
            {state.authed && state.onboarded ? (
              <motion.div key="account" className="flex" {...motionProps}>
                <AccountMenu
                  label={state.handle}
                  avatarUrl={state.avatarUrl}
                  showOrganization={showInvites}
                />
              </motion.div>
            ) : state.authed ? (
              <motion.div
                key="setup"
                className="flex items-center gap-0.5 sm:gap-1"
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
                  props={{ surface: "site_nav" }}
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

const headerClass = {
  shell: "mb-10 flex items-center justify-between gap-4",
  landing:
    "relative z-10 flex items-center justify-between gap-4 px-6 py-5 sm:px-10 lg:px-14",
  login:
    "relative z-10 flex items-center justify-between gap-4 px-6 py-5 sm:px-8",
} as const;

/** One chrome for marketing + app pages. Docs (Nextra) stays its own navbar. */
export function SiteHeader({
  variant = "shell",
}: {
  variant?: keyof typeof headerClass;
}) {
  return (
    <header className={headerClass[variant]}>
      <BrandMark />
      <SiteNav />
    </header>
  );
}
