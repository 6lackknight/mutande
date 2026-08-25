"use client";

import { useEffect, useState } from "react";
import { AnimatePresence, motion, useReducedMotion } from "motion/react";
import {
  FILTERS,
  INITIAL_THREADS,
  filterThreads,
  matchAddresses,
  type ProtoThread,
  type ThreadFilter,
} from "./data";
import { MacFrame, PlusGlyph } from "./frame";
import { EASE_EXPO, EASE_OUT, type ComposeProtoState } from "./types";

export const variantName = "Reading-pane letter";

type Props = { onState: (s: ComposeProtoState) => void };

/** C — Compose occupies the reading pane. List stays; the letter is the mail. */
export function VariantC({ onState }: Props) {
  const reduce = useReducedMotion();
  const [filter, setFilter] = useState<ThreadFilter>("all");
  const [open, setOpen] = useState(true);
  const [selected, setSelected] = useState<string | null>(null);
  const [recipient, setRecipient] = useState("@claude");
  const [query, setQuery] = useState("");
  const [note, setNote] = useState("");
  const [sending, setSending] = useState(false);
  const [lastSent, setLastSent] = useState<ComposeProtoState["lastSent"]>(null);
  const [threads, setThreads] = useState<ProtoThread[]>(INITIAL_THREADS);
  const [suggest, setSuggest] = useState(false);

  const visible = filterThreads(threads, filter);
  const reading = threads.find((t) => t.id === selected);
  const matches = matchAddresses(query);
  const canSend = recipient.length > 0 && note.trim().length > 0 && !sending;
  const dur = reduce ? 0.01 : undefined;

  useEffect(() => {
    onState({
      variant: "C",
      filter,
      composeOpen: open,
      phase: open ? "write" : selected ? "read" : "idle",
      recipient,
      note,
      sending,
      lastSent,
      threadCount: threads.length,
    });
  }, [filter, open, selected, recipient, note, sending, lastSent, threads.length, onState]);

  async function send() {
    if (!canSend) return;
    setSending(true);
    await new Promise((r) => setTimeout(r, 520));
    const id = `n-${Date.now()}`;
    const next: ProtoThread = {
      id,
      title: note.trim().slice(0, 42),
      from: "you",
      snippet: `→ ${recipient}`,
      status: "open",
      filed: null,
      time: "now",
    };
    setThreads((t) => [next, ...t]);
    setLastSent({ recipient, note: note.trim() });
    setSending(false);
    setOpen(false);
    setSelected(id);
    setNote("");
  }

  return (
    <MacFrame>
      <div className="flex h-full min-h-0">
        <section className="flex w-[36%] min-w-[240px] flex-col border-r border-stone-200 bg-[#fafaf9]">
          <div className="flex items-center gap-1 px-3 pt-3 pb-2">
            <div className="flex min-w-0 flex-1 gap-1 overflow-x-auto">
              {FILTERS.map((f) => {
                const selectedF = filter === f.id;
                return (
                  <button
                    key={f.id}
                    type="button"
                    onClick={() => setFilter(f.id)}
                    className={`shrink-0 rounded-full px-2.5 py-1 text-[12px] font-medium ${
                      selectedF
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
              onClick={() => {
                setOpen(true);
                setSelected(null);
              }}
              className={`flex size-8 shrink-0 items-center justify-center rounded-full ${
                open ? "bg-[#292524] text-stone-50" : "bg-stone-100 text-stone-700"
              }`}
              whileTap={reduce ? undefined : { scale: 0.94 }}
            >
              <PlusGlyph className="size-[18px]" />
            </motion.button>
          </div>
          <ul className="min-h-0 flex-1 overflow-auto px-1 pb-3">
            {visible.map((t) => {
              const on = selected === t.id && !open;
              return (
                <li key={t.id}>
                  <button
                    type="button"
                    onClick={() => {
                      setSelected(t.id);
                      setOpen(false);
                    }}
                    className={`flex w-full items-start gap-2.5 rounded-lg px-3 py-2.5 text-left ${
                      on ? "bg-stone-200/70" : "hover:bg-stone-100"
                    }`}
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
                    <span className="text-[11px] tabular-nums text-stone-400">
                      {t.time}
                    </span>
                  </button>
                </li>
              );
            })}
          </ul>
        </section>

        <aside className="relative flex min-w-0 flex-1 flex-col overflow-hidden bg-stone-100/50">
          <AnimatePresence mode="wait">
            {open ? (
              <motion.div
                key="compose"
                initial={reduce ? { opacity: 0 } : { opacity: 0, x: 18 }}
                animate={{ opacity: 1, x: 0 }}
                exit={reduce ? { opacity: 0 } : { opacity: 0, x: 12 }}
                transition={{ duration: dur ?? 0.34, ease: EASE_EXPO }}
                className="flex h-full min-h-0 flex-col px-8 py-7"
              >
                <div className="flex items-baseline justify-between">
                  <p className="text-[11px] font-semibold uppercase tracking-[0.14em] text-stone-400">
                    New thread
                  </p>
                  <div className="flex items-center gap-3">
                    <button
                      type="button"
                      onClick={() => setOpen(false)}
                      className="text-[13px] font-medium text-[#92400e]"
                    >
                      Cancel
                    </button>
                    <motion.button
                      type="button"
                      disabled={!canSend}
                      onClick={() => void send()}
                      className="rounded-full bg-[#292524] px-4 py-1.5 text-[13px] font-medium text-stone-50 disabled:opacity-35"
                      whileTap={reduce || !canSend ? undefined : { scale: 0.96 }}
                    >
                      {sending ? "Sending…" : "Forward"}
                    </motion.button>
                  </div>
                </div>
                <div className="mt-8 flex items-center gap-3 border-b border-stone-300/80 pb-3">
                  <span className="text-[13px] text-stone-400">To</span>
                  {recipient && !suggest ? (
                    <button
                      type="button"
                      onClick={() => {
                        setSuggest(true);
                        setQuery(recipient);
                      }}
                      className="text-[22px] font-semibold tracking-[-0.04em] text-stone-900"
                    >
                      {recipient}
                    </button>
                  ) : (
                    <input
                      autoFocus
                      value={query}
                      onChange={(e) => {
                        setQuery(e.target.value);
                        setSuggest(true);
                        setRecipient("");
                      }}
                      placeholder="an address"
                      className="flex-1 bg-transparent text-[22px] font-semibold tracking-[-0.04em] text-stone-900 outline-none placeholder:font-normal placeholder:text-stone-300"
                    />
                  )}
                </div>
                <AnimatePresence>
                  {suggest ? (
                    <motion.ul
                      initial={reduce ? { opacity: 0 } : { opacity: 0, y: -6 }}
                      animate={{ opacity: 1, y: 0 }}
                      exit={{ opacity: 0 }}
                      transition={{ duration: dur ?? 0.2, ease: EASE_OUT }}
                      className="mt-2"
                    >
                      {matches.map((a) => (
                        <li key={a.id}>
                          <button
                            type="button"
                            onClick={() => {
                              setRecipient(a.label);
                              setQuery("");
                              setSuggest(false);
                            }}
                            className="flex w-full items-baseline justify-between py-1.5 text-left"
                          >
                            <span className="text-[14px] text-stone-800">{a.label}</span>
                            <span className="text-[12px] text-stone-400">{a.hint}</span>
                          </button>
                        </li>
                      ))}
                    </motion.ul>
                  ) : null}
                </AnimatePresence>
                <textarea
                  value={note}
                  onChange={(e) => setNote(e.target.value)}
                  placeholder="Write the note. Their agent reads this."
                  className="mt-6 min-h-0 flex-1 resize-none bg-transparent text-[16px] leading-[1.55] text-stone-800 outline-none placeholder:text-stone-400"
                />
              </motion.div>
            ) : reading ? (
              <motion.div
                key={reading.id}
                initial={reduce ? { opacity: 0 } : { opacity: 0, x: 12 }}
                animate={{ opacity: 1, x: 0 }}
                exit={reduce ? { opacity: 0 } : { opacity: 0, x: -8 }}
                transition={{ duration: dur ?? 0.28, ease: EASE_OUT }}
                className="flex h-full flex-col px-8 py-7"
              >
                <p className="text-[11px] font-semibold uppercase tracking-[0.14em] text-stone-400">
                  Thread
                </p>
                <h2 className="mt-2 text-[22px] font-semibold tracking-[-0.04em] text-stone-900">
                  {reading.title}
                </h2>
                <p className="mt-1 text-[13px] text-stone-500">{reading.from}</p>
                <p className="mt-8 max-w-md text-[15px] leading-relaxed text-stone-700">
                  {reading.snippet}
                </p>
              </motion.div>
            ) : (
              <motion.div
                key="empty"
                initial={{ opacity: 0 }}
                animate={{ opacity: 1 }}
                exit={{ opacity: 0 }}
                className="flex h-full items-center justify-center"
              >
                <p className="text-[13px] text-stone-400">
                  Select a thread — or compose to the right
                </p>
              </motion.div>
            )}
          </AnimatePresence>
        </aside>
      </div>
    </MacFrame>
  );
}
