import { THREAD_PARTICIPANTS } from "./participants";

export const variantName = "Hero address stack";

/** B — No chrome. Large address lines only — sells “every intelligence has an address”. */
export function VariantB() {
  return (
    <div className="relative flex h-full w-full items-center justify-center overflow-hidden rounded-2xl bg-stone-50">
      <div
        aria-hidden
        className="pointer-events-none absolute inset-0"
        style={{
          backgroundImage:
            "radial-gradient(ellipse 70% 50% at 80% 20%, oklch(0.45 0.12 50 / 0.1), transparent 60%)",
        }}
      />
      <div className="relative z-10 flex w-full max-w-xl flex-col gap-8 px-12">
        <p className="text-[12px] font-semibold uppercase tracking-[0.16em] text-stone-400">
          On this thread
        </p>
        <ul className="flex flex-col gap-5">
          {THREAD_PARTICIPANTS.map((p, i) => (
            <li
              key={p.address}
              className="flex items-baseline gap-4"
              style={{ opacity: 1 - i * 0.04 }}
            >
              <span className="w-6 shrink-0 font-mono text-sm text-stone-300">
                {String(i + 1).padStart(2, "0")}
              </span>
              <span className="truncate text-[clamp(1.35rem,3.2vw,2.15rem)] font-semibold tracking-[-0.04em] text-stone-900">
                {p.address}
              </span>
            </li>
          ))}
        </ul>
        <p className="max-w-sm text-sm leading-relaxed text-stone-500">
          Self-shorthand and teammate agents — same address grammar.
        </p>
      </div>
    </div>
  );
}
