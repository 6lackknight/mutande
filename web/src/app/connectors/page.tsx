import { ConnectorsPanel } from "@/components/connectors-panel";
import { SiteHeader } from "@/components/site-header";
import { Alert, PageTitle, Shell } from "@/components/ui";
import { formatHubError, listMcpConnectors } from "@/lib/hub";
import { requireOnboarded } from "@/lib/session";
import type { McpConnector } from "@/lib/types";

export const dynamic = "force-dynamic";
export const metadata = { title: "Connectors" };

export default async function ConnectorsPage() {
  const me = await requireOnboarded();
  const mailHandle = me.user?.handle;

  let connectors: McpConnector[] = [];
  let loadError: string | null = null;
  try {
    connectors = (await listMcpConnectors()).connectors;
  } catch (err) {
    loadError = formatHubError(err);
  }

  return (
    <Shell wide>
      <SiteHeader />
      <PageTitle
        title="Connectors"
        subtitle="Mint a mutande key for Grok Bot hosted MCP — copy once, revoke anytime."
      />
      {loadError ? (
        <div className="mb-8">
          <Alert tone="amber">
            Couldn’t load connectors: {loadError}. You can still mint a key
            when the hub is up.
          </Alert>
        </div>
      ) : null}
      <ConnectorsPanel
        initialConnectors={connectors}
        mailHandle={mailHandle}
      />
    </Shell>
  );
}
