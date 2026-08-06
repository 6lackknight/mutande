import { redirect } from "next/navigation";
import { OpsDashboard } from "@/components/ops-dashboard";
import { BrandMark, PageTitle, Shell } from "@/components/ui";
import {
  formatHubError,
  listFeedback,
  listWaitlistAdmin,
} from "@/lib/hub";
import { requireOnboarded } from "@/lib/session";
import { isOpsAdmin, type Feedback, type WaitlistEntry } from "@/lib/types";

export const dynamic = "force-dynamic";
export const metadata = { title: "Ops" };

export default async function AdminOpsPage() {
  const me = await requireOnboarded();
  if (!isOpsAdmin(me)) {
    redirect("/dashboard");
  }

  let feedback: Feedback[] = [];
  let waitlist: WaitlistEntry[] = [];
  let listError: string | null = null;
  try {
    const [fb, wl] = await Promise.all([listFeedback(), listWaitlistAdmin()]);
    feedback = fb.feedback ?? [];
    waitlist = wl.waitlist ?? [];
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
        subtitle="Feedback and waitlist — Auth0 SuperAdmin only."
      />
      <OpsDashboard
        initialFeedback={feedback}
        initialWaitlist={waitlist}
        loadError={listError}
      />
    </Shell>
  );
}
