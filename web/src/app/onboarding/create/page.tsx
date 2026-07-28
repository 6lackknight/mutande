import { redirect } from "next/navigation";
import { CreateOrgForm } from "@/components/create-org-form";
import { Alert, BrandMark, PageTitle, Shell } from "@/components/ui";
import { loadMeOrNull, requireSession } from "@/lib/session";

export const dynamic = "force-dynamic";
export const metadata = { title: "Create team" };

export default async function CreateTeamPage() {
  const session = await requireSession();
  const { me, error } = await loadMeOrNull();

  if (me?.onboarded) redirect("/dashboard");

  const email =
    typeof session.user.email === "string" ? session.user.email : undefined;
  const emailLocal =
    (email ?? "user").split("@")[0]?.toLowerCase().replace(/[^a-z0-9._-]/g, "") ||
    "user";

  return (
    <Shell>
      <div className="mb-10 flex items-center justify-between gap-4">
        <BrandMark />
        <a href="/signup" className="text-sm text-muted hover:text-stone-800">
          Back
        </a>
      </div>
      <PageTitle
        title="Create your team"
        subtitle="Pick an org slug. Your handle defaults to email-local@org and stays editable."
      />
      {error ? (
        <div className="mb-6">
          <Alert tone="amber">
            Hub status: {error}. You can still fill the form; create will retry
            against the hub.
          </Alert>
        </div>
      ) : null}
      <CreateOrgForm emailLocal={emailLocal} />
    </Shell>
  );
}
