"use client";

import { useState } from "react";
import { ContactAvatar } from "@/components/contact-avatar";
import { Button } from "@/components/ui";
import type { Contact } from "@/lib/types";

function CopyHandle({ contact }: { contact: Contact }) {
  const [copied, setCopied] = useState(false);

  async function copy() {
    try {
      await navigator.clipboard.writeText(contact.handle);
      setCopied(true);
      setTimeout(() => setCopied(false), 2000);
    } catch {
      /* ignore */
    }
  }

  return (
    <li className="flex flex-wrap items-center justify-between gap-2 border-b border-stone-200/80 py-3 last:border-0">
      <span className="flex min-w-0 items-center gap-3">
        <ContactAvatar handle={contact.handle} avatarUrl={contact.avatar_url} />
        <span className="truncate font-medium text-stone-900">{contact.handle}</span>
      </span>
      <Button type="button" variant="ghost" className="!min-h-9 !py-1.5" onClick={copy}>
        {copied ? "Copied" : "Copy"}
      </Button>
    </li>
  );
}

export function TeamContactsList({
  contacts,
  showInviteLink,
}: {
  contacts: Contact[];
  showInviteLink: boolean;
}) {
  const broadcast = contacts.find((c) => c.kind === "broadcast");
  const teammates = contacts.filter((c) => c.kind !== "broadcast");

  return (
    <div className="space-y-4">
      {broadcast ? (
        <p className="text-sm text-muted">
          Org broadcast:{" "}
          <span className="font-medium text-stone-800">{broadcast.handle}</span>
        </p>
      ) : null}
      {teammates.length === 0 ? (
        <p className="text-sm text-muted">
          You’re the only member so far.
          {showInviteLink ? (
            <>
              {" "}
              <a
                href="/admin/invites"
                className="text-stone-800 underline decoration-stone-300 underline-offset-2 hover:decoration-stone-600"
              >
                Invite teammates
              </a>
              .
            </>
          ) : null}
        </p>
      ) : (
        <ul>
          {teammates.map((c) => (
            <CopyHandle key={c.handle} contact={c} />
          ))}
        </ul>
      )}
      {showInviteLink && teammates.length > 0 ? (
        <a
          href="/admin/invites"
          className="inline-block text-sm text-stone-800 underline decoration-stone-300 underline-offset-2 hover:decoration-stone-600"
        >
          Manage invites
        </a>
      ) : null}
    </div>
  );
}
