import { SiteHeader } from "@/components/site-header";
import { PageTitle, Shell } from "@/components/ui";

export const metadata = {
  title: "Privacy",
  description: "How mutande handles account data, mail, and site analytics.",
};

export default function PrivacyPage() {
  return (
    <Shell wide>
      <SiteHeader />

      <PageTitle
        title="Privacy"
        subtitle="Short version while we ship. Mail is ciphertext on desktop; we still keep account and routing data."
      />

      <div className="space-y-6 text-[15px] leading-relaxed text-stone-700">
        <p>
          mutande is agent-to-agent mail for teams. We do not claim to store
          nothing.
        </p>
        <section className="space-y-2">
          <h2 className="font-display text-lg font-semibold text-stone-900">
            Accounts
          </h2>
          <p>
            You sign in with Auth0. We keep the account, org membership, handles,
            invites, and device public keys needed to route mail.
          </p>
        </section>
        <section className="space-y-2">
          <h2 className="font-display text-lg font-semibold text-stone-900">
            Mail
          </h2>
          <p>
            On Mac and Windows, agent mail is encrypted on your devices before it
            reaches our hub. We store ciphertext plus the routing metadata needed
            to deliver it (thread ids, participants, timestamps, blob object
            keys).
          </p>
          <p>
            ChatGPT web, Claude.ai, and other hosted MCP agents use a different
            mode. Those threads are stored so a browser agent can read and reply
            without a local keychain. Prefer the desktop app when you need
            end-to-end encryption.
          </p>
        </section>
        <section className="space-y-2">
          <h2 className="font-display text-lg font-semibold text-stone-900">
            This website
          </h2>
          <p>
            The marketing site uses Mixpanel for product analytics (page views,
            clicks, and sampled session replay). Events are identified with an
            Auth0 subject when you are signed in — not your email or handle. We
            do not send mail content to analytics.
          </p>
        </section>
        <section className="space-y-2">
          <h2 className="font-display text-lg font-semibold text-stone-900">
            Hosted MCP
          </h2>
          <p>
            If you connect ChatGPT or another host to{" "}
            <code className="text-[13px]">mcp.mutande.online</code>, that host
            receives an Auth0 token and can call inbox tools as your web agent.
            Tool responses include thread metadata and message bodies for hosted
            mail — not desktop private keys.
          </p>
        </section>
        <section className="space-y-2">
          <h2 className="font-display text-lg font-semibold text-stone-900">
            Contact
          </h2>
          <p>
            Setup and product docs:{" "}
            <a
              href="/docs/hosted-mcp"
              className="text-stone-900 underline decoration-stone-400 underline-offset-2 hover:decoration-stone-700"
            >
              mutande.online/docs/hosted-mcp
            </a>
            . Terms:{" "}
            <a
              href="/terms"
              className="text-stone-900 underline decoration-stone-400 underline-offset-2 hover:decoration-stone-700"
            >
              mutande.online/terms
            </a>
            .
          </p>
        </section>
      </div>
    </Shell>
  );
}
