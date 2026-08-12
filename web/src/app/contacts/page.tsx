import { ExternalContactsList } from "@/components/external-contacts-list";
import { LoggedInHeader } from "@/components/logged-in-header";
import { PairingPinCard } from "@/components/pairing-pin-card";
import { PendingPairList } from "@/components/pending-pair-list";
import { RequestPairForm } from "@/components/request-pair-form";
import { TeamContactsList } from "@/components/team-contacts-list";
import { Alert, PageTitle, Shell } from "@/components/ui";
import {
  formatHubError,
  getPairingPin,
  listContacts,
  listExternalContacts,
  listPendingPairRequests,
} from "@/lib/hub";
import { requireOnboarded } from "@/lib/session";
import { isOrgAdmin, type Contact, type PairRequest, type PairingPinResponse } from "@/lib/types";

export const dynamic = "force-dynamic";
export const metadata = { title: "Contacts" };

export default async function ContactsPage() {
  const me = await requireOnboarded();
  const isAdmin = isOrgAdmin(me.user);

  let pin: PairingPinResponse | null = null;
  let orgContacts: Contact[] = [];
  let external: Contact[] = [];
  let incoming: PairRequest[] = [];
  let outgoing: PairRequest[] = [];
  let loadError: string | null = null;

  try {
    const [pinRes, orgRes, extRes, pendingRes] = await Promise.all([
      getPairingPin(),
      listContacts(),
      listExternalContacts(),
      listPendingPairRequests(),
    ]);
    pin = pinRes;
    orgContacts = orgRes.contacts;
    external = extRes.contacts;
    incoming = pendingRes.incoming;
    outgoing = pendingRes.outgoing;
  } catch (err) {
    loadError = formatHubError(err);
  }

  return (
    <Shell wide>
      <LoggedInHeader />
      <PageTitle
        title="Contacts"
        subtitle="Pair with people outside your org, or copy teammate handles. Encrypted mail still lives in the desktop app."
      />

      {loadError ? (
        <div className="mb-8">
          <Alert tone="amber">
            Couldn’t load contacts: {loadError}. Try again when the hub is up.
          </Alert>
        </div>
      ) : null}

      <div className="space-y-12">
        <section className="max-w-md">
          <h2 className="mb-4 font-display text-xl text-stone-900">
            Your pairing PIN
          </h2>
          <PairingPinCard initialPin={pin} />
        </section>

        <section className="max-w-md">
          <h2 className="mb-4 font-display text-xl text-stone-900">
            Add contact
          </h2>
          <RequestPairForm />
        </section>

        <section>
          <h2 className="mb-4 font-display text-xl text-stone-900">Pending</h2>
          <PendingPairList incoming={incoming} outgoing={outgoing} />
        </section>

        <section>
          <h2 className="mb-4 font-display text-xl text-stone-900">External</h2>
          <ExternalContactsList contacts={external} />
        </section>

        <section>
          <h2 className="mb-4 font-display text-xl text-stone-900">Team</h2>
          <TeamContactsList contacts={orgContacts} showInviteLink={isAdmin} />
        </section>
      </div>
    </Shell>
  );
}
