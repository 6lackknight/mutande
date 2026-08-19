import { redirect } from "next/navigation";
import { OpsDashboard } from "@/components/ops-dashboard";
import { SiteHeader } from "@/components/site-header";
import { PageTitle, Shell } from "@/components/ui";
import {
  formatHubError,
  listEnterpriseMetrics,
  listFeedback,
  listOpsCensus,
  listRegistryAdmin,
  listWaitlistAdmin,
} from "@/lib/hub";
import { requireOnboarded, sessionShowsOps } from "@/lib/session";
import type {
  EnterpriseDeliveryMetric,
  Feedback,
  OpsCensus,
  RegistryListing,
  WaitlistEntry,
} from "@/lib/types";

export const dynamic = "force-dynamic";
export const metadata = { title: "Ops" };

export default async function AdminOpsPage() {
  const me = await requireOnboarded();
  if (!(await sessionShowsOps(me))) {
    redirect("/dashboard");
  }

  let feedback: Feedback[] = [];
  let waitlist: WaitlistEntry[] = [];
  let listings: RegistryListing[] = [];
  let metrics: EnterpriseDeliveryMetric[] = [];
  let census: OpsCensus | null = null;
  let listError: string | null = null;
  try {
    const [fb, wl, reg, met, cen] = await Promise.all([
      listFeedback(),
      listWaitlistAdmin(),
      listRegistryAdmin().catch(() => ({ listings: [] as RegistryListing[] })),
      listEnterpriseMetrics().catch(() => ({
        metrics: [] as EnterpriseDeliveryMetric[],
      })),
      listOpsCensus().catch(() => null),
    ]);
    feedback = fb.feedback ?? [];
    waitlist = wl.waitlist ?? [];
    listings = reg.listings ?? [];
    metrics = met.metrics ?? [];
    census = cen ?? null;
  } catch (err) {
    listError = formatHubError(err);
  }

  return (
    <Shell xl>
      <SiteHeader />
      <PageTitle
        title="Ops"
        subtitle="Phase 1 evidence, intake, and enterprise registry — Auth0 SuperAdmin only."
      />
      <OpsDashboard
        initialFeedback={feedback}
        initialWaitlist={waitlist}
        initialListings={listings}
        initialMetrics={metrics}
        initialCensus={census}
        loadError={listError}
      />
    </Shell>
  );
}
