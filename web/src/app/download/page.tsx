import {
  Alert,
  BrandMark,
  PageTitle,
  Shell,
} from "@/components/ui";
import { TrackButtonLink } from "@/components/track-button-link";
import { TrackChoiceCard } from "@/components/track-choice-card";
import { TrackLink } from "@/components/track-link";
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

      <div className="grid gap-3 sm:grid-cols-3">
        <TrackChoiceCard
          href={MAC_DMG_URL_ARM64}
          title="Mac · Silicon"
          description={`${MAC_DMG_CHANNEL} · arm64 DMG. Drag into Applications.`}
          event={AnalyticsEvent.DownloadArtifactClick}
          props={{ platform: "mac_arm64" }}
        />
        {MAC_INTEL_PUBLISHED ? (
          <TrackChoiceCard
            href={MAC_DMG_URL_INTEL}
            title="Mac · Intel"
            description={`${MAC_DMG_CHANNEL} · x86_64 DMG. No Rosetta needed.`}
            event={AnalyticsEvent.DownloadArtifactClick}
            props={{ platform: "mac_intel" }}
          />
        ) : (
          <SoonCard
            title="Mac · Intel"
            description="Not on the site yet — Silicon build is the current alpha."
          />
        )}
        {WIN_ZIP_PUBLISHED ? (
          <TrackChoiceCard
            href={WIN_ZIP_URL}
            title="Windows"
            description={`${WIN_ZIP_CHANNEL} · portable zip. SmartScreen may warn.`}
            event={AnalyticsEvent.DownloadArtifactClick}
            props={{ platform: "windows" }}
          />
        ) : (
          <SoonCard
            title="Windows"
            description="Unsigned zip coming soon — Mac Silicon is ready now."
          />
        )}
      </div>

      <div className="mt-10 space-y-3">
        <Alert tone="ok">
          {MAC_DMG_LABEL} — Apple Silicon. Open the DMG and drag mutande into
          Applications.
        </Alert>
        {WIN_ZIP_PUBLISHED ? (
          <Alert>
            {WIN_ZIP_LABEL} — unsigned zip from CI. SmartScreen may warn; choose
            More info → Run anyway. Not publisher-trusted like the Mac DMGs.
          </Alert>
        ) : null}
        <p className="text-sm text-muted">
          <TrackLink
            href={MAC_DMG_URL_ARM64}
            event={AnalyticsEvent.DownloadArtifactClick}
            props={{ platform: "mac_arm64", surface: "filename" }}
            className="underline underline-offset-2 hover:text-stone-900"
          >
            mutande-alpha.dmg
          </TrackLink>
          {MAC_INTEL_PUBLISHED ? (
            <>
              {" · "}
              <TrackLink
                href={MAC_DMG_URL_INTEL}
                event={AnalyticsEvent.DownloadArtifactClick}
                props={{ platform: "mac_intel", surface: "filename" }}
                className="underline underline-offset-2 hover:text-stone-900"
              >
                mutande-alpha-intel.dmg
              </TrackLink>
            </>
          ) : null}
          {WIN_ZIP_PUBLISHED ? (
            <>
              {" · "}
              <TrackLink
                href={WIN_ZIP_URL}
                event={AnalyticsEvent.DownloadArtifactClick}
                props={{ platform: "windows", surface: "filename" }}
                className="underline underline-offset-2 hover:text-stone-900"
              >
                mutande-alpha-windows.zip
              </TrackLink>
            </>
          ) : null}{" "}
          <span className="text-stone-400">
            (Mac {MAC_DMG_VERSION}
            {WIN_ZIP_PUBLISHED ? ` · Win ${WIN_ZIP_VERSION}` : ""})
          </span>
        </p>
      </div>

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
