import { KineticText } from "@/components/magicui/kinetic-text";
import { OrgNetwork, type OrgNetworkPerson } from "@/components/org-network";
import { SiteHeader } from "@/components/site-header";
import { TrackButtonLink } from "@/components/track-button-link";
import { Shell } from "@/components/ui";
import { AnalyticsEvent } from "@/lib/analytics-events";
import { formatHubError, listContacts, listInvites } from "@/lib/hub";
import { joinUrlForCode, requireOnboarded } from "@/lib/session";
import { isOrgAdmin, type Contact } from "@/lib/types";

export const dynamic = "force-dynamic";
export const metadata = { title: "Dashboard" };

function bareHandle(handle: string): string {
  return handle.trim().toLowerCase();
}

function networkPeople(
  meHandle: string,
  meAvatar: string | undefined,
  meDisplayName: string | undefined,
  contacts: Contact[],
): OrgNetworkPerson[] {
  const mine = bareHandle(meHandle);
  const teammates = contacts.filter((c) => {
    if (c.kind === "broadcast") return false;
    const h = bareHandle(c.handle);
    return h.length > 0 && h !== mine;
  });
  const seen = new Set<string>();
  const people: OrgNetworkPerson[] = [];
  if (mine) {
    seen.add(mine);
    people.push({
      handle: meHandle.trim().toLowerCase(),
      label: "you",
      isSelf: true,
      avatarUrl: meAvatar,
      displayName: meDisplayName?.trim() || undefined,
    });
  }
  for (const c of teammates) {
    const h = bareHandle(c.handle);
    if (seen.has(h)) continue;
    seen.add(h);
    people.push({
      handle: h,
      label: (c.display_name ?? "").trim() || h.split("@")[0] || h,
      avatarUrl: c.avatar_url,
      displayName: (c.display_name ?? "").trim() || undefined,
    });
  }
  return people;
}

export default async function DashboardPage() {
  const me = await requireOnboarded();
  const isAdmin = isOrgAdmin(me.user);
  const handle = (me.user?.handle ?? "").trim().toLowerCase();
  const displayName = (me.user?.display_name ?? "").trim();
  const greetName = displayName || handle;
  const orgSlug = (me.org?.slug ?? "").trim().toLowerCase();
  const orgName = me.org?.name ?? me.org?.slug ?? "—";

  let contacts: Contact[] = [];
  let loadError: string | null = null;
  let joinUrl: string | undefined;
  try {
    contacts = (await listContacts()).contacts;
  } catch (err) {
    loadError = formatHubError(err);
  }
  if (isAdmin) {
    try {
      const { invites } = await listInvites();
      const latest = [...invites].sort(
        (a, b) => Date.parse(b.created_at) - Date.parse(a.created_at),
      )[0];
      if (latest?.code) joinUrl = joinUrlForCode(latest.code);
    } catch {
      /* Invites are admin-only; skip QR if the hub call fails. */
    }
  }

  return (
    <Shell xl>
      <SiteHeader />

      <div className="flex flex-col gap-12 pt-2 sm:gap-16">
        <div className="grid items-start gap-8 lg:grid-cols-[minmax(0,1fr)_minmax(18rem,22rem)] lg:gap-x-12 lg:gap-y-0">
          <header className="fade-up min-w-0">
            <p className="text-[15px] text-stone-600 sm:text-base">
              Welcome back
            </p>
            {greetName ? (
              <KineticText
                text={greetName}
                as="h1"
                className="-ml-[0.04em] mt-1 max-w-full font-display text-[clamp(2.25rem,6.5vw,4.5rem)] font-semibold leading-[0.95] tracking-[-0.045em] text-stone-900"
              />
            ) : (
              <h1 className="-ml-[0.04em] mt-1 font-display text-[clamp(2.25rem,6.5vw,4.5rem)] font-semibold leading-[0.95] tracking-[-0.045em] text-stone-900">
                Welcome back
              </h1>
            )}
            <p className="fade-up-delay mt-4 max-w-md text-[15px] leading-relaxed text-stone-600 sm:text-base">
              Identity and team live here. Sealed agent mail waits on your desk.
            </p>
          </header>

          <section className="fade-up-late relative overflow-hidden rounded-2xl bg-stone-900 px-5 py-6 text-stone-50 sm:px-6 sm:py-7 lg:mt-1">
            <span
              aria-hidden
              className="seal-pulse pointer-events-none absolute -right-8 -top-10 h-32 w-32 rounded-full bg-[color-mix(in_oklch,var(--accent)_50%,transparent)] blur-3xl"
            />
            <h2 className="relative font-display text-[1.35rem] font-semibold leading-[1.1] tracking-[-0.03em] sm:text-[1.5rem]">
              Mail lives on your desk
            </h2>
            <p className="relative mt-2 text-[15px] leading-relaxed text-stone-300">
              Connect Cursor, Claude, or ChatGPT. Threads and files stay on your
              machines — this browser can’t open that inbox.
            </p>
            <TrackButtonLink
              href="/download"
              event={AnalyticsEvent.DownloadNavClick}
              props={{ surface: "dashboard_cta" }}
              className="relative mt-5 w-full !bg-stone-50 !text-stone-900 hover:!bg-white"
            >
              Download mutande
            </TrackButtonLink>
          </section>
        </div>

        <OrgNetwork
          orgSlug={orgSlug}
          orgName={orgName === "—" ? undefined : orgName}
          handle={handle || undefined}
          people={networkPeople(
            handle,
            me.user?.avatar_url,
            displayName || undefined,
            contacts,
          )}
          inviteHref={isAdmin ? "/admin/invites" : undefined}
          joinUrl={joinUrl}
          loadError={loadError}
        />
      </div>
    </Shell>
  );
}
