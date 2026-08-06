"use client";

import { useEffect, useMemo, useState } from "react";
import { Alert, ChoiceCard } from "@/components/ui";
import { TrackLink } from "@/components/track-link";
import {
  detectDownloadPlatform,
  resolvePublishedPlatform,
  type DownloadPlatform,
} from "@/lib/detect-download-platform";
import { AnalyticsEvent } from "@/lib/analytics-events";
import { track } from "@/lib/mixpanel";

type PlatformOption = {
  id: DownloadPlatform;
  title: string;
  description: string;
  href: string;
  fileName: string;
  alert: string;
  alertTone: "ok" | "amber";
  published: boolean;
  soonDescription: string;
};

function SoonCard({
  title,
  description,
}: {
  title: string;
  description: string;
}) {
  return (
    <div className="rounded-lg border border-dashed border-stone-300/80 bg-white/30 p-5">
      <div className="font-display text-lg text-stone-500">{title}</div>
      <p className="mt-1.5 text-sm leading-relaxed text-muted">{description}</p>
    </div>
  );
}

export function DownloadPlatformPicker({
  macArm64Url,
  macIntelUrl,
  winZipUrl,
  macChannel,
  winChannel,
  macLabel,
  winLabel,
  macVersion,
  winVersion,
  macIntelPublished,
  winZipPublished,
}: {
  macArm64Url: string;
  macIntelUrl: string;
  winZipUrl: string;
  macChannel: string;
  winChannel: string;
  macLabel: string;
  winLabel: string;
  macVersion: string;
  winVersion: string;
  macIntelPublished: boolean;
  winZipPublished: boolean;
}) {
  const options = useMemo<PlatformOption[]>(
    () => [
      {
        id: "mac_arm64",
        title: "Mac · Silicon",
        description: `${macChannel} · arm64 DMG. Drag into Applications.`,
        href: macArm64Url,
        fileName: "mutande-alpha.dmg",
        alert: `${macLabel} — Apple Silicon. Open the DMG and drag mutande into Applications.`,
        alertTone: "ok",
        published: true,
        soonDescription: "",
      },
      {
        id: "mac_intel",
        title: "Mac · Intel",
        description: `${macChannel} · x86_64 DMG. No Rosetta needed.`,
        href: macIntelUrl,
        fileName: "mutande-alpha-intel.dmg",
        alert: `${macLabel} — Intel. Open the DMG and drag mutande into Applications.`,
        alertTone: "ok",
        published: macIntelPublished,
        soonDescription:
          "Not on the site yet — Silicon build is the current alpha.",
      },
      {
        id: "windows",
        title: "Windows",
        description: `${winChannel} · portable zip. SmartScreen may warn.`,
        href: winZipUrl,
        fileName: "mutande-alpha-windows.zip",
        alert: `${winLabel} — unsigned zip from CI. SmartScreen may warn; choose More info → Run anyway. Not publisher-trusted like the Mac DMGs.`,
        alertTone: "amber",
        published: winZipPublished,
        soonDescription:
          "Unsigned zip coming soon — Mac Silicon is ready now.",
      },
    ],
    [
      macArm64Url,
      macIntelUrl,
      winZipUrl,
      macChannel,
      winChannel,
      macLabel,
      winLabel,
      macIntelPublished,
      winZipPublished,
    ],
  );

  const available = useMemo(
    () => options.filter((o) => o.published).map((o) => o.id),
    [options],
  );

  // SSR + first paint: silicon (always published). Client effect upgrades.
  const [selected, setSelected] = useState<DownloadPlatform>("mac_arm64");

  useEffect(() => {
    let cancelled = false;
    void (async () => {
      const raw = await detectDownloadPlatform();
      if (cancelled) return;
      setSelected(resolvePublishedPlatform(raw, available));
    })();
    return () => {
      cancelled = true;
    };
  }, [available]);

  const current =
    options.find((o) => o.id === selected && o.published) ??
    options.find((o) => o.published)!;

  return (
    <>
      <div className="grid gap-3 sm:grid-cols-3">
        {options.map((option) =>
          option.published ? (
            <ChoiceCard
              key={option.id}
              href={option.href}
              title={option.title}
              description={option.description}
              selected={selected === option.id}
              onClick={() => {
                setSelected(option.id);
                track(AnalyticsEvent.DownloadArtifactClick, {
                  href: option.href,
                  artifact: option.title,
                  platform: option.id,
                });
              }}
            />
          ) : (
            <SoonCard
              key={option.id}
              title={option.title}
              description={option.soonDescription}
            />
          ),
        )}
      </div>

      <div className="mt-10 space-y-3">
        <Alert tone={current.alertTone}>{current.alert}</Alert>
        {winZipPublished && current.id !== "windows" ? (
          <Alert>
            {winLabel} — unsigned zip from CI. SmartScreen may warn; choose More
            info → Run anyway. Not publisher-trusted like the Mac DMGs.
          </Alert>
        ) : null}
        <p className="text-sm text-muted">
          {options
            .filter((o) => o.published)
            .map((o, i) => (
              <span key={o.id}>
                {i > 0 ? " · " : null}
                <TrackLink
                  href={o.href}
                  event={AnalyticsEvent.DownloadArtifactClick}
                  props={{ platform: o.id, surface: "filename" }}
                  className="underline underline-offset-2 hover:text-stone-900"
                >
                  {o.fileName}
                </TrackLink>
              </span>
            ))}{" "}
          <span className="text-stone-400">
            (Mac {macVersion}
            {winZipPublished ? ` · Win ${winVersion}` : ""})
          </span>
        </p>
      </div>
    </>
  );
}
