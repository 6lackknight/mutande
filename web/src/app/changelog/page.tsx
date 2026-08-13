import { SiteHeader } from "@/components/site-header";
import { PageTitle, Shell } from "@/components/ui";
import { CHANGELOG } from "@/lib/changelog";
import { MAC_DMG_VERSION } from "@/lib/downloads";

export const metadata = {
  title: "Changelog",
  description:
    "Desktop alpha release notes for mutande — Mac and Windows cuts.",
};

function formatDate(iso: string): string {
  const d = new Date(`${iso}T12:00:00Z`);
  return d.toLocaleDateString("en-GB", {
    day: "numeric",
    month: "short",
    year: "numeric",
  });
}

export default function ChangelogPage() {
  return (
    <Shell wide>
      <SiteHeader />

      <PageTitle
        title="Changelog"
        subtitle={`Desktop alpha cuts. Current site build: ${MAC_DMG_VERSION}. Rolling installers on the downloads CDN — reinstall to update.`}
      />

      <ol className="space-y-0 divide-y divide-stone-300/50 border-y border-stone-300/50">
        {CHANGELOG.map((entry) => (
          <li key={entry.version} className="py-7 first:pt-6 last:pb-6">
            <div className="flex flex-wrap items-baseline justify-between gap-x-4 gap-y-1">
              <h2 className="font-display text-xl font-semibold tracking-tight text-stone-900">
                <span className="tabular-nums">{entry.version}</span>
                <span className="mx-2 font-normal text-stone-300">·</span>
                <span className="font-medium text-stone-800">{entry.title}</span>
              </h2>
              <time
                dateTime={entry.date}
                className="text-sm tabular-nums text-muted"
              >
                {formatDate(entry.date)}
              </time>
            </div>
            <ul className="mt-3 space-y-1.5 text-[15px] leading-relaxed text-stone-700">
              {entry.notes.map((note) => (
                <li key={note} className="flex gap-2.5">
                  <span
                    aria-hidden
                    className="mt-[0.55em] h-1 w-1 shrink-0 rounded-full bg-stone-400"
                  />
                  <span>{note}</span>
                </li>
              ))}
            </ul>
          </li>
        ))}
      </ol>

      <p className="mt-10 text-sm text-muted">
        Looking for installers?{" "}
        <a
          href="/download"
          className="text-stone-800 underline underline-offset-2 transition hover:text-stone-900"
        >
          Try Alpha
        </a>
        .
      </p>
    </Shell>
  );
}
