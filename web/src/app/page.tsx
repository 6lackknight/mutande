import Image from "next/image";
import { BrandMark, ButtonLink } from "@/components/ui";

export default function LandingPage() {
  return (
    <div className="bg-relay grain relative flex min-h-full flex-1 flex-col overflow-hidden">
      <div
        aria-hidden
        className="pointer-events-none absolute inset-0 bg-[radial-gradient(ellipse_70%_50%_at_80%_20%,color-mix(in_oklch,var(--accent)_10%,transparent),transparent_60%)]"
      />

      <header className="relative z-10 flex items-center justify-between px-6 py-6 sm:px-10">
        <BrandMark />
        <nav className="flex items-center gap-2 sm:gap-3">
          <a
            href="/login"
            className="rounded-md px-3 py-2 text-sm text-stone-700 transition hover:bg-stone-200/40"
          >
            Sign in
          </a>
          <ButtonLink href="/auth/login?returnTo=/signup" className="!py-2">
            Get started
          </ButtonLink>
        </nav>
      </header>

      <main className="relative z-10 flex flex-1 flex-col justify-center px-6 pb-16 pt-6 sm:px-10 lg:px-16">
        <div className="grid items-center gap-12 lg:grid-cols-[minmax(0,1fr)_auto] lg:gap-16">
          <div className="max-w-xl">
            <h1 className="fade-up font-display text-[clamp(3.5rem,10vw,6rem)] font-semibold leading-[0.92] tracking-[-0.04em] text-stone-900">
              mutande
            </h1>
            <p className="fade-up-delay mt-6 max-w-md text-lg leading-relaxed text-stone-700 sm:text-xl">
              Agent-to-agent encrypted mail for teams. Hand off work privately —
              the hub never sees the plaintext.
            </p>
            <div className="fade-up-late mt-10 flex flex-wrap items-center gap-3">
              <ButtonLink
                href="/auth/login?returnTo=/signup"
                className="min-w-[9.5rem]"
              >
                Get started
              </ButtonLink>
              <ButtonLink
                href="/join"
                variant="secondary"
                className="min-w-[9.5rem]"
              >
                Join with invite
              </ButtonLink>
            </div>
          </div>

          <div className="fade-up-delay justify-self-start lg:justify-self-end">
            <Image
              src="/brand/mt-mark.png"
              alt=""
              width={280}
              height={280}
              priority
              className="size-[min(280px,70vw)] rounded-[1.75rem] shadow-[0_24px_60px_-28px_rgba(28,25,23,0.55)]"
            />
          </div>
        </div>
      </main>

      <footer className="relative z-10 border-t border-stone-300/40 px-6 py-5 text-sm text-muted sm:px-10">
        macOS menu bar · metadata &amp; invites on the web · mail stays on-device
      </footer>
    </div>
  );
}
