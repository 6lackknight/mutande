import { LandingForceField } from "@/components/landing-force-field";
import { LandingIntroVideo } from "@/components/landing-intro-video";
import { SiteHeader } from "@/components/site-header";
import { TrackButtonLink } from "@/components/track-button-link";
import { AnalyticsEvent } from "@/lib/analytics-events";
import { LANDING_INTRO_POSTER_URL } from "@/lib/brand-assets";

export default function LandingPage() {
  return (
    <LandingForceField>
      {/* Discover LCP poster in the initial document (cross-origin R2). */}
      <link
        rel="preload"
        as="image"
        href={LANDING_INTRO_POSTER_URL}
        fetchPriority="high"
      />
      <link rel="preconnect" href="https://downloads.mutande.online" />
      <div className="bg-relay grain relative flex min-h-dvh flex-1 flex-col overflow-hidden">
        <div
          aria-hidden
          className="pointer-events-none absolute inset-0 bg-[radial-gradient(ellipse_70%_50%_at_80%_20%,color-mix(in_oklch,var(--accent)_10%,transparent),transparent_60%)]"
        />

        <SiteHeader variant="landing" />

        <main className="relative z-10 flex flex-1 flex-col justify-center px-6 pb-12 pt-4 sm:px-10 lg:px-14">
          <div className="mx-auto grid w-full max-w-[72rem] items-center gap-10 md:grid-cols-[minmax(0,1fr)_minmax(0,1.05fr)] md:gap-x-10 md:gap-y-0 lg:gap-x-14 xl:gap-x-20">
            <div className="flex max-w-[28rem] flex-col md:max-w-none md:pr-2">
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
                  {" "}
                  <span className="whitespace-nowrap">— a spider’s web</span>
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
                  href="/waitlist?next=/download"
                  event={AnalyticsEvent.DownloadNavClick}
                  props={{ surface: "landing_hero" }}
                  variant="secondary"
                  className="min-w-[9.5rem]"
                >
                  Try Alpha
                </TrackButtonLink>
              </div>
            </div>

            <div className="fade-up-delay w-full max-w-[min(100%,28rem)] justify-self-center md:max-w-none md:justify-self-stretch">
              <div className="relative aspect-square w-full overflow-hidden rounded-[1.5rem] shadow-[0_28px_64px_-32px_rgba(28,25,23,0.45)] ring-1 ring-stone-900/5 sm:rounded-[1.75rem]">
                <LandingIntroVideo />
              </div>
            </div>
          </div>
        </main>

        <footer className="relative z-10 hidden items-center justify-end gap-4 px-6 py-5 text-sm sm:flex sm:px-10 lg:px-14">
          <a
            href="/changelog"
            className="text-stone-700 transition hover:text-stone-900"
          >
            Changelog
          </a>
          <a
            href="/terms"
            className="text-stone-700 transition hover:text-stone-900"
          >
            Terms
          </a>
        </footer>
      </div>
    </LandingForceField>
  );
}
