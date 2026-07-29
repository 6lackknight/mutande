"use client";

import { useActionState, useMemo, useState } from "react";
import { createInviteAction, type ActionState } from "@/app/actions";
import { Alert, Button, Field, Input } from "@/components/ui";
import type { Invite } from "@/lib/types";

const initial: ActionState = {};

function joinPath(code: string): string {
  if (typeof window === "undefined") return `/join?invite=${code}`;
  return `${window.location.origin}/join?invite=${encodeURIComponent(code)}`;
}

export function InviteAdmin({
  initialInvites,
}: {
  initialInvites: Invite[];
}) {
  const [state, action, pending] = useActionState(createInviteAction, initial);
  const [copied, setCopied] = useState<string | null>(null);

  const invites = useMemo(() => {
    if (!state.inviteCode) return initialInvites;
    if (initialInvites.some((i) => i.code === state.inviteCode)) return initialInvites;
    return [
      {
        code: state.inviteCode,
        org_id: "",
        created_at: new Date().toISOString(),
        email: state.inviteEmail,
      },
      ...initialInvites,
    ];
  }, [initialInvites, state.inviteCode, state.inviteEmail]);

  async function copy(text: string, id: string) {
    try {
      await navigator.clipboard.writeText(text);
      setCopied(id);
      setTimeout(() => setCopied(null), 1600);
    } catch {
      setCopied(null);
    }
  }

  return (
    <div className="space-y-10">
      <form action={action} className="space-y-4">
        {state.error && !state.inviteCode ? (
          <Alert tone="danger">{state.error}</Alert>
        ) : null}
        {state.ok ? <Alert tone="ok">{state.ok}</Alert> : null}
        {state.emailSkipped ? (
          <Alert tone="amber">{state.emailSkipped}</Alert>
        ) : null}
        {state.error && state.inviteCode ? (
          <Alert tone="amber">Email: {state.error}</Alert>
        ) : null}

        {state.joinUrl ? (
          <div className="rounded-md border border-stone-300/70 bg-white/60 p-3 text-sm">
            <div className="text-muted">Shareable link</div>
            <div className="mt-1 break-all font-medium text-stone-800">
              {state.joinUrl}
            </div>
            <button
              type="button"
              className="mt-2 text-sm text-accent underline-offset-2 hover:underline"
              onClick={() => copy(state.joinUrl!, "new")}
            >
              {copied === "new" ? "Copied" : "Copy link"}
            </button>
          </div>
        ) : null}

        <Field
          label="Send invite email (optional)"
          hint="Uses Plunk when PLUNK_API_KEY is set. Otherwise create + copy link."
        >
          <Input
            name="email"
            type="email"
            placeholder="teammate@company.com"
            autoComplete="email"
          />
        </Field>

        <Button type="submit" disabled={pending}>
          {pending ? "Creating…" : "Create invite"}
        </Button>
      </form>

      <section>
        <h2 className="font-display text-xl text-stone-900">Invites</h2>
        {invites.length === 0 ? (
          <p className="mt-3 text-sm text-muted">No invites yet.</p>
        ) : (
          <ul className="mt-4 divide-y divide-stone-200/80 border-y border-stone-200/80">
            {invites.map((invite) => {
              const url = joinPath(invite.code);
              return (
                <li
                  key={invite.code}
                  className="flex flex-col gap-2 py-4 sm:flex-row sm:items-center sm:justify-between"
                >
                  <div>
                    <div className="font-medium text-stone-800">
                      {invite.email?.trim() || "No email"}
                    </div>
                    <div className="mt-0.5 break-all font-mono text-xs text-muted">
                      {invite.code}
                    </div>
                    <div className="mt-0.5 text-xs text-muted">
                      {invite.created_at
                        ? new Date(invite.created_at).toLocaleString()
                        : "—"}
                    </div>
                  </div>
                  <div className="flex gap-3 text-sm">
                    <button
                      type="button"
                      className="text-stone-700 underline-offset-2 hover:underline"
                      onClick={() => copy(invite.code, `code-${invite.code}`)}
                    >
                      {copied === `code-${invite.code}` ? "Copied" : "Copy code"}
                    </button>
                    <button
                      type="button"
                      className="text-accent underline-offset-2 hover:underline"
                      onClick={() => copy(url, `url-${invite.code}`)}
                    >
                      {copied === `url-${invite.code}` ? "Copied" : "Copy link"}
                    </button>
                  </div>
                </li>
              );
            })}
          </ul>
        )}
      </section>
    </div>
  );
}
