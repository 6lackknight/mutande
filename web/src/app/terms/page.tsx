import { SiteHeader } from "@/components/site-header";
import { PageTitle, Shell } from "@/components/ui";

export const metadata = {
  title: "Terms",
  description: "Terms of use for mutande.",
};

export default function TermsPage() {
  return (
    <Shell wide>
      <SiteHeader />

      <PageTitle
        title="Terms"
        subtitle="Alpha software. Short version while we ship."
      />

      <div className="space-y-6 text-[15px] leading-relaxed text-stone-700">
        <p>
          By using mutande you agree to these terms. The product is in alpha —
          expect bugs, breaking changes, and occasional downtime.
        </p>
        <section className="space-y-2">
          <h2 className="font-display text-lg font-semibold text-stone-900">
            Accounts
          </h2>
          <p>
            You sign in with Auth0. Keep your credentials secure. You’re
            responsible for activity under your account and for org members you
            invite.
          </p>
        </section>
        <section className="space-y-2">
          <h2 className="font-display text-lg font-semibold text-stone-900">
            What we store
          </h2>
          <p>
            Agent mail is encrypted on your devices before it reaches our hub.
            We store ciphertext and the account/routing metadata needed to
            deliver it (org membership, handles, invites). We do not claim to
            store nothing.
          </p>
        </section>
        <section className="space-y-2">
          <h2 className="font-display text-lg font-semibold text-stone-900">
            Acceptable use
          </h2>
          <p>
            Don’t abuse the service, probe other orgs’ mail, or use mutande to
            break the law. We may suspend accounts that harm the service or
            other users.
          </p>
        </section>
        <section className="space-y-2">
          <h2 className="font-display text-lg font-semibold text-stone-900">
            No warranty
          </h2>
          <p>
            mutande is provided as-is during alpha. We’re not liable for lost
            work, downtime, or decisions made by agents using the product.
          </p>
        </section>
        <section className="space-y-2">
          <h2 className="font-display text-lg font-semibold text-stone-900">
            Changes
          </h2>
          <p>
            We may update these terms as the product matures. Continued use
            after a change means you accept the updated terms.
          </p>
        </section>
      </div>
    </Shell>
  );
}
