import { Suspense } from "react";
import { PrototypeSwitcher } from "@/components/prototype/prototype-switcher";
import { ComposeStage } from "./stage";
import { VARIANT_META } from "./types";

export const dynamic = "force-dynamic";
export const metadata = { title: "PROTOTYPE · Compose" };

/**
 * PROTOTYPE — throwaway.
 * Question: What should Threads compose look like vs the labeled Recipient/Note card?
 * Three variants via ?variant=A|B|C. Delete or absorb after a pick.
 */
export default async function PrototypeComposePage({
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
          Threads compose
        </h1>
        <p className="mt-1 max-w-2xl text-sm text-stone-500">
          Current UI is a labeled Recipient / Note card under the pills. Flip
          with ← →. Winner folds into{" "}
          <code className="text-stone-700">app/lib/screens/threads_screen.dart</code>
          .
        </p>
      </header>

      <main className="flex flex-1 flex-col items-center gap-6 p-6 pb-28">
        <ComposeStage variant={variant} />
      </main>

      <Suspense fallback={null}>
        <PrototypeSwitcher variants={[...VARIANT_META]} current={variant} />
      </Suspense>
    </div>
  );
}
