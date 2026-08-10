"use client";

import { useEffect } from "react";
import { usePathname, useRouter, useSearchParams } from "next/navigation";

type Props = {
  variants: { key: string; name: string }[];
  current: string;
};

/** PROTOTYPE ONLY — floating variant bar. Hidden in production builds. */
export function PrototypeSwitcher({ variants, current }: Props) {
  const router = useRouter();
  const pathname = usePathname();
  const searchParams = useSearchParams();

  if (process.env.NODE_ENV === "production") return null;

  const idx = Math.max(
    0,
    variants.findIndex((v) => v.key === current),
  );
  const label = variants[idx] ?? variants[0];

  const go = (nextIdx: number) => {
    const wrapped = (nextIdx + variants.length) % variants.length;
    const key = variants[wrapped]!.key;
    const params = new URLSearchParams(searchParams.toString());
    params.set("variant", key);
    router.replace(`${pathname}?${params.toString()}`);
  };

  useEffect(() => {
    const onKey = (e: KeyboardEvent) => {
      const t = e.target as HTMLElement | null;
      if (
        t &&
        (t.tagName === "INPUT" ||
          t.tagName === "TEXTAREA" ||
          t.isContentEditable)
      ) {
        return;
      }
      if (e.key === "ArrowLeft") go(idx - 1);
      if (e.key === "ArrowRight") go(idx + 1);
    };
    window.addEventListener("keydown", onKey);
    return () => window.removeEventListener("keydown", onKey);
  });

  return (
    <div className="fixed bottom-6 left-1/2 z-[9999] flex -translate-x-1/2 items-center gap-3 rounded-full border border-stone-800 bg-stone-900 px-3 py-2 text-sm text-stone-50 shadow-xl">
      <button
        type="button"
        aria-label="Previous variant"
        className="rounded-full px-2 py-1 hover:bg-stone-700"
        onClick={() => go(idx - 1)}
      >
        ←
      </button>
      <span className="min-w-[14rem] text-center font-medium tracking-tight">
        {label.key} — {label.name}
      </span>
      <button
        type="button"
        aria-label="Next variant"
        className="rounded-full px-2 py-1 hover:bg-stone-700"
        onClick={() => go(idx + 1)}
      >
        →
      </button>
    </div>
  );
}
