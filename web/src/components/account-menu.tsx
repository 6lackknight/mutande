"use client";

import { useEffect, useRef, useState } from "react";

/** Small account dropdown — handle as trigger, org/profile/logout beneath. */
export function AccountMenu({
  label,
  showOrganization,
  avatarUrl,
}: {
  label: string;
  showOrganization?: boolean;
  avatarUrl?: string;
}) {
  const [open, setOpen] = useState(false);
  const rootRef = useRef<HTMLDivElement>(null);

  useEffect(() => {
    if (!open) return;
    const onPointerDown = (e: PointerEvent) => {
      if (!rootRef.current?.contains(e.target as Node)) setOpen(false);
    };
    const onKeyDown = (e: KeyboardEvent) => {
      if (e.key === "Escape") setOpen(false);
    };
    document.addEventListener("pointerdown", onPointerDown);
    document.addEventListener("keydown", onKeyDown);
    return () => {
      document.removeEventListener("pointerdown", onPointerDown);
      document.removeEventListener("keydown", onKeyDown);
    };
  }, [open]);

  const itemClass =
    "block w-full px-3.5 py-2 text-left text-sm text-stone-700 transition hover:bg-stone-100 hover:text-stone-900";

  return (
    <div ref={rootRef} className="relative">
      <button
        type="button"
        aria-haspopup="menu"
        aria-expanded={open}
        onClick={() => setOpen((v) => !v)}
        className="flex max-w-[14rem] items-center gap-1.5 rounded-md px-3 py-2 text-sm font-medium text-stone-900 transition hover:bg-stone-200/40"
      >
        {avatarUrl ? (
          // eslint-disable-next-line @next/next/no-img-element -- tiny data-URL avatar
          <img
            src={avatarUrl}
            alt=""
            className="h-5 w-5 shrink-0 rounded-full object-cover ring-1 ring-stone-900/10"
          />
        ) : null}
        <span className="truncate">{label}</span>
        <svg
          width="12"
          height="12"
          viewBox="0 0 12 12"
          aria-hidden
          className={`shrink-0 text-stone-500 transition-transform ${open ? "rotate-180" : ""}`}
        >
          <path
            d="M2.5 4.5 6 8l3.5-3.5"
            fill="none"
            stroke="currentColor"
            strokeWidth="1.4"
            strokeLinecap="round"
            strokeLinejoin="round"
          />
        </svg>
      </button>

      {open ? (
        <div
          role="menu"
          className="absolute right-0 top-full z-30 mt-1.5 w-44 overflow-hidden rounded-lg border border-stone-300/60 bg-white/95 py-1 shadow-[0_12px_32px_-16px_rgba(28,25,23,0.35)] backdrop-blur-sm"
        >
          <a role="menuitem" href="/profile" className={itemClass}>
            Profile
          </a>
          <a role="menuitem" href="/contacts" className={itemClass}>
            Contacts
          </a>
          {showOrganization ? (
            <a role="menuitem" href="/admin/invites" className={itemClass}>
              Organization
            </a>
          ) : null}
          <div className="mx-3 my-1 border-t border-stone-200" />
          <a role="menuitem" href="/auth/logout" className={itemClass}>
            Log out
          </a>
        </div>
      ) : null}
    </div>
  );
}
