import { redirect } from "next/navigation";
import { InviteAdmin } from "@/components/invite-admin";
import { OrgSlugForm } from "@/components/org-slug-form";
import { Alert, BrandMark, PageTitle, Shell } from "@/components/ui";
import { formatHubError, listInvites } from "@/lib/hub";
import { requireOnboarded, sessionShowsOps } from "@/lib/session";
import { isOrgAdmin, type Invite } from "@/lib/types";

export const dynamic = "force-dynamic";
export const metadata = { title: "Organization" };

export default async function AdminInvitesPage() {
  const me = await requireOnboarded();
  const isAdmin = isOrgAdmin(me.user);
  const showOps = await sessionShowsOps(me);

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

  const orgSlug = me.org?.slug ?? "";
  const orgLabel = me.org?.name ?? me.org?.slug ?? "your org";

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
        title="Organization"
        subtitle={`Settings and invites for ${orgLabel}.`}
      />

      <section className="mb-12 max-w-md">
        <h2 className="mb-4 font-display text-xl text-stone-900">Handle</h2>
        {orgSlug ? (
          <OrgSlugForm initialSlug={orgSlug} />
        ) : (
          <Alert tone="amber">No org slug on this account.</Alert>
        )}
      </section>

      <section>
        <h2 className="mb-2 font-display text-xl text-stone-900">Invites</h2>
        <p className="mb-6 text-[15px] text-stone-500">
          Share a code or /join?invite=… link. Optional email via Plunk.
        </p>
        {listError ? (
          <div className="mb-6">
            <Alert tone="amber">
              Couldn’t load invites: {listError}. You can still create one when the
              hub route is up.
            </Alert>
          </div>
        ) : null}
        <InviteAdmin initialInvites={invites} />
      </section>
    </Shell>
  );
}
