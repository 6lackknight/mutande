"use client";

import { ChoiceCard } from "@/components/ui";
import { track } from "@/lib/mixpanel";

export function TrackChoiceCard({
  href,
  title,
  description,
  event,
  props,
}: {
  href: string;
  title: string;
  description: string;
  event: string;
  props?: Record<string, string | number | boolean | undefined>;
}) {
  return (
    <ChoiceCard
      href={href}
      title={title}
      description={description}
      onClick={() => track(event, { href, artifact: title, ...props })}
    />
  );
}
