import { BrandMark, PageTitle, Shell } from "@/components/ui";
import { TrackButtonLink } from "@/components/track-button-link";
import { DownloadPlatformPicker } from "@/components/download-platform-picker";
import { CHANGELOG, LATEST_CHANGELOG } from "@/lib/changelog";
import {
  MAC_DMG_CHANNEL,
  MAC_DMG_LABEL,
  MAC_DMG_URL_ARM64,
  MAC_DMG_URL_INTEL,
  MAC_DMG_VERSION,
  MAC_INTEL_PUBLISHED,
  WIN_ZIP_CHANNEL,
  WIN_ZIP_LABEL,
  WIN_ZIP_PUBLISHED,
  WIN_ZIP_URL,
  WIN_ZIP_VERSION,
} from "@/lib/downloads";
import { AnalyticsEvent } from "@/lib/analytics-events";

export const metadata = { title: "Try Alpha" };

export default function DownloadPage() {
  return (
    <Shell wide>
      <div className="mb-10 flex items-center justify-between gap-4">
        <BrandMark />
        <nav className="flex items-center gap-3 text-sm">
          <a
            href="/docs"
            className="text-muted transition hover:text-stone-800"
          >
            Docs
          </a>
          <a
            href="/changelog"
            className="text-muted transition hover:text-stone-800"
          >
            Changelog
          </a>
          <TrackButtonLink
            href="/waitlist"
            event={AnalyticsEvent.WaitlistClick}
            props={{ surface: "download_nav" }}
            className="!py-2"
          >
            Join waitlist
          </TrackButtonLink>
        </nav>
      </div>

      <PageTitle
        title="Try Alpha"
        subtitle="Alpha builds for desktop. Pick your platform — expect rough edges."
      />

      <DownloadPlatformPicker
        macArm64Url={MAC_DMG_URL_ARM64}
        macIntelUrl={MAC_DMG_URL_INTEL}
        winZipUrl={WIN_ZIP_URL}
        macChannel={MAC_DMG_CHANNEL}
        winChannel={WIN_ZIP_CHANNEL}
        macLabel={MAC_DMG_LABEL}
        winLabel={WIN_ZIP_LABEL}
        macVersion={MAC_DMG_VERSION}
        winVersion={WIN_ZIP_VERSION}
        macIntelPublished={MAC_INTEL_PUBLISHED}
        winZipPublished={WIN_ZIP_PUBLISHED}
      />

      <section className="mt-12 border-t border-stone-300/50 pt-8">
        <div className="flex flex-wrap items-baseline justify-between gap-x-4 gap-y-2">
          <h2 className="font-display text-lg font-semibold tracking-tight text-stone-900">
            Recent versions
          </h2>
          <a
            href="/changelog"
            className="text-sm text-stone-700 underline underline-offset-2 transition hover:text-stone-900"
          >
            Full changelog
          </a>
        </div>
        <p className="mt-2 text-sm leading-relaxed text-muted">
          Latest:{" "}
          <span className="tabular-nums text-stone-800">
            {LATEST_CHANGELOG.version}
          </span>
          {" — "}
          {LATEST_CHANGELOG.title}.{" "}
          {CHANGELOG.slice(0, 4)
            .map((e) => e.version)
            .join(" · ")}
          .
        </p>
        <ul className="mt-4 space-y-2 text-sm leading-relaxed text-stone-700">
          {LATEST_CHANGELOG.notes.slice(0, 2).map((note) => (
            <li key={note} className="flex gap-2.5">
              <span
                aria-hidden
                className="mt-[0.55em] h-1 w-1 shrink-0 rounded-full bg-stone-400"
              />
              <span>{note}</span>
            </li>
          ))}
        </ul>
      </section>
    </Shell>
  );
}
