"use client";

import { useActionState, useEffect, useMemo, useState } from "react";
import { useRouter } from "next/navigation";
import {
  mintConnectorAction,
  revokeConnectorAction,
  type ActionState,
} from "@/app/actions";
import { Alert, Button, Field, Input } from "@/components/ui";
import {
  MAX_MCP_CONNECTORS,
  MCP_CONNECTOR_URL,
  type McpConnector,
} from "@/lib/types";

const initial: ActionState = {};

function formatConnectorAgentAddress(
  mailHandle: string | undefined,
  slug: string,
): string {
  const s = slug.trim().toLowerCase() || "grok";
  const h = mailHandle?.trim().toLowerCase();
  if (h && !h.includes("/")) return `${h}/${s}`;
  return `you@org/${s}`;
}

function formatRelative(iso: string | undefined): string {
  if (!iso) return "";
  const t = Date.parse(iso);
  if (!Number.isFinite(t)) return "";
  const delta = Date.now() - t;
  if (delta < 0) return "";
  const minutes = Math.floor(delta / 60_000);
  if (minutes < 1) return "just now";
  if (minutes < 60) return `${minutes}m`;
  const hours = Math.floor(minutes / 60);
  if (hours < 24) {
    return new Date(t).toLocaleTimeString(undefined, {
      hour: "2-digit",
      minute: "2-digit",
    });
  }
  const days = Math.floor(hours / 24);
  if (days < 7) return `${days}d`;
  if (days < 30) return `${Math.floor(days / 7)}w`;
  return `${Math.floor(days / 30)}m`;
}

function CopyButton({
  text,
  copiedLabel = "Copied",
  idleLabel = "Copy",
}: {
  text: string;
  copiedLabel?: string;
  idleLabel?: string;
}) {
  const [copied, setCopied] = useState(false);

  async function copy() {
    try {
      await navigator.clipboard.writeText(text);
      setCopied(true);
      setTimeout(() => setCopied(false), 1600);
    } catch {
      setCopied(false);
    }
  }

  return (
    <button
      type="button"
      onClick={copy}
      className="text-sm font-medium text-accent underline-offset-2 hover:underline"
    >
      {copied ? copiedLabel : idleLabel}
    </button>
  );
}

function MintedSecretPanel({
  token,
  agentSlug,
  mailHandle,
  onDismiss,
}: {
  token: string;
  agentSlug?: string;
  mailHandle?: string;
  onDismiss: () => void;
}) {
  const slug = (agentSlug?.trim() || "grok").toLowerCase();
  const agentAddress = formatConnectorAgentAddress(mailHandle, slug);
  const [copied, setCopied] = useState(false);

  async function copy() {
    try {
      await navigator.clipboard.writeText(token);
      setCopied(true);
      setTimeout(() => setCopied(false), 1600);
    } catch {
      setCopied(false);
    }
  }

  return (
    <div className="rounded-md border border-accent/30 bg-accent-soft px-4 py-3">
      <p className="text-sm leading-relaxed text-stone-800">
        Copy this key now — mutande will not show it again.
      </p>
      <div className="mt-3 flex items-start gap-2 rounded-md bg-stone-900 px-3 py-2.5">
        <code className="min-w-0 flex-1 break-all font-mono text-[13px] leading-relaxed text-stone-50">
          {token}
        </code>
        <button
          type="button"
          onClick={() => void copy()}
          className="shrink-0 text-sm font-medium text-stone-200 underline-offset-2 hover:text-white hover:underline"
        >
          {copied ? "Copied" : "Copy"}
        </button>
      </div>
      <div className="mt-3 space-y-1 text-sm leading-relaxed text-stone-700">
        <p>
          In Grok Plugins, paste URL{" "}
          <code className="font-mono text-[13px]">{MCP_CONNECTOR_URL}</code>
        </p>
        <p>
          Header{" "}
          <code className="font-mono text-[13px]">X-Mutande-Connector</code>{" "}
          = this key. Slug{" "}
          <code className="font-mono text-[13px]">{slug}</code> is stored on
          this key — agent address{" "}
          <code className="font-mono text-[13px]">{agentAddress}</code>.
          {" "}
          <code className="font-mono text-[13px]">X-Mutande-Agent-Slug</code>{" "}
          overrides when set.
        </p>
      </div>
      <div className="mt-2 flex justify-end">
        <Button type="button" variant="ghost" onClick={onDismiss}>
          Done
        </Button>
      </div>
    </div>
  );
}

