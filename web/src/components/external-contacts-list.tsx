"use client";

import { useActionState, useEffect } from "react";
import { useRouter } from "next/navigation";
import { unpairExternalContactAction, type ActionState } from "@/app/actions";
import { ContactAvatar } from "@/components/contact-avatar";
import { Alert, Button } from "@/components/ui";
import type { Contact } from "@/lib/types";

const initial: ActionState = {};

function ExternalRow({ contact }: { contact: Contact }) {
  const router = useRouter();
  const [state, action, pending] = useActionState(
    unpairExternalContactAction,
    initial,
  );

  useEffect(() => {
    if (state.ok) router.refresh();
  }, [state.ok, router]);

  const linkId = contact.external_link_id;
  if (!linkId) return null;

  return (
    <li className="space-y-2 border-b border-stone-200/80 py-4 last:border-0">
      {state.error ? <Alert tone="danger">{state.error}</Alert> : null}
      {state.ok && !pending ? <Alert tone="ok">{state.ok}</Alert> : null}
      <div className="flex flex-wrap items-center justify-between gap-3">
        <span className="flex min-w-0 items-center gap-3">
          <ContactAvatar
            handle={contact.handle}
            avatarUrl={contact.avatar_url}
            name={contact.display_name}
          />
          <span className="min-w-0">
            <span className="block truncate font-medium leading-tight text-stone-900">
              {(contact.display_name ?? "").trim() ||
                contact.handle.split("@")[0] ||
                contact.handle}
            </span>
            <span className="mt-0.5 block truncate text-[12px] leading-snug text-muted">
              {contact.handle}
            </span>
          </span>
        </span>
        <form action={action}>
          <input type="hidden" name="link_id" value={linkId} />
          <Button type="submit" variant="ghost" disabled={pending}>
            {pending ? "Removing…" : "Unpair"}
          </Button>
        </form>
      </div>
    </li>
  );
}

export function ExternalContactsList({ contacts }: { contacts: Contact[] }) {
  if (contacts.length === 0) {
    return (
      <p className="text-sm text-muted">No external contacts yet.</p>
    );
  }

  return (
    <ul>
      {contacts.map((c) => (
        <ExternalRow key={c.external_link_id ?? c.handle} contact={c} />
      ))}
    </ul>
  );
}
