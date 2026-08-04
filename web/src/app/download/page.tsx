import {
  Alert,
  BrandMark,
  ButtonLink,
  ChoiceCard,
  PageTitle,
  Shell,
} from "@/components/ui";
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
          <ButtonLink href="/waitlist" className="!py-2">
            Join waitlist
          </ButtonLink>
        </nav>
      </div>

      <PageTitle
        title="Try Alpha"
        subtitle="Alpha builds for desktop. Pick your platform — expect rough edges."
      />

      <div className="grid gap-3 sm:grid-cols-3">
        <ChoiceCard
          href={MAC_DMG_URL_ARM64}
          title="Mac · Silicon"
          description={`${MAC_DMG_CHANNEL} · arm64 DMG. Drag into Applications.`}
        />
        {MAC_INTEL_PUBLISHED ? (
          <ChoiceCard
            href={MAC_DMG_URL_INTEL}
            title="Mac · Intel"
            description={`${MAC_DMG_CHANNEL} · x86_64 DMG. No Rosetta needed.`}
          />
        ) : (
          <SoonCard
            title="Mac · Intel"
            description="Not on the site yet — Silicon build is the current alpha."
          />
        )}
        {WIN_ZIP_PUBLISHED ? (
          <ChoiceCard
            href={WIN_ZIP_URL}
            title="Windows"
            description={`${WIN_ZIP_CHANNEL} · portable zip. SmartScreen may warn.`}
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
          <a
            href={MAC_DMG_URL_ARM64}
            className="underline underline-offset-2 hover:text-stone-900"
          >
            mutande-alpha.dmg
          </a>
          {MAC_INTEL_PUBLISHED ? (
            <>
              {" · "}
              <a
                href={MAC_DMG_URL_INTEL}
                className="underline underline-offset-2 hover:text-stone-900"
              >
                mutande-alpha-intel.dmg
              </a>
            </>
          ) : null}
          {WIN_ZIP_PUBLISHED ? (
            <>
              {" · "}
              <a
                href={WIN_ZIP_URL}
                className="underline underline-offset-2 hover:text-stone-900"
              >
                mutande-alpha-windows.zip
              </a>
            </>
          ) : null}{" "}
          <span className="text-stone-400">
            (Mac {MAC_DMG_VERSION}
            {WIN_ZIP_PUBLISHED ? ` · Win ${WIN_ZIP_VERSION}` : ""})
          </span>
        </p>
      </div>
    </Shell>
  );
}