function ConnectorRow({
  connector,
  disabled,
}: {
  connector: McpConnector;
  disabled: boolean;
}) {
  const router = useRouter();
  const [state, action, pending] = useActionState(
    revokeConnectorAction,
    initial,
  );
  const [confirming, setConfirming] = useState(false);

  useEffect(() => {
    if (state.ok) router.refresh();
  }, [state.ok, router]);

  const created = formatRelative(connector.created_at);
  const used = formatRelative(connector.last_used_at);
  const meta = [
    connector.prefix,
    created,
    used ? `used ${used}` : null,
    connector.slug ? `@${connector.slug}` : null,
  ]
    .filter(Boolean)
    .join(" · ");

  return (
    <li className="flex flex-col gap-2 py-4 sm:flex-row sm:items-center sm:justify-between">
      <div className="min-w-0">
        <div className="font-medium text-stone-800">
          {connector.label.trim() || "Connector"}
        </div>
        {meta ? (
          <div className="mt-0.5 break-all font-mono text-xs text-muted">
            {meta}
          </div>
        ) : null}
        {state.error ? (
          <div className="mt-2">
            <Alert tone="danger">{state.error}</Alert>
          </div>
        ) : null}
        {confirming && !pending ? (
          <p className="mt-2 max-w-md text-sm leading-relaxed text-stone-600">
            Grok Plugins using “{connector.label.trim() || "this key"}” will
            stop reaching mutande. You can mint a new key after this.
          </p>
        ) : null}
      </div>
      <div className="flex shrink-0 items-center gap-2">
        {confirming ? (
          <>
            <Button
              type="button"
              variant="ghost"
              disabled={pending}
              onClick={() => setConfirming(false)}
            >
              Cancel
            </Button>
            <form action={action}>
              <input type="hidden" name="connector_id" value={connector.id} />
              <Button
                type="submit"
                variant="ghost"
                disabled={pending}
                className="text-red-800 hover:bg-red-50 hover:text-red-900"
              >
                {pending ? "Revoking…" : "Revoke"}
              </Button>
            </form>
          </>
        ) : (
          <Button
            type="button"
            variant="ghost"
            disabled={disabled || pending}
            className="text-red-800 hover:bg-red-50 hover:text-red-900"
            onClick={() => setConfirming(true)}
          >
            Revoke
          </Button>
        )}
      </div>
    </li>
  );
}

