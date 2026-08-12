"use client";

import { useActionState, useEffect, useState } from "react";
import { useRouter } from "next/navigation";
import { updateOrgSlugAction, type ActionState } from "@/app/actions";
import { Alert, Button, Field, Input } from "@/components/ui";

const initial: ActionState = {};

function slugify(raw: string): string {
  return raw
    .toLowerCase()
    .trim()
    .replace(/[^a-z0-9-]+/g, "-")
    .replace(/^-+|-+$/g, "")
    .slice(0, 48);
}

export function OrgSlugForm({ initialSlug }: { initialSlug: string }) {
  const router = useRouter();
  const [state, action, pending] = useActionState(updateOrgSlugAction, initial);
  const [slug, setSlug] = useState(initialSlug);

  useEffect(() => {
    setSlug(initialSlug);
  }, [initialSlug]);

  useEffect(() => {
    if (state.ok) router.refresh();
  }, [state.ok, router]);

  return (
    <form action={action} className="space-y-4">
      {state.error ? <Alert tone="danger">{state.error}</Alert> : null}
      {state.ok && !pending ? <Alert tone="ok">{state.ok}</Alert> : null}

      <Field
        label="Organization handle"
        hint="Everyone’s address becomes local@this-slug. Old threads keep the previous address."
      >
        <Input
          name="slug"
          required
          autoComplete="off"
          spellCheck={false}
          value={slug}
          onChange={(e) => setSlug(slugify(e.target.value))}
          pattern="[a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?"
          title="Lowercase letters, numbers, hyphens"
          maxLength={63}
        />
      </Field>

      <Button type="submit" disabled={pending || slug === initialSlug || slug.length < 2}>
        {pending ? "Saving…" : "Update handle"}
      </Button>
    </form>
  );
}
