import { Alert, BrandMark, ButtonLink, PageTitle, Shell } from "@/components/ui";
import { MAC_DMG_URL, MAC_DMG_VERSION } from "@/lib/downloads";
import { requireOnboarded } from "@/lib/session";
import { isOrgAdmin } from "@/lib/types";

export const dynamic = "force-dynamic";
export const metadata = { title: "Dashboard" };

export default async function DashboardPage() {
  const me = await requireOnboarded();
  const isAdmin = isOrgAdmin(me.user);

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
        <ButtonLink href={MAC_DMG_URL} variant="secondary">
          Download Mac app
        </ButtonLink>
      </div>

      <div id="download" className="mt-12 space-y-3">
        <Alert tone="ok">
          mutande for macOS {MAC_DMG_VERSION} — menu bar app with the local
          daemon bundled. Open the DMG and drag mutande into Applications.
        </Alert>
        <p className="text-sm text-muted">
          Direct link:{" "}
          <a
            href={MAC_DMG_URL}
            className="underline underline-offset-2 hover:text-stone-900"
          >
            mutande-{MAC_DMG_VERSION}.dmg
          </a>
        </p>
      </div>
    </Shell>
  );
}
