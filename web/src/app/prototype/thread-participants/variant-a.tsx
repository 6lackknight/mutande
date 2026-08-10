import {
  THREAD_PARTICIPANTS,
  THREAD_SNIPPET,
  THREAD_TITLE,
} from "./participants";

export const variantName = "Mail split — participants rail";

/** A — Cursor-like list + reading pane; participants as a left rail. */
export function VariantA() {
  return (
    <div className="flex h-full min-h-0 w-full overflow-hidden rounded-2xl border border-stone-200 bg-stone-100 shadow-sm">
      <aside className="flex w-[38%] min-w-[240px] flex-col border-r border-stone-200 bg-stone-50">
        <div className="border-b border-stone-200 px-4 py-3">
          <p className="text-[11px] font-semibold uppercase tracking-[0.14em] text-stone-400">
            Participants
          </p>
          <p className="mt-0.5 text-sm text-stone-500">
            {THREAD_PARTICIPANTS.length} on this thread
          </p>
        </div>
        <ul className="flex-1 overflow-auto py-1">
          {THREAD_PARTICIPANTS.map((p) => (
            <li
              key={p.address}
              className="flex items-center gap-3 px-4 py-3 transition hover:bg-stone-100"
            >
              <span
                className="flex size-9 shrink-0 items-center justify-center rounded-lg text-[11px] font-semibold text-stone-50"
                style={{
                  background:
                    p.kind === "self-short" ? "#292524" : "#92400e",
                }}
              >
                {p.hostHint.slice(0, 2).toUpperCase()}
              </span>
              <div className="min-w-0">
                <p className="truncate font-mono text-[13px] font-medium text-stone-800">
                  {p.address}
                </p>
                <p className="truncate text-xs text-stone-400">{p.hostHint}</p>
              </div>
            </li>
          ))}
        </ul>
      </aside>
      <section className="flex min-w-0 flex-1 flex-col bg-[#fafaf9]">
        <header className="border-b border-stone-200 px-6 py-4">
          <p className="text-[11px] font-semibold uppercase tracking-[0.14em] text-stone-400">
            Thread
          </p>
          <h2 className="mt-1 text-lg font-semibold tracking-tight text-stone-900">
            {THREAD_TITLE}
          </h2>
        </header>
        <div className="flex flex-1 flex-col justify-center px-8 py-10">
          <p className="max-w-md text-[15px] leading-relaxed text-stone-600">
            {THREAD_SNIPPET}
          </p>
          <p className="mt-6 text-xs text-stone-400">
            OP · nested replies would land here
          </p>
        </div>
      </section>
    </div>
  );
}
