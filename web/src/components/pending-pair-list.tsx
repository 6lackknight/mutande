"use client";

import { useActionState, useEffect } from "react";
import { useRouter } from "next/navigation";
import {
  approvePairRequestAction,
  denyPairRequestAction,
  type ActionState,
} from "@/app/actions";
import { Alert, Button } from "@/components/ui";
import type { PairRequest } from "@/lib/types";

const initial: ActionState = {};

function IncomingRow({ request }: { request: PairRequest }) {
  const router = useRouter();
  const [approveState, approveAction, approvePending] = useActionState(
    approvePairRequestAction,
    initial,
  );
  const [denyState, denyAction, denyPending] = useActionState(
    denyPairRequestAction,
    initial,
  );
  const pending = approvePending || denyPending;
  const error = approveState.error ?? denyState.error;
  const ok = approveState.ok ?? denyState.ok;

  useEffect(() => {
    if (ok) router.refresh();
  }, [ok, router]);

  return (
    <li className="space-y-2 border-b border-stone-200/80 py-4 last:border-0">
      {error ? <Alert tone="danger">{error}</Alert> : null}
      {ok && !pending ? <Alert tone="ok">{ok}</Alert> : null}
      <div className="flex flex-wrap items-start justify-between gap-3">
        <div>
          <div className="font-medium text-stone-900">
            {request.requester_handle}
          </div>
          {request.intro ? (
            <p className="mt-1 text-sm text-muted">{request.intro}</p>
          ) : null}
        </div>
        <div className="flex gap-2">
          <form action={approveAction}>
            <input type="hidden" name="request_id" value={request.id} />
            <Button type="submit" disabled={pending}>
              {approvePending ? "…" : "Approve"}
            </Button>
          </form>
          <form action={denyAction}>
            <input type="hidden" name="request_id" value={request.id} />
            <Button type="submit" variant="ghost" disabled={pending}>
              Deny
            </Button>
          </form>
        </div>
      </div>
    </li>
  );
}

export function PendingPairList({
  incoming,
  outgoing,
}: {
  incoming: PairRequest[];
  outgoing: PairRequest[];
}) {
  if (incoming.length === 0 && outgoing.length === 0) {
    return (
      <p className="text-sm text-muted">No pending pairing requests.</p>
    );
  }

  return (
    <div className="space-y-8">
      {incoming.length > 0 ? (
        <div>
          <h3 className="mb-2 text-[13px] font-medium uppercase tracking-[0.12em] text-muted">
            Incoming
          </h3>
          <ul>
            {incoming.map((r) => (
              <IncomingRow key={r.id} request={r} />
            ))}
          </ul>
        </div>
      ) : null}
      {outgoing.length > 0 ? (
        <div>
          <h3 className="mb-2 text-[13px] font-medium uppercase tracking-[0.12em] text-muted">
            Outgoing
          </h3>
          <ul>
            {outgoing.map((r) => (
              <li
                key={r.id}
                className="border-b border-stone-200/80 py-3 text-[15px] last:border-0"
              >
                <span className="font-medium text-stone-900">
                  {r.target_handle}
                </span>
                <span className="ml-2 text-sm text-muted">Waiting</span>
              </li>
            ))}
          </ul>
        </div>
      ) : null}
    </div>
  );
}
