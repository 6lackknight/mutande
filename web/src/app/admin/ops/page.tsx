import { redirect } from "next/navigation";
import { OpsDashboard } from "@/components/ops-dashboard";
import { BrandMark, PageTitle, Shell } from "@/components/ui";
import {
  formatHubError,
  listEnterpriseMetrics,
  listFeedback,
  listRegistryAdmin,
  listWaitlistAdmin,
} from "@/lib/hub";
import { requireOnboarded, sessionShowsOps } from "@/lib/session";
import type {
  EnterpriseDeliveryMetric,
  Feedback,
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
  let listError: string | null = null;
  try {
    const [fb, wl, reg, met] = await Promise.all([
      listFeedback(),
      listWaitlistAdmin(),
      listRegistryAdmin().catch(() => ({ listings: [] as RegistryListing[] })),
      listEnterpriseMetrics().catch(() => ({
        metrics: [] as EnterpriseDeliveryMetric[],
      })),
    ]);
    feedback = fb.feedback ?? [];
    waitlist = wl.waitlist ?? [];
    listings = reg.listings ?? [];
    metrics = met.metrics ?? [];
  } catch (err) {
    listError = formatHubError(err);
  }

  return (
    <Shell xl>
      <div className="mb-10 flex items-center justify-between gap-4">
        <BrandMark />
        <div className="flex flex-wrap items-center gap-4 text-sm">
          <a
            href="/admin/invites"
            className="text-muted hover:text-stone-800"
          >
            Invites
          </a>
          <a href="/dashboard" className="text-muted hover:text-stone-800">
            Dashboard
          </a>
        </div>
      </div>
      <PageTitle
        title="Ops"
        subtitle="Feedback, waitlist, and enterprise registry — Auth0 SuperAdmin only."
      />
      <OpsDashboard
        initialFeedback={feedback}
        initialWaitlist={waitlist}
        initialListings={listings}
        initialMetrics={metrics}
        loadError={listError}
      />
    </Shell>
  );
}
