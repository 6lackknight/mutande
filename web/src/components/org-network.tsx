"use client";

import { useId, useState } from "react";
import { motion, useReducedMotion } from "motion/react";
import { ContactAvatar } from "@/components/contact-avatar";
import { JoinQr } from "@/components/join-qr";
import { ButtonLink } from "@/components/ui";

export type OrgNetworkPerson = {
  handle: string;
  label: string;
  isSelf?: boolean;
  avatarUrl?: string;
  displayName?: string;
};

const SEAT_CAP = 20;

function localPart(handle: string): string {
  const h = handle.trim().toLowerCase();
  const at = h.indexOf("@");
  if (at <= 0) return h;
  return h.slice(0, at);
}

export function OrgNetwork({
  orgSlug,
  orgName,
  handle,
  people,
  inviteHref,
  joinUrl,
  loadError,
}: {
  orgSlug: string;
  orgName?: string;
  handle?: string;
  people: OrgNetworkPerson[];
  inviteHref?: string;
  joinUrl?: string;
  loadError?: string | null;
}) {
  const liveId = useId();
  const reduce = useReducedMotion();
  const [sealed, setSealed] = useState<string | null>(null);
  const slug = orgSlug.trim().toLowerCase();
  const broadcast = slug ? `@all@${slug}` : "";
  const shown = people.slice(0, 12);
  const n = Math.max(shown.length, 1);
  const teammates = people.filter((p) => !p.isSelf);
  const title = (handle || orgName || slug || "Org").trim();
  const showOrgLine = Boolean(
    orgName && orgName.trim().toLowerCase() !== title.toLowerCase(),
  );

  async function copy(value: string) {
    try {
      await navigator.clipboard.writeText(value);
      setSealed(value);
      window.setTimeout(() => {
        setSealed((prev) => (prev === value ? null : prev));
      }, 1600);
    } catch {
      /* ignore */
    }
  }

  return (
    <section>
      <div className="min-w-0 max-w-xl">
        <div className="flex flex-wrap items-baseline justify-between gap-x-4 gap-y-1">
          <p className="text-[13px] font-medium uppercase tracking-[0.12em] text-muted">
            Org
          </p>
          <p className="text-[13px] tabular-nums text-muted">
            seats {people.length}/{SEAT_CAP}
          </p>
        </div>
        <h2 className="-ml-[0.04em] mt-2 font-display text-[clamp(1.85rem,4vw,3.1rem)] font-semibold leading-[1.05] tracking-[-0.035em] text-stone-900">
          {title}
        </h2>
        {showOrgLine ? (
          <p className="mt-2 text-[15px] leading-snug text-stone-600">
            {orgName}
            {slug ? <span className="ml-2 text-muted">@{slug}</span> : null}
          </p>
        ) : null}
      </div>

      <div className="mt-8 grid items-start gap-8 lg:grid-cols-[minmax(16rem,22rem)_minmax(0,1fr)] lg:gap-x-14">
        <div className="min-w-0 max-w-sm">
          {loadError ? (
            <p className="text-[15px] leading-relaxed text-muted">
              Couldn’t load teammates. Refresh to try again.
            </p>
          ) : people.length > 0 ? (
            <ul className="divide-y divide-stone-200/80 border-y border-stone-200/80">
              {people.map((person) => (
                <li key={person.handle}>
                  <button
                    type="button"
                    onClick={() => copy(person.handle)}
                    className="flex min-h-12 w-full items-center gap-3 py-2.5 text-left transition hover:bg-stone-100/60 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-accent/35"
                  >
                    <ContactAvatar
                      handle={person.handle}
                      avatarUrl={person.avatarUrl}
                      name={person.displayName}
                      size={40}
                    />
                    <span className="min-w-0 flex-1">
                      <span className="block truncate text-[14px] font-medium leading-tight text-stone-800">
                        {sealed === person.handle
                          ? "sealed"
                          : person.displayName?.trim() ||
                            localPart(person.handle)}
                      </span>
                      <span className="mt-0.5 block truncate text-[12px] leading-snug text-muted">
                        {person.handle}
                      </span>
                    </span>
                    {person.isSelf ? (
                      <span className="shrink-0 text-[12px] text-muted">
                        you
                      </span>
                    ) : null}
                  </button>
                </li>
              ))}
            </ul>
          ) : null}

          {joinUrl ? (
            <div className="mt-8">
              <JoinQr url={joinUrl} caption="Scan to join this org." />
            </div>
          ) : inviteHref ? (
            <p className="mt-8 text-[13px] leading-relaxed text-muted">
              No join code yet.{" "}
              <a
                href={inviteHref}
                className="font-medium text-stone-800 underline decoration-stone-300 underline-offset-[3px] hover:decoration-stone-600"
              >
                Create an invite
              </a>{" "}
              to show a QR.
            </p>
          ) : teammates.length === 0 ? (
            <p className="mt-8 text-[15px] leading-relaxed text-stone-600">
              One strand on the web. Ask an admin to invite the rest of the org.
            </p>
          ) : null}

          <div className="mt-8 flex flex-col gap-3">
            <ButtonLink
              href={inviteHref ?? "/admin/invites"}
              className="w-full !min-h-12 py-3.5 text-[15px]"
            >
              Invite to org
            </ButtonLink>
            <ButtonLink
              href="/contacts#add-contact"
              variant="secondary"
              className="w-full !min-h-12 py-3.5 text-[15px]"
            >
              Add a contact
            </ButtonLink>
          </div>
        </div>

        <div className="w-full rounded-2xl border border-stone-300/70 bg-white/50 p-3 sm:p-4">
        <div className="relative aspect-square w-full">
        <div className="orbit-spin pointer-events-none absolute inset-0">
          <svg
            className="h-full w-full text-stone-300"
            viewBox="0 0 100 100"
            aria-hidden
          >
            <circle
              cx="50"
              cy="50"
              r="41"
              fill="none"
              stroke="currentColor"
              strokeWidth="0.35"
            />
            <circle
              cx="50"
              cy="50"
              r="28"
              fill="none"
              stroke="currentColor"
              strokeWidth="0.28"
              strokeDasharray="0.9 1.8"
            />
          </svg>
        </div>
        <div className="orbit-spin-rev pointer-events-none absolute inset-[18%]">
          <svg
            className="h-full w-full text-stone-200"
            viewBox="0 0 100 100"
            aria-hidden
          >
            <circle
              cx="50"
              cy="50"
              r="48"
              fill="none"
              stroke="currentColor"
              strokeWidth="0.5"
            />
          </svg>
        </div>

        <div className="absolute left-1/2 top-1/2 z-[2] -translate-x-1/2 -translate-y-1/2">
          <motion.button
            type="button"
            onClick={() => broadcast && copy(broadcast)}
            className="relative flex min-h-11 min-w-11 flex-col items-center focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-accent/35 focus-visible:ring-offset-2 focus-visible:ring-offset-[var(--stone-50)]"
            aria-label={
              broadcast ? `Copy org broadcast ${broadcast}` : "Org hub"
            }
            animate={
              sealed === broadcast && !reduce
                ? { scale: [1, 1.08, 1] }
                : { scale: 1 }
            }
            transition={{ duration: 0.35, ease: [0.25, 1, 0.5, 1] }}
          >
            <span
              aria-hidden
              className="seal-pulse pointer-events-none absolute left-1/2 top-1/2 h-28 w-28 -translate-x-1/2 -translate-y-1/2 rounded-full bg-[color-mix(in_oklch,var(--accent)_22%,transparent)] blur-md"
            />
            <span className="relative flex h-[5.5rem] w-[5.5rem] items-center justify-center rounded-full bg-stone-900 text-[15px] font-semibold tracking-tight text-stone-50 shadow-[0_18px_40px_-18px_rgba(28,25,23,0.7)]">
              {sealed === broadcast ? "sealed" : slug || "org"}
            </span>
          </motion.button>
        </div>

        <div className="orbit-spin absolute inset-0">
          {shown.map((person, i) => {
            const angle = -Math.PI / 2 + (2 * Math.PI * i) / n;
            const left = 50 + Math.cos(angle) * 41;
            const top = 50 + Math.sin(angle) * 41;
            const label = person.isSelf
              ? "you"
              : person.displayName?.trim().split(/\s+/)[0] ||
                person.label.trim() ||
                localPart(person.handle);
            const justSealed = sealed === person.handle;
            return (
              <div
                key={person.handle}
                style={{ left: `${left}%`, top: `${top}%` }}
                className="absolute z-[2] w-20 -translate-x-1/2 -translate-y-1/2"
              >
                <motion.button
                  type="button"
                  title={person.handle}
                  onClick={() => copy(person.handle)}
                  initial={reduce ? false : { opacity: 0, scale: 0.86 }}
                  animate={{ opacity: 1, scale: 1 }}
                  transition={{
                    duration: 0.45,
                    delay: 0.12 + Math.min(i * 0.06, 0.4),
                    ease: [0.25, 1, 0.5, 1],
                  }}
                  whileHover={reduce ? undefined : { scale: 1.08 }}
                  whileTap={reduce ? undefined : { scale: 0.96 }}
                  className="group flex min-h-11 w-full flex-col items-center focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-accent/35"
                >
                  <span className="orbit-spin-rev flex flex-col items-center gap-1.5">
                    <span
                      className={`rounded-full bg-white p-0.5 ring-2 ${
                        person.isSelf
                          ? "ring-stone-900/50"
                          : "ring-stone-900/10 group-hover:ring-stone-800/30"
                      }`}
                    >
                      <ContactAvatar
                        handle={person.handle}
                        avatarUrl={person.avatarUrl}
                        name={person.displayName}
                        size={52}
                      />
                    </span>
                    <span className="max-w-[5.5rem] truncate text-[12px] font-medium text-stone-700">
                      {justSealed ? "sealed" : label}
                    </span>
                    <span className="max-w-[8rem] truncate text-[12px] text-muted opacity-0 transition-opacity duration-200 group-hover:opacity-100 group-focus-visible:opacity-100">
                      {person.handle}
                    </span>
                  </span>
                </motion.button>
              </div>
            );
          })}
        </div>
        </div>
        <p className="mt-3 text-center text-sm text-muted">
          Tap a person to copy their handle.
        </p>
      </div>
      </div>

      <p id={liveId} className="sr-only" aria-live="polite">
        {sealed ? `Sealed ${sealed} to clipboard` : ""}
      </p>
    </section>
  );
}
