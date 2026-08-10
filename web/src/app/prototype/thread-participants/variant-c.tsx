import {
  THREAD_PARTICIPANTS,
  THREAD_SNIPPET,
  THREAD_TITLE,
} from "./participants";

export const variantName = "Popover over thread";

/** C — Compact macOS sheet over a blurred inbox; participants as dense chips. */
export function VariantC() {
  return (
    <div className="relative flex h-full w-full items-center justify-center overflow-hidden rounded-2xl bg-stone-200">
      {/* Fake inbox backdrop */}
      <div
        aria-hidden
        className="absolute inset-0 scale-105 px-6 py-8 blur-[3px] saturate-75"
      >
        <div className="mx-auto max-w-lg space-y-3 opacity-70">
          {[THREAD_TITLE, "Ping @all", "Blob handoff", "Safety numbers"].map(
            (t) => (
              <div
                key={t}
                className="rounded-xl border border-stone-300/80 bg-stone-50 px-4 py-3"
              >
                <p className="text-sm font-medium text-stone-700">{t}</p>
                <p className="mt-1 truncate text-xs text-stone-400">
                  {THREAD_SNIPPET}
                </p>
              </div>
            ),
          )}
        </div>
      </div>

      <div className="relative z-10 w-[min(100%,22rem)] rounded-2xl border border-stone-200 bg-stone-50/95 p-4 shadow-2xl shadow-stone-900/20 backdrop-blur-md">
        <div className="mb-3 flex items-center justify-between px-1">
          <p className="text-[13px] font-semibold text-stone-800">
            On this thread
          </p>
          <span className="rounded-full bg-amber-100 px-2 py-0.5 text-[11px] font-medium text-amber-900">
            {THREAD_PARTICIPANTS.length}
          </span>
        </div>
        <ul className="flex flex-col gap-1.5">
          {THREAD_PARTICIPANTS.map((p) => (
            <li
              key={p.address}
              className="flex items-center gap-2.5 rounded-xl bg-white px-3 py-2.5 ring-1 ring-stone-200/80"
            >
              <span className="size-2 shrink-0 rounded-full bg-stone-800" />
              <div className="min-w-0 flex-1">
                <p className="truncate font-mono text-[12.5px] font-medium text-stone-900">
                  {p.address}
                </p>
              </div>
              <span className="shrink-0 rounded-md bg-stone-100 px-1.5 py-0.5 text-[10px] font-medium uppercase tracking-wide text-stone-500">
                {p.hostHint}
              </span>
            </li>
          ))}
        </ul>
      </div>
    </div>
  );
}
