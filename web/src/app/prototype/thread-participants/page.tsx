import { Suspense } from "react";
import { PrototypeSwitcher } from "@/components/prototype/prototype-switcher";
import { THREAD_PARTICIPANTS } from "./participants";
import { VariantA, variantName as nameA } from "./variant-a";
import { VariantB, variantName as nameB } from "./variant-b";
import { VariantC, variantName as nameC } from "./variant-c";

export const dynamic = "force-dynamic";
export const metadata = { title: "PROTOTYPE · Thread participants" };

const VARIANTS = [
  { key: "A", name: nameA },
  { key: "B", name: nameB },
  { key: "C", name: nameC },
] as const;

/**
 * PROTOTYPE — throwaway.
 * Question: What should the landing-intro opening beat look like when selling
 * “an address for every intelligence” via a thread-participants panel?
 * Three variants via ?variant=A|B|C. Delete or absorb after a pick.
 */
export default async function PrototypeThreadParticipantsPage({
  searchParams,
}: {
  searchParams: Promise<{ variant?: string }>;
}) {
  const sp = await searchParams;
  const raw = (sp.variant ?? "A").toUpperCase();
  const variant = (["A", "B", "C"].includes(raw) ? raw : "A") as "A" | "B" | "C";

  return (
    <div className="flex min-h-dvh flex-col bg-stone-300/40">
      <header className="border-b border-stone-200 bg-stone-50 px-6 py-4">
        <p className="text-[11px] font-semibold uppercase tracking-[0.14em] text-amber-800">
          Prototype — throwaway
        </p>
        <h1 className="mt-1 font-display text-xl font-semibold tracking-tight text-stone-900">
          Thread participants · opening beat
        </h1>
        <p className="mt-1 max-w-2xl text-sm text-stone-500">
          Selling “An address for every intelligence.” Flip variants with ← → or
          the bar. Remotion will absorb the winner into{" "}
          <code className="text-stone-700">video/</code>.
        </p>
      </header>

      <main className="flex flex-1 flex-col items-center justify-center gap-6 p-6 pb-28">
        {/* 1080² stage — matches Remotion frame */}
        <div className="aspect-square w-full max-w-[min(100%,720px)] overflow-hidden rounded-2xl shadow-lg ring-1 ring-stone-400/30">
          {variant === "A" ? <VariantA /> : null}
          {variant === "B" ? <VariantB /> : null}
          {variant === "C" ? <VariantC /> : null}
        </div>

        {/* Surface state on every switch */}
        <pre className="w-full max-w-[min(100%,720px)] overflow-auto rounded-xl border border-stone-200 bg-stone-50 p-4 font-mono text-[11px] leading-relaxed text-stone-600">
          {JSON.stringify(
            {
              variant,
              name: VARIANTS.find((v) => v.key === variant)?.name,
              participants: THREAD_PARTICIPANTS.map((p) => p.address),
            },
            null,
            2,
          )}
        </pre>
      </main>

      <Suspense fallback={null}>
        <PrototypeSwitcher
          variants={[...VARIANTS]}
          current={variant}
        />
      </Suspense>
    </div>
  );
}
