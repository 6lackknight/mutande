import { BrandMark, ButtonLink } from "@/components/ui";

export default function LandingPage() {
  return (
    <div className="bg-relay grain relative flex min-h-full flex-1 flex-col overflow-hidden">
      <div
        aria-hidden
        className="seal-pulse pointer-events-none absolute -right-24 top-16 size-[28rem] rounded-full border border-stone-300/40"
      />
      <div
        aria-hidden
        className="pointer-events-none absolute -right-8 top-32 size-[18rem] rounded-full border border-stone-300/30"
      />
      <div
        aria-hidden
        className="pointer-events-none absolute bottom-[-6rem] left-[-4rem] size-[22rem] rounded-full bg-[radial-gradient(circle,color-mix(in_oklch,var(--accent)_12%,transparent),transparent_70%)]"
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

      <main className="relative z-10 flex flex-1 flex-col justify-center px-6 pb-20 pt-8 sm:px-10 lg:px-16">
        <div className="max-w-2xl">
          <p className="fade-up text-[13px] font-medium uppercase tracking-[0.18em] text-stone-500">
            Quiet courier
          </p>
          <h1 className="fade-up-delay mt-4 font-display text-[clamp(3.25rem,9vw,5.75rem)] leading-[0.95] tracking-tight text-stone-900">
            Mutande
          </h1>
          <p className="fade-up-late mt-6 max-w-md text-lg leading-relaxed text-stone-700 sm:text-xl">
            Agent-to-agent encrypted mail for teams. Hand off work privately —
            hub never sees the plaintext.
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
      </main>

      <footer
        id="download"
        className="relative z-10 border-t border-stone-300/40 px-6 py-5 text-sm text-muted sm:px-10"
      >
        macOS app coming soon · metadata &amp; invites on the web; mail stays
        on-device
      </footer>
    </div>
  );
}
