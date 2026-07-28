"use client";

import { useActionState } from "react";
import { joinOrgAction, type ActionState } from "@/app/actions";
import { Alert, Button, Field, Input } from "@/components/ui";

const initial: ActionState = {};

export function JoinForm({
  initialInvite,
  initialHandle,
}: {
  initialInvite: string;
  initialHandle: string;
}) {
  const [state, action, pending] = useActionState(joinOrgAction, initial);

  return (
    <form action={action} className="space-y-5">
      {state.error ? <Alert tone="danger">{state.error}</Alert> : null}

      <Field label="Invite code">
        <Input
          name="invite_code"
          required
          defaultValue={initialInvite}
          placeholder="paste code"
          autoComplete="off"
        />
      </Field>

      <Field
        label="Your handle"
        hint="Usually local@org — match the org slug your admin shared."
      >
        <Input
          name="handle"
          required
          defaultValue={initialHandle}
          placeholder="alice@acme"
        />
      </Field>

      <Button type="submit" className="w-full" disabled={pending}>
        {pending ? "Joining…" : "Join team"}
      </Button>
    </form>
  );
}
