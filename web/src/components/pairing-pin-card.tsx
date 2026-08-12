"use client";

import { useActionState, useEffect, useState } from "react";
import { useRouter } from "next/navigation";
import {
  issuePairingPinAction,
  rotatePairingPinAction,
  type ActionState,
} from "@/app/actions";
import { Alert, Button } from "@/components/ui";
import type { PairingPinResponse } from "@/lib/types";

const initial: ActionState = {};

function formatExpiry(iso: string): string {
  try {
    return new Date(iso).toLocaleString(undefined, {
      dateStyle: "medium",
      timeStyle: "short",
    });
  } catch {
    return iso;
  }
}

export function PairingPinCard({
  initialPin,
}: {
  initialPin: PairingPinResponse | null;
}) {
  const router = useRouter();
  const [issueState, issueAction, issuePending] = useActionState(
    issuePairingPinAction,
    initial,
  );
  const [rotateState, rotateAction, rotatePending] = useActionState(
    rotatePairingPinAction,
    initial,
  );
  const [copied, setCopied] = useState(false);
  const pending = issuePending || rotatePending;
  const error = issueState.error ?? rotateState.error;
  const ok = issueState.ok ?? rotateState.ok;

  useEffect(() => {
    if (ok) router.refresh();
  }, [ok, router]);

  async function copyPin() {
    if (!initialPin?.pin) return;
    try {
      await navigator.clipboard.writeText(initialPin.pin);
      setCopied(true);
      setTimeout(() => setCopied(false), 2000);
    } catch {
      /* ignore */
    }
  }

  return (
    <div className="space-y-4">
      {error ? <Alert tone="danger">{error}</Alert> : null}
      {ok && !pending ? <Alert tone="ok">{ok}</Alert> : null}

      <p className="text-sm text-muted">
        Share this PIN with someone outside your org so they can request a
        connection. Cross-org mail uses app envelope — not end-to-end.
      </p>

      {initialPin ? (
        <div className="space-y-3">
          <div className="font-display text-3xl tracking-[0.2em] text-stone-900">
            {initialPin.pin}
          </div>
          <p className="text-xs text-muted">
            Expires {formatExpiry(initialPin.expires_at)}
          </p>
          <div className="flex flex-wrap gap-2">
            <Button type="button" variant="secondary" onClick={copyPin}>
              {copied ? "Copied" : "Copy PIN"}
            </Button>
            <form action={rotateAction}>
              <Button type="submit" variant="ghost" disabled={pending}>
                {rotatePending ? "Rotating…" : "Rotate"}
              </Button>
            </form>
          </div>
        </div>
      ) : (
        <form action={issueAction}>
          <Button type="submit" disabled={pending}>
            {issuePending ? "Creating…" : "Create pairing PIN"}
          </Button>
        </form>
      )}
    </div>
  );
}
