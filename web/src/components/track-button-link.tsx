"use client";

import type { ReactNode } from "react";
import { ButtonLink } from "@/components/ui";
import { track } from "@/lib/mixpanel";

export function TrackButtonLink({
  href,
  event,
  props,
  variant = "primary",
  className = "",
  children,
}: {
  href: string;
  event: string;
  props?: Record<string, string | number | boolean | undefined>;
  variant?: "primary" | "secondary" | "ghost";
  className?: string;
  children: ReactNode;
}) {
  return (
    <ButtonLink
      href={href}
      variant={variant}
      className={className}
      onClick={() => track(event, { href, ...props })}
    >
      {children}
    </ButtonLink>
  );
}
