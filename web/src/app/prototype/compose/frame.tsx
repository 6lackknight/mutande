/** PROTOTYPE — Mac window chrome only. Interiors stay per-variant. */

export function MacFrame({ children }: { children: React.ReactNode }) {
  return (
    <div className="flex h-full min-h-0 w-full flex-col overflow-hidden rounded-2xl border border-stone-300/80 bg-stone-200 shadow-[0_28px_60px_-32px_rgba(41,37,36,0.55)]">
      <div className="flex h-10 shrink-0 items-center gap-2 border-b border-stone-300/70 bg-stone-100/90 px-3">
        <span className="size-2.5 rounded-full bg-[#d6d3d1]" />
        <span className="size-2.5 rounded-full bg-[#d6d3d1]" />
        <span className="size-2.5 rounded-full bg-[#d6d3d1]" />
        <p className="ml-2 text-[12px] font-medium tracking-tight text-stone-500">
          mutande
        </p>
      </div>
      <div className="min-h-0 flex-1 bg-[#f5f5f4]">{children}</div>
    </div>
  );
}

export function PlusGlyph({ className }: { className?: string }) {
  return (
    <svg viewBox="0 0 24 24" fill="none" className={className} aria-hidden>
      <circle
        cx="12"
        cy="12"
        r="8.25"
        stroke="currentColor"
        strokeWidth="1.4"
        strokeDasharray="2.4 2.1"
      />
      <path
        d="M12 8.5v7M8.5 12h7"
        stroke="currentColor"
        strokeWidth="1.5"
        strokeLinecap="round"
      />
    </svg>
  );
}
