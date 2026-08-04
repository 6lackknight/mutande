import { LandingForceField } from "@/components/landing-force-field";
import { LandingIntroVideo } from "@/components/landing-intro-video";
import { TrackButtonLink } from "@/components/track-button-link";
import { TrackLink } from "@/components/track-link";
import { BrandMark } from "@/components/ui";
import { AnalyticsEvent } from "@/lib/analytics-events";

export default function LandingPage() {
  return (
    <LandingForceField>
      <div className="bg-relay grain relative flex min-h-dvh flex-1 flex-col overflow-hidden">
        <div
          aria-hidden
          className="pointer-events-none absolute inset-0 bg-[radial-gradient(ellipse_70%_50%_at_80%_20%,color-mix(in_oklch,var(--accent)_10%,transparent),transparent_60%)]"
        />

        <header className="relative z-10 flex items-center justify-between px-6 py-5 sm:px-10 lg:px-14">
          <BrandMark />
          <nav className="flex items-center gap-1 sm:gap-2">
            <a
              href="/docs"
              className="rounded-md px-3 py-2 text-sm text-stone-700 transition hover:bg-stone-200/40"
            >
              Docs
            </a>
            <TrackLink
              href="/download"
              event={AnalyticsEvent.DownloadNavClick}
              props={{ surface: "landing_nav" }}
              className="rounded-md px-3 py-2 text-sm text-stone-700 transition hover:bg-stone-200/40"
            >
              Try Alpha
            </TrackLink>
            <TrackLink
              href="/login"
              event={AnalyticsEvent.SignInClick}
              props={{ surface: "landing_nav" }}
              className="rounded-md px-3 py-2 text-sm text-stone-700 transition hover:bg-stone-200/40"
            >
              Sign in
            </TrackLink>
          </nav>
        </header>

        <main className="relative z-10 flex flex-1 flex-col justify-center px-6 pb-24 pt-4 sm:px-10 lg:px-14">
          <div className="mx-auto grid w-full max-w-[72rem] items-center gap-10 lg:grid-cols-[minmax(0,1fr)_minmax(0,1.05fr)] lg:gap-x-14 lg:gap-y-0 xl:gap-x-20">
            <div className="flex max-w-[28rem] flex-col lg:max-w-none lg:pr-2">
              <h1 className="fade-up order-1 font-display text-[clamp(3.25rem,8.5vw,5.75rem)] font-semibold leading-[0.92] tracking-[-0.04em] text-stone-900 max-sm:sr-only">
                mutande
              </h1>
              <p className="fade-up order-3 mt-2 text-[0.75rem] leading-snug text-stone-500 sm:order-2 sm:text-[0.95rem] md:text-base">
                <span className="italic">/moo-TAHN-deh/</span>
                <span className="mx-1.5 text-stone-300">·</span>
                <span className="italic">n.</span>
                <span className="mx-1.5 text-stone-300">·</span>
                <span>
                  Shona · from{" "}
                  <em className="not-italic text-stone-600">
                    dande
                    <span className="underline decoration-stone-400 underline-offset-2">
                      mutande
                    </span>
                  </em>
                  {" — "}a spider’s web
                </span>
              </p>
              <h2 className="fade-up-delay order-2 mt-0 max-w-md font-display text-[clamp(1.5rem,3.5vw,2rem)] font-semibold leading-snug tracking-[-0.03em] text-stone-900 sm:order-3 sm:mt-6">
                Address Intelligence.
              </h2>
              <p className="fade-up-delay order-4 mt-3 max-w-md text-[1.05rem] leading-relaxed text-stone-700 sm:text-xl">
                Give every intelligence in your organisation a trusted address.
                Route work by identity, not implementation.
              </p>
              <div className="fade-up-late order-5 mt-8 flex flex-wrap items-center gap-3 sm:mt-10">
                <TrackButtonLink
                  href="/waitlist"
                  event={AnalyticsEvent.WaitlistClick}
                  props={{ surface: "landing_hero" }}
                  className="min-w-[9.5rem]"
                >
                  Join waitlist
                </TrackButtonLink>
                <TrackButtonLink
                  href="/download"
                  event={AnalyticsEvent.DownloadNavClick}
                  props={{ surface: "landing_hero" }}
                  variant="secondary"
                  className="min-w-[9.5rem]"
                >
                  Try Alpha
                </TrackButtonLink>
              </div>
            </div>

            <div className="fade-up-delay w-full max-w-[min(100%,28rem)] justify-self-center lg:max-w-none lg:justify-self-stretch">
              <div className="relative aspect-square w-full overflow-hidden rounded-[1.5rem] shadow-[0_28px_64px_-32px_rgba(28,25,23,0.45)] ring-1 ring-stone-900/5 sm:rounded-[1.75rem]">
                <LandingIntroVideo />
              </div>
            </div>
          </div>
        </main>

        <footer className="fixed bottom-0 left-0 right-0 z-20 hidden flex-wrap items-center justify-between gap-3 border-t border-stone-300/40 bg-[color-mix(in_oklch,var(--stone-50)_92%,transparent)] px-6 py-5 text-sm text-muted backdrop-blur-sm sm:flex sm:px-10 lg:px-14">
          <span>
            macOS menu bar · metadata &amp; invites on the web · mail stays
            on-device
          </span>
          <a
            href="/docs"
            className="text-stone-700 transition hover:text-stone-900"
          >
            Docs
          </a>
        </footer>
      </div>
    </LandingForceField>
  );
}
