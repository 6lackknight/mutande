"use client";

import { useActionState, useMemo, useState } from "react";
import { createOrgAction, type ActionState } from "@/app/actions";
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

export function CreateOrgForm({
  emailLocal,
  initialSlug = "",
}: {
  emailLocal: string;
  initialSlug?: string;
}) {
  const [state, action, pending] = useActionState(createOrgAction, initial);
  const [slug, setSlug] = useState(initialSlug);
  const [handleTouched, setHandleTouched] = useState(false);
  const [handle, setHandle] = useState(
    initialSlug ? `${emailLocal}@${initialSlug}` : `${emailLocal}@`,
  );

  const suggested = useMemo(() => {
    const s = slugify(slug);
    return s ? `${emailLocal}@${s}` : `${emailLocal}@`;
  }, [emailLocal, slug]);

  return (
    <form action={action} className="space-y-5">
      {state.error ? <Alert tone="danger">{state.error}</Alert> : null}

      <Field label="Org slug" hint="Lowercase letters, numbers, hyphens.">
        <Input
          name="slug"
          required
          autoComplete="off"
          placeholder="acme"
          value={slug}
          onChange={(e) => {
            const next = slugify(e.target.value);
            setSlug(next);
            if (!handleTouched) setHandle(`${emailLocal}@${next}`);
          }}
        />
      </Field>

      <Field label="Team name">
        <Input
          name="name"
          placeholder="Acme"
          defaultValue=""
          autoComplete="organization"
        />
      </Field>

      <Field
        label="Your handle"
        hint="Defaults to email-local@org. Editable before you create."
      >
        <Input
          name="handle"
          required
          value={handle}
          placeholder={suggested}
          onChange={(e) => {
            setHandleTouched(true);
            setHandle(e.target.value);
          }}
        />
      </Field>

      <Button type="submit" className="w-full" disabled={pending}>
        {pending ? "Creating…" : "Create team"}
      </Button>
    </form>
  );
}
