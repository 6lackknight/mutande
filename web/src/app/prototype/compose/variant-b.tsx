"use client";

import { useEffect, useState } from "react";
import { AnimatePresence, motion, useReducedMotion } from "motion/react";
import {
  ADDRESSES,
  FILTERS,
  INITIAL_THREADS,
  filterThreads,
  matchAddresses,
  type ProtoThread,
  type ThreadFilter,
} from "./data";
import { MacFrame, PlusGlyph } from "./frame";
import { EASE_EXPO, EASE_OUT, type ComposeProtoState } from "./types";

export const variantName = "Spotlight dispatch";

type Props = { onState: (s: ComposeProtoState) => void };

/** B — Address-first command strip over a dimmed list. Note reveals after a pick. */
export function VariantB({ onState }: Props) {
  const reduce = useReducedMotion();
  const [filter, setFilter] = useState<ThreadFilter>("all");
  const [open, setOpen] = useState(true);
  const [phase, setPhase] = useState<"pick" | "write">("pick");
  const [recipient, setRecipient] = useState("");
  const [query, setQuery] = useState("");
  const [note, setNote] = useState("");
  const [sending, setSending] = useState(false);
  const [lastSent, setLastSent] = useState<ComposeProtoState["lastSent"]>(null);
  const [threads, setThreads] = useState<ProtoThread[]>(INITIAL_THREADS);

  const visible = filterThreads(threads, filter);
  const matches = query.trim() ? matchAddresses(query) : ADDRESSES;
  const canSend = recipient.length > 0 && note.trim().length > 0 && !sending;
  const dur = reduce ? 0.01 : undefined;

  useEffect(() => {
    onState({
      variant: "B",
      filter,
      composeOpen: open,
      phase: open ? phase : "idle",
      recipient,
      note,
      sending,
      lastSent,
      threadCount: threads.length,
    });
  }, [filter, open, phase, recipient, note, sending, lastSent, threads.length, onState]);

  function openCompose() {
    setOpen(true);
    setPhase("pick");
    setRecipient("");
    setQuery("");
    setNote("");
  }

  function pick(label: string) {
    setRecipient(label);
    setQuery("");
    setPhase("write");
  }

  async function send() {
    if (!canSend) return;
    setSending(true);
    await new Promise((r) => setTimeout(r, 520));
    setThreads((t) => [
      {
        id: `n-${Date.now()}`,
        title: note.trim().slice(0, 42),
        from: "you",
        snippet: `→ ${recipient}`,
        status: "open",
        filed: null,
        time: "now",
      },
      ...t,
    ]);
    setLastSent({ recipient, note: note.trim() });
    setSending(false);
    setOpen(false);
    setPhase("pick");
    setRecipient("");
    setNote("");
  }

  return (
    <MacFrame>
      <div className="relative flex h-full min-h-0 flex-col">
        <div className="flex items-center gap-1 px-3 pt-3 pb-2">
          <div className="flex min-w-0 flex-1 gap-1 overflow-x-auto">
            {FILTERS.map((f) => {
              const selected = filter === f.id;
              return (
                <button
                  key={f.id}
                  type="button"
                  onClick={() => setFilter(f.id)}
                  className={`shrink-0 rounded-full px-2.5 py-1 text-[12px] font-medium ${
                    selected
                      ? "bg-[#292524] text-stone-50"
                      : "bg-stone-100 text-stone-600"
                  }`}
                >
                  {f.label}
                </button>
              );
            })}
          </div>
          <motion.button
            type="button"
            aria-label="Compose"
            onClick={openCompose}
            className="flex size-8 shrink-0 items-center justify-center rounded-full bg-[#292524] text-stone-50"
            whileTap={reduce ? undefined : { scale: 0.94 }}
          >
            <PlusGlyph className="size-[18px]" />
          </motion.button>
        </div>

        <ul className="min-h-0 flex-1 overflow-auto px-2 pb-4">
          {visible.map((t) => (
            <li
              key={t.id}
              className="flex items-start gap-2.5 rounded-lg px-3 py-2.5"
            >
              {t.status === "needsYou" ? (
                <span className="mt-1.5 size-1.5 shrink-0 rounded-full bg-amber-700" />
              ) : (
                <span className="mt-1.5 size-1.5 shrink-0" />
              )}
              <div className="min-w-0 flex-1">
                <p className="truncate text-[13.5px] font-medium tracking-tight text-stone-800">
                  {t.title}
                </p>
                <p className="truncate text-[12px] text-stone-500">
                  {t.from} · {t.snippet}
                </p>
              </div>
              <span className="text-[11px] tabular-nums text-stone-400">{t.time}</span>
            </li>
          ))}
        </ul>

        <AnimatePresence>
          {open ? (
            <motion.div
              className="absolute inset-0 z-10 flex items-start justify-center px-8 pt-16"
              initial={{ opacity: 0 }}
              animate={{ opacity: 1 }}
              exit={{ opacity: 0 }}
              transition={{ duration: dur ?? 0.22, ease: EASE_OUT }}
            >
              <button
                type="button"
                aria-label="Dismiss"
                className="absolute inset-0 bg-stone-800/25"
                onClick={() => setOpen(false)}
              />
              <motion.div
                role="dialog"
                aria-label="Dispatch"
                initial={reduce ? { opacity: 0 } : { opacity: 0, y: 16, scale: 0.96 }}
                animate={{ opacity: 1, y: 0, scale: 1 }}
                exit={reduce ? { opacity: 0 } : { opacity: 0, y: 10, scale: 0.98 }}
                transition={{ duration: dur ?? 0.38, ease: EASE_EXPO }}
                className="relative z-10 w-full max-w-lg rounded-2xl bg-[#fafaf9] p-4 shadow-[0_32px_64px_-28px_rgba(41,37,36,0.5)] ring-1 ring-stone-200"
              >
                <p className="px-1 text-[11px] font-semibold uppercase tracking-[0.14em] text-stone-400">
                  Dispatch
                </p>
                {phase === "pick" ? (
                  <div className="mt-3">
                    <input
                      autoFocus
                      value={query}
                      onChange={(e) => setQuery(e.target.value)}
                      placeholder="Who should get this?"
                      className="w-full border-b border-stone-200 bg-transparent pb-2 text-[18px] font-medium tracking-tight text-stone-900 outline-none placeholder:font-normal placeholder:text-stone-400"
                    />
                    <ul className="mt-3 flex flex-col gap-0.5">
                      {matches.map((a, i) => (
                        <motion.li
                          key={a.id}
                          initial={reduce ? false : { opacity: 0, x: -6 }}
                          animate={{ opacity: 1, x: 0 }}
                          transition={{
                            duration: dur ?? 0.22,
                            delay: reduce ? 0 : i * 0.04,
                            ease: EASE_OUT,
                          }}
                        >
                          <button
                            type="button"
                            onClick={() => pick(a.label)}
                            className="flex w-full items-center gap-3 rounded-lg px-2 py-2 text-left hover:bg-stone-100"
                          >
                            <span className="size-1.5 rounded-full bg-[#292524]" />
                            <span className="text-[15px] font-medium tracking-tight text-stone-800">
                              {a.label}
                            </span>
                            <span className="ml-auto text-[12px] text-stone-400">
                              {a.hint}
                            </span>
                          </button>
                        </motion.li>
                      ))}
                    </ul>
                  </div>
                ) : (
                  <div className="mt-3">
                    <div className="flex items-center gap-2">
                      <span className="text-[11px] font-medium uppercase tracking-[0.12em] text-stone-400">
                        To
                      </span>
                      <button
                        type="button"
                        onClick={() => {
                          setPhase("pick");
                          setRecipient("");
                        }}
                        className="rounded-full bg-[#292524] px-2.5 py-0.5 text-[13px] font-medium text-stone-50"
                      >
                        {recipient}
                      </button>
                    </div>
                    <textarea
                      autoFocus
                      value={note}
                      onChange={(e) => setNote(e.target.value)}
                      placeholder="The note they should act on"
                      rows={4}
                      className="mt-3 w-full resize-none bg-transparent text-[15px] leading-relaxed text-stone-800 outline-none placeholder:text-stone-400"
                    />
                    <div className="mt-2 flex items-center justify-end">
                      <motion.button
                        type="button"
                        disabled={!canSend}
                        onClick={() => void send()}
                        className="flex size-9 items-center justify-center rounded-full bg-[#292524] text-stone-50 disabled:opacity-35"
                        whileTap={reduce || !canSend ? undefined : { scale: 0.94 }}
                        animate={sending && !reduce ? { scale: [1, 0.96, 1] } : { scale: 1 }}
                        transition={{ duration: 0.4, ease: EASE_OUT }}
                        aria-label="Send"
                      >
                        ↑
                      </motion.button>
                    </div>
                  </div>
                )}
              </motion.div>
            </motion.div>
          ) : null}
        </AnimatePresence>
      </div>
    </MacFrame>
  );
}
