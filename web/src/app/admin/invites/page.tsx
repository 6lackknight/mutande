import { redirect } from "next/navigation";
import { InviteAdmin } from "@/components/invite-admin";
import { Alert, BrandMark, PageTitle, Shell } from "@/components/ui";
import { formatHubError, listInvites } from "@/lib/hub";
import { requireOnboarded } from "@/lib/session";
import { isOpsAdmin, isOrgAdmin, type Invite } from "@/lib/types";

export const dynamic = "force-dynamic";
export const metadata = { title: "Invites" };

export default async function AdminInvitesPage() {
  const me = await requireOnboarded();
  const isAdmin = isOrgAdmin(me.user);
  const showOps = isOpsAdmin(me);

  if (!isAdmin) {
    redirect("/dashboard");
  }

  let invites: Invite[] = [];
  let listError: string | null = null;
  try {
    const data = await listInvites();
    invites = data.invites ?? [];
  } catch (err) {
    listError = formatHubError(err);
  }

  return (
    <Shell wide>
      <div className="mb-10 flex items-center justify-between gap-4">
        <BrandMark />
        <div className="flex flex-wrap items-center gap-4 text-sm">
          {showOps ? (
            <a href="/admin/ops" className="text-muted hover:text-stone-800">
              Ops
            </a>
          ) : null}
          <a href="/dashboard" className="text-muted hover:text-stone-800">
            Dashboard
          </a>
        </div>
      </div>
      <PageTitle
        title="Invites"
        subtitle={`Share a code or /join?invite=… link for ${me.org?.name ?? me.org?.slug ?? "your org"}. Optional email via Plunk.`}
      />
      {listError ? (
        <div className="mb-6">
          <Alert tone="amber">
            Couldn’t load invites: {listError}. You can still create one when the
            hub route is up.
          </Alert>
        </div>
      ) : null}
      <InviteAdmin initialInvites={invites} />
    </Shell>
  );
}
