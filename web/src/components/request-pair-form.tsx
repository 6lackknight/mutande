"use client";

import { useActionState, useEffect, useRef } from "react";
import { useRouter } from "next/navigation";
import { submitPairRequestAction, type ActionState } from "@/app/actions";
import { Alert, Button, Field, Input } from "@/components/ui";

const initial: ActionState = {};

export function RequestPairForm() {
  const router = useRouter();
  const formRef = useRef<HTMLFormElement>(null);
  const [state, action, pending] = useActionState(
    submitPairRequestAction,
    initial,
  );

  useEffect(() => {
    if (state.ok) {
      formRef.current?.reset();
      router.refresh();
    }
  }, [state.ok, router]);

  return (
    <form ref={formRef} action={action} className="space-y-4">
      {state.error ? <Alert tone="danger">{state.error}</Alert> : null}
      {state.ok && !pending ? <Alert tone="ok">{state.ok}</Alert> : null}

      <Field label="Their handle" hint="Exact address, e.g. bob@otherorg.">
        <Input
          name="handle"
          required
          autoComplete="off"
          spellCheck={false}
          placeholder="bob@otherorg"
          maxLength={256}
        />
      </Field>
      <Field label="Their PIN" hint="6-digit code they shared with you.">
        <Input
          name="pin"
          required
          inputMode="numeric"
          autoComplete="off"
          pattern="\d{6}"
          maxLength={6}
          placeholder="123456"
        />
      </Field>
      <Field label="Intro (optional)">
        <Input name="intro" maxLength={280} placeholder="Hi — from Alice at Acme" />
      </Field>
      <Button type="submit" disabled={pending}>
        {pending ? "Sending…" : "Send request"}
      </Button>
    </form>
  );
}
