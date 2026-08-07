"use client";

import { useEffect, useMemo, useState } from "react";
import { WarpBackground } from "@/components/magicui/warp-background";
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
  href: string;
  fileName: string;
  alert: string;
  alertTone: "ok" | "amber";
  published: boolean;
};

function triggerDownload(href: string) {
  const a = document.createElement("a");
  a.href = href;
  a.rel = "noopener";
  document.body.appendChild(a);
  a.click();
  a.remove();
}

/** Survives React Strict Mode remount so autodetect only fires once per page load. */
let autodetectStarted = false;

export function DownloadPlatformPicker({
  macArm64Url,
  macIntelUrl,
  winZipUrl,
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
        href: macArm64Url,
        fileName: "mutande-alpha.dmg",
        alert: `${macLabel} — Apple Silicon. Check your downloads folder.`,
        alertTone: "ok",
        published: true,
      },
      {
        id: "mac_intel",
        title: "Mac · Intel",
        href: macIntelUrl,
        fileName: "mutande-alpha-intel.dmg",
        alert: `${macLabel} — Intel. Check your downloads folder.`,
        alertTone: "ok",
        published: macIntelPublished,
      },
      {
        id: "windows",
        title: "Windows",
        href: winZipUrl,
        fileName: "mutande-alpha-windows.zip",
        alert: `${winLabel}. Check your downloads folder.`,
        alertTone: "amber",
        published: winZipPublished,
      },
    ],
    [
      macArm64Url,
      macIntelUrl,
      winZipUrl,
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

  const published = useMemo(
    () => options.filter((o) => o.published),
    [options],
  );

  // SSR + first paint: silicon (always published). Client effect upgrades.
  const [selected, setSelected] = useState<DownloadPlatform>("mac_arm64");
  const [confirmed, setConfirmed] = useState<PlatformOption | null>(null);

  const startFor = (option: PlatformOption, surface: string) => {
    setSelected(option.id);
    setConfirmed(option);
    track(AnalyticsEvent.DownloadArtifactClick, {
      href: option.href,
      artifact: option.title,
      platform: option.id,
      surface,
    });
    triggerDownload(option.href);
  };

  useEffect(() => {
    let cancelled = false;
    void (async () => {
      const raw = await detectDownloadPlatform();
      if (cancelled || autodetectStarted) return;
      autodetectStarted = true;
      const id = resolvePublishedPlatform(raw, available);
      const option =
        options.find((o) => o.id === id && o.published) ??
        options.find((o) => o.published)!;
      startFor(option, "autodetect");
    })();
    return () => {
      cancelled = true;
    };
    // Intentionally once after mount (module flag blocks Strict Mode double-start).
    // eslint-disable-next-line react-hooks/exhaustive-deps -- autodetect boot
  }, [available, options]);

  const current =
    confirmed ??
    options.find((o) => o.id === selected && o.published) ??
    options.find((o) => o.published)!;

  const switchTargets = published.filter((o) => o.id !== current.id);

  return (
    <div className="space-y-3">
      <WarpBackground
        className="min-h-[40vh] overflow-hidden border-stone-300/60 bg-stone-50/40 p-4 sm:p-5"
        gridColor="color-mix(in oklch, var(--stone-300) 55%, transparent)"
        beamsPerSide={2}
        beamDuration={4}
      >
        {/* Inner flex: grid/flex on WarpBackground collapses @container-[size] beams. */}
        <div className="flex min-h-[calc(40vh-2rem)] items-center justify-center sm:min-h-[calc(40vh-2.5rem)]">
          <div
            className={`h-fit w-fit max-w-full rounded-md border px-4 py-3.5 text-sm leading-relaxed shadow-sm sm:px-5 sm:py-4 ${
              current.alertTone === "ok"
                ? "border-accent/30 bg-accent-soft/95 text-stone-800"
                : "border-amber-300/50 bg-amber-50/90 text-stone-800"
            }`}
          >
            <p className="font-medium text-stone-900">
              {confirmed
                ? `Download started — ${current.title}`
                : `Preparing download — ${current.title}`}
            </p>
            <p className="mt-1.5 max-w-prose">{current.alert}</p>
          </div>
        </div>
      </WarpBackground>

      {switchTargets.length > 0 ? (
        <p className="text-sm text-muted">
          Need a different build?{" "}
          {switchTargets.map((o, i) => (
            <span key={o.id}>
              {i > 0 ? " · " : null}
              <button
                type="button"
                onClick={() => startFor(o, "platform_switch")}
                className="underline underline-offset-2 hover:text-stone-900"
              >
                {o.title}
              </button>
            </span>
          ))}
        </p>
      ) : null}

      <p className="text-sm text-muted">
        {published.map((o, i) => (
          <span key={o.id}>
            {i > 0 ? " · " : null}
            <button
              type="button"
              onClick={() => startFor(o, "filename")}
              className="underline underline-offset-2 hover:text-stone-900"
            >
              {o.fileName}
            </button>
          </span>
        ))}{" "}
        <span className="text-stone-400">
          (Mac {macVersion}
          {winZipPublished ? ` · Win ${winVersion}` : ""})
        </span>
      </p>
    </div>
  );
}
