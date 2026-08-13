import { SiteHeader } from "@/components/site-header";
import { PageTitle, Shell } from "@/components/ui";
import { WaitlistForm } from "@/components/waitlist-form";

export const metadata = { title: "Join waitlist" };

export default function WaitlistPage() {
  return (
    <Shell>
      <SiteHeader />

      <PageTitle
        title="Join waitlist"
        subtitle="Five quick questions. We’ll use this to prioritize who gets in next — Mac alpha is open now if you want to try."
      />

      <WaitlistForm />
    </Shell>
  );
}
