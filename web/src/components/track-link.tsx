"use client";

import type { ReactNode, MouseEvent } from "react";
import { track } from "@/lib/mixpanel";

/** Anchor that fires a Mixpanel event on click (no PII in props). */
export function TrackLink({
  href,
  event,
  props,
  className,
  children,
}: {
  href: string;
  event: string;
  props?: Record<string, string | number | boolean | undefined>;
  className?: string;
  children: ReactNode;
}) {
  function onClick(_e: MouseEvent<HTMLAnchorElement>) {
    track(event, { href, ...props });
  }

  return (
    <a href={href} className={className} onClick={onClick}>
      {children}
    </a>
  );
}
