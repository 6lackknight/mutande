"use client";

import { useEffect, useMemo, useState } from "react";
import { LayoutGroup, motion, useReducedMotion } from "motion/react";
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

export const variantName = "Inline letter";

type Props = { onState: (s: ComposeProtoState) => void };

/** A — Compose expands under the pills as a letter, not a labeled form card. */
export function VariantA({ onState }: Props) {
  const reduce = useReducedMotion();
  const [filter, setFilter] = useState<ThreadFilter>("all");
  const [open, setOpen] = useState(true);
  const [recipient, setRecipient] = useState("");
  const [query, setQuery] = useState("");
  const [note, setNote] = useState("");
  const [sending, setSending] = useState(false);
  const [sent, setSent] = useState(false);
  const [lastSent, setLastSent] = useState<ComposeProtoState["lastSent"]>(null);
  const [threads, setThreads] = useState<ProtoThread[]>(INITIAL_THREADS);

  const visible = filterThreads(threads, filter);
  const matches = matchAddresses(query);
  const canSend = recipient.length > 0 && note.trim().length > 0 && !sending;

  useEffect(() => {
    onState({
      variant: "A",
      filter,
      composeOpen: open,
      phase: open ? "letter" : "idle",
      recipient,
      note,
      sending,
      lastSent,
      threadCount: threads.length,
    });
  }, [filter, open, recipient, note, sending, lastSent, threads.length, onState]);

  const dur = reduce ? 0.01 : undefined;

  async function send() {
    if (!canSend) return;
    setSending(true);
    await new Promise((r) => setTimeout(r, 520));
    const next: ProtoThread = {
      id: `n-${Date.now()}`,
      title: note.trim().slice(0, 42) || "Untitled",
      from: "you",
      snippet: `→ ${recipient}`,
      status: "open",
      filed: null,
      time: "now",
    };
    setThreads((t) => [next, ...t]);
    setLastSent({ recipient, note: note.trim() });
    setSending(false);
    setSent(true);
    setTimeout(() => {
      setOpen(false);
      setSent(false);
      setRecipient("");
      setQuery("");
      setNote("");
    }, 380);
  }

  const needsYou = useMemo(
    () => threads.filter((t) => t.status === "needsYou").length,
    [threads],
  );

  return (
    <MacFrame>
      <div className="flex h-full min-h-0">
        <section className="flex w-[42%] min-w-[280px] flex-col border-r border-stone-200 bg-[#fafaf9]">
          <LayoutGroup>
            <div className="flex items-center gap-1 px-3 pt-3 pb-1">
              <div className="flex min-w-0 flex-1 gap-1 overflow-x-auto">
                {FILTERS.map((f) => {
                  const selected = filter === f.id;
                  return (
                    <button
                      key={f.id}
                      type="button"
                      onClick={() => setFilter(f.id)}
                      className="relative shrink-0 rounded-full px-2.5 py-1 text-[12px] font-medium tracking-tight"
                    >
                      {selected ? (
                        <motion.span
                          layoutId="a-pill"
                          className="absolute inset-0 rounded-full bg-[#292524]"
                          transition={{ duration: dur ?? 0.22, ease: EASE_EXPO }}
                        />
                      ) : null}
                      <span
                        className={`relative z-10 ${selected ? "text-stone-50" : "text-stone-600"}`}
                      >
                        {f.label}
                        {f.id === "needs_action" && needsYou > 0 ? (
                          <span className="ml-1 tabular-nums opacity-70">{needsYou}</span>
                        ) : null}
                      </span>
                    </button>
                  );
                })}
              </div>
              <motion.button
                type="button"
                aria-label={open ? "Close compose" : "Compose"}
                onClick={() => setOpen((v) => !v)}
                className="flex size-8 shrink-0 items-center justify-center rounded-full bg-[#292524] text-stone-50"
                whileTap={reduce ? undefined : { scale: 0.94 }}
                transition={{ duration: 0.12, ease: EASE_OUT }}
              >
                <motion.span
                  animate={{ rotate: open ? 45 : 0 }}
                  transition={{ duration: dur ?? 0.28, ease: EASE_EXPO }}
                  className="flex"
                >
                  <PlusGlyph className="size-[18px]" />
                </motion.span>
              </motion.button>
            </div>
          </LayoutGroup>

          <div
            className="grid px-3"
            style={{
              gridTemplateRows: open ? "1fr" : "0fr",
              transition: `grid-template-rows ${reduce ? "0.01ms" : "320ms"} cubic-bezier(0.25, 1, 0.5, 1)`,
            }}
          >
            <div className="overflow-hidden">
              <div
                className="mt-2 mb-1 rounded-[10px] bg-[#fafaf9] px-3 py-3 ring-1 ring-stone-200"
                style={{
                  opacity: open ? 1 : 0,
                  transform: open ? "translateY(0)" : "translateY(-8px)",
                  transition: `opacity ${reduce ? "0.01ms" : "280ms"} cubic-bezier(0.25, 1, 0.5, 1), transform ${reduce ? "0.01ms" : "280ms"} cubic-bezier(0.25, 1, 0.5, 1)`,
                }}
              >
                <div>
                  <div className="flex flex-wrap items-center gap-1.5 border-b border-stone-200 pb-2">
                    <span className="text-[11px] font-medium uppercase tracking-[0.12em] text-stone-400">
                      To
                    </span>
                    {recipient ? (
                      <motion.button
                        type="button"
                        layout
                        onClick={() => {
                          setRecipient("");
                          setQuery("");
                        }}
                        className="rounded-full bg-[#292524] px-2 py-0.5 text-[12px] font-medium text-stone-50"
                      >
                        {recipient}
                      </motion.button>
                    ) : (
                      <input
                        value={query}
                        onChange={(e) => {
                          setQuery(e.target.value);
                        }}
                        placeholder="@claude, @all…"
                        className="min-w-[8rem] flex-1 bg-transparent text-[13px] text-stone-800 outline-none placeholder:text-stone-400"
                      />
                    )}
                  </div>
                </div>
                {!recipient ? (
                    <ul className="mt-1.5 flex flex-col">
                      {matches.map((a) => (
                        <li key={a.id}>
                          <button
                            type="button"
                            onClick={() => {
                              setRecipient(a.label);
                              setQuery("");
                            }}
                            className="flex w-full items-baseline justify-between rounded-md px-1 py-1 text-left hover:bg-stone-100"
                          >
                            <span className="text-[13px] font-medium text-stone-800">
                              {a.label}
                            </span>
                            <span className="text-[11px] text-stone-400">{a.hint}</span>
                          </button>
                        </li>
                      ))}
                    </ul>
                  ) : null}
                <textarea
                  value={note}
                  onChange={(e) => setNote(e.target.value)}
                  placeholder="Short note for their agent"
                  rows={3}
                  className="mt-2 w-full resize-none bg-transparent text-[13.5px] leading-relaxed text-stone-800 outline-none placeholder:text-stone-400"
                />
                <div className="mt-2 flex items-center">
                  <button
                    type="button"
                    onClick={() => setOpen(false)}
                    className="text-[13px] font-medium text-[#92400e]"
                  >
                    Cancel
                  </button>
                  <div className="ml-auto">
                    <motion.button
                      type="button"
                      disabled={!canSend}
                      onClick={() => void send()}
                      className="rounded-full bg-[#292524] px-5 py-1.5 text-[13px] font-medium text-stone-50 disabled:opacity-35"
                      whileTap={reduce || !canSend ? undefined : { scale: 0.96 }}
                    >
                      {sending ? "Sending…" : sent ? "Sent" : "Send"}
                    </motion.button>
                  </div>
                </div>
              </div>
            </div>
          </div>

          <ul className="min-h-0 flex-1 overflow-auto px-1 pb-3">
            {visible.map((t, i) => (
              <motion.li
                key={t.id}
                initial={reduce ? false : { opacity: 0, y: 6 }}
                animate={{ opacity: 1, y: 0 }}
                transition={{ duration: dur ?? 0.28, delay: reduce ? 0 : Math.min(i, 6) * 0.04, ease: EASE_OUT }}
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
                <span className="shrink-0 text-[11px] tabular-nums text-stone-400">{t.time}</span>
              </motion.li>
            ))}
          </ul>
        </section>
        <aside className="flex flex-1 items-center justify-center bg-stone-100/40">
          <p className="text-[13px] text-stone-400">Select a thread</p>
        </aside>
      </div>
    </MacFrame>
  );
}
