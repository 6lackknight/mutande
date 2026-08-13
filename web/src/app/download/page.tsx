import { SiteHeader } from "@/components/site-header";
import { PageTitle, Shell } from "@/components/ui";
import { DownloadPlatformPicker } from "@/components/download-platform-picker";
import { CHANGELOG, LATEST_CHANGELOG } from "@/lib/changelog";
import {
  MAC_DMG_LABEL,
  MAC_DMG_URL_ARM64,
  MAC_DMG_URL_INTEL,
  MAC_DMG_VERSION,
  MAC_INTEL_PUBLISHED,
  WIN_ZIP_LABEL,
  WIN_ZIP_PUBLISHED,
  WIN_ZIP_URL,
  WIN_ZIP_VERSION,
} from "@/lib/downloads";

export const metadata = { title: "Try Alpha" };

export default function DownloadPage() {
  return (
    <Shell wide>
      <SiteHeader />

      <PageTitle
        title="Try Alpha"
        subtitle="Alpha builds for desktop. Your download should start automatically — expect rough edges."
      />

      <DownloadPlatformPicker
        macArm64Url={MAC_DMG_URL_ARM64}
        macIntelUrl={MAC_DMG_URL_INTEL}
        winZipUrl={WIN_ZIP_URL}
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