export function ConnectorsPanel({
  initialConnectors,
  mailHandle,
}: {
  initialConnectors: McpConnector[];
  mailHandle?: string;
}) {
  const router = useRouter();
  const [mintState, mintAction, mintPending] = useActionState(
    mintConnectorAction,
    initial,
  );
  const [secretDismissed, setSecretDismissed] = useState(false);
  const [seenIds, setSeenIds] = useState<Set<string>>(() => new Set());

  useEffect(() => {
    if (mintState.ok) {
      setSecretDismissed(false);
      router.refresh();
    }
  }, [mintState.ok, mintState.connectorToken, router]);

  useEffect(() => {
    setSeenIds((prev) => {
      const next = new Set(prev);
      let changed = false;
      for (const c of initialConnectors) {
        if (!next.has(c.id)) {
          next.add(c.id);
          changed = true;
        }
      }
      return changed ? next : prev;
    });
  }, [initialConnectors]);

  const connectors = useMemo(() => {
    const minted = mintState.connector;
    if (!minted) return initialConnectors;
    if (initialConnectors.some((c) => c.id === minted.id)) {
      return initialConnectors;
    }
    if (seenIds.has(minted.id)) return initialConnectors;
    return [minted, ...initialConnectors];
  }, [initialConnectors, mintState.connector, seenIds]);

  const atCap = connectors.length >= MAX_MCP_CONNECTORS;
  const mintedGone = Boolean(
    mintState.connector &&
      seenIds.has(mintState.connector.id) &&
      !initialConnectors.some((c) => c.id === mintState.connector?.id),
  );
  const revealed =
    !secretDismissed && mintState.connectorToken && !mintedGone
      ? mintState.connectorToken
      : null;

  return (
    <div className="space-y-10">
      <section className="space-y-4">
        <h2 className="font-display text-xl text-stone-900">Grok Bot</h2>
        <p className="max-w-prose text-[15px] leading-relaxed text-stone-600">
          Hosted MCP connector keys for Grok Plugins and similar header-auth
          hosts. Shown once at mint. ChatGPT and Claude web still use Auth0
          OAuth — this page is not that path.
        </p>
        <p className="max-w-prose text-sm leading-relaxed text-muted">
          Mail on this path uses app envelope, not end-to-end encryption. The
          hub can deliver readable payloads so a browser agent can work without
          a local keychain.
        </p>

        <div className="rounded-lg border border-stone-300/70 bg-white/60 p-4">
          <div className="text-[13px] font-medium tracking-wide text-stone-700">
            MCP URL
          </div>
          <div className="mt-1.5 flex flex-wrap items-start justify-between gap-2">
            <code className="break-all font-mono text-[13px] text-stone-800">
              {MCP_CONNECTOR_URL}
            </code>
            <CopyButton text={MCP_CONNECTOR_URL} idleLabel="Copy URL" />
          </div>
          <p className="mt-2 text-sm leading-relaxed text-muted">
            Header{" "}
            <code className="font-mono text-[12px]">X-Mutande-Connector</code>{" "}
            with the <code className="font-mono text-[12px]">mtc_…</code>{" "}
            secret. Each key stores an agent slug;{" "}
            <code className="font-mono text-[12px]">X-Mutande-Agent-Slug</code>{" "}
            overrides it when set.
          </p>
        </div>
      </section>

      {mintState.error ? <Alert tone="danger">{mintState.error}</Alert> : null}

      {revealed ? (
        <MintedSecretPanel
          token={revealed}
          agentSlug={mintState.connector?.slug}
          mailHandle={mailHandle}
          onDismiss={() => setSecretDismissed(true)}
        />
      ) : null}

      <form action={mintAction} className="space-y-4">
        <div className="grid gap-4 sm:grid-cols-2">
          <Field
            label="Label"
            hint="Shown in this list. Default is Grok Bot."
          >
            <Input
              name="label"
              defaultValue="Grok Bot"
              maxLength={64}
              autoComplete="off"
              placeholder="Grok Bot"
            />
          </Field>
          <Field
            label="Agent slug"
            hint="Bound when the connector is used. Default grok."
          >
            <Input
              name="slug"
              defaultValue="grok"
              maxLength={32}
              autoComplete="off"
              spellCheck={false}
              pattern="[a-z0-9-]{1,32}"
              title="1–32 lowercase letters, digits, or hyphens"
              placeholder="grok"
            />
          </Field>
        </div>
        <Button type="submit" disabled={mintPending || atCap}>
          {mintPending ? "Minting…" : atCap ? "Key limit reached" : "Mint key"}
        </Button>
        {atCap ? (
          <p className="text-xs text-muted">
            You already have {MAX_MCP_CONNECTORS} keys. Revoke one first.
          </p>
        ) : null}
      </form>

      <section>
        <h2 className="font-display text-xl text-stone-900">Keys</h2>
        {connectors.length === 0 && !revealed ? (
          <p className="mt-3 text-sm text-muted">No keys yet.</p>
        ) : connectors.length === 0 ? null : (
          <ul className="mt-4 divide-y divide-stone-200/80 border-y border-stone-200/80">
            {connectors.map((connector) => (
              <ConnectorRow
                key={connector.id}
                connector={connector}
                disabled={mintPending}
              />
            ))}
          </ul>
        )}
      </section>
    </div>
  );
}
