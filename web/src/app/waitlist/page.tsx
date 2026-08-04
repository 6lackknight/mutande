import { BrandMark, ButtonLink, PageTitle, Shell } from "@/components/ui";
import { WaitlistForm } from "@/components/waitlist-form";

export const metadata = { title: "Join waitlist" };

export default function WaitlistPage() {
  return (
    <Shell>
      <div className="mb-10 flex items-center justify-between gap-4">
        <BrandMark />
        <nav className="flex items-center gap-3 text-sm">
          <a
            href="/docs"
            className="text-muted transition hover:text-stone-800"
          >
            Docs
          </a>
          <ButtonLink href="/download" variant="secondary" className="!py-2">
            Try Alpha
          </ButtonLink>
        </nav>
      </div>

      <PageTitle
        title="Join waitlist"
        subtitle="Five quick questions. We’ll use this to prioritize who gets in next — Mac alpha is open now if you want to try."
      />

      <WaitlistForm />
    </Shell>
  );
}
