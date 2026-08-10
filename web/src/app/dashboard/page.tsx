import { BrandMark, ButtonLink, PageTitle, Shell } from "@/components/ui";
import { requireOnboarded, sessionShowsOps } from "@/lib/session";
import { isOrgAdmin } from "@/lib/types";

export const dynamic = "force-dynamic";
export const metadata = { title: "Dashboard" };

export default async function DashboardPage() {
  const me = await requireOnboarded();
  const isAdmin = isOrgAdmin(me.user);
  const showOps = await sessionShowsOps(me);

  return (
    <Shell wide>
      <div className="mb-10 flex items-center justify-between gap-4">
        <BrandMark />
        <a
          href="/auth/logout"
          className="text-sm text-muted hover:text-stone-800"
        >
          Sign out
        </a>
      </div>

      <PageTitle
        title="You’re set"
        subtitle="This web surface is for identity, org, and invites. Encrypted mail lives in the Mac app."
      />

      <dl className="grid gap-6 sm:grid-cols-2">
        <div>
          <dt className="text-[13px] font-medium uppercase tracking-[0.12em] text-muted">
            Handle
          </dt>
          <dd className="mt-1 font-display text-2xl text-stone-900">
            {me.user?.handle ?? "—"}
          </dd>
        </div>
        <div>
          <dt className="text-[13px] font-medium uppercase tracking-[0.12em] text-muted">
            Org
          </dt>
          <dd className="mt-1 font-display text-2xl text-stone-900">
            {me.org?.name ?? me.org?.slug ?? "—"}
            {me.org?.slug ? (
              <span className="ml-2 text-base font-sans text-muted">
                @{me.org.slug}
              </span>
            ) : null}
          </dd>
        </div>
      </dl>

      <div className="mt-10 flex flex-wrap gap-3">
        {isAdmin ? (
          <ButtonLink href="/admin/invites">Manage invites</ButtonLink>
        ) : null}
        {showOps ? (
          <ButtonLink href="/admin/ops" variant="secondary">
            Ops
          </ButtonLink>
        ) : null}
        <ButtonLink href="/download" variant="secondary">
          Download desktop app
        </ButtonLink>
      </div>
    </Shell>
  );
}
