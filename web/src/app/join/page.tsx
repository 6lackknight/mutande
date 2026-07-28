import { redirect } from "next/navigation";
import { JoinForm } from "@/components/join-form";
import { Alert, BrandMark, PageTitle, Shell } from "@/components/ui";
import {
  defaultHandleFromEmail,
  loadMeOrNull,
  requireSession,
} from "@/lib/session";

export const dynamic = "force-dynamic";
export const metadata = { title: "Join team" };

export default async function JoinPage({
  searchParams,
}: {
  searchParams: Promise<{ invite?: string }>;
}) {
  const { invite = "" } = await searchParams;
  const returnTo = invite
    ? `/join?invite=${encodeURIComponent(invite)}`
    : "/join";
  const session = await requireSession(returnTo);
  const { me, error } = await loadMeOrNull();

  if (me?.onboarded) redirect("/dashboard");

  const email =
    typeof session.user.email === "string" ? session.user.email : undefined;

  return (
    <Shell>
      <div className="mb-10 flex items-center justify-between gap-4">
        <BrandMark />
        <a href="/signup" className="text-sm text-muted hover:text-stone-800">
          Back
        </a>
      </div>
      <PageTitle
        title="Join with invite"
        subtitle="Use the code from your admin or a shared /join?invite=… link."
      />
      {error ? (
        <div className="mb-6">
          <Alert tone="amber">Hub status: {error}</Alert>
        </div>
      ) : null}
      <JoinForm
        initialInvite={invite}
        initialHandle={defaultHandleFromEmail(email, "org")}
      />
    </Shell>
  );
}
