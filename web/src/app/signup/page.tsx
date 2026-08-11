import { LoggedInHeader } from "@/components/logged-in-header";
import { ChoiceCard, Alert, PageTitle, Shell } from "@/components/ui";
import {
  defaultHandleFromEmail,
  loadMeOrNull,
  requireSession,
} from "@/lib/session";
import { redirect } from "next/navigation";

export const dynamic = "force-dynamic";
export const metadata = { title: "Get started" };

export default async function SignupPage({
  searchParams,
}: {
  searchParams: Promise<{ hub_error?: string }>;
}) {
  const session = await requireSession();
  const { hub_error } = await searchParams;
  const { me, error } = await loadMeOrNull();

  if (me?.onboarded) {
    redirect("/dashboard");
  }

  const email =
    typeof session.user.email === "string" ? session.user.email : undefined;
  const previewHandle = defaultHandleFromEmail(email, "your-org");

  return (
    <Shell>
      <LoggedInHeader />
      <PageTitle
        title="How are you joining?"
        subtitle={`Signed in as ${email ?? session.user.name ?? "you"}. Create a team or redeem an invite. Your handle will look like ${previewHandle}.`}
      />

      {(hub_error || error) && (
        <div className="mb-6">
          <Alert tone="amber">{hub_error || error}</Alert>
        </div>
      )}

      <div className="space-y-3">
        <ChoiceCard
          href="/onboarding/create"
          title="Create team"
          description="Pick an org slug, name your team, and claim your handle as admin."
        />
        <ChoiceCard
          href="/join"
          title="I have an invite"
          description="Enter an invite code or open a /join?invite=… link from your admin."
        />
      </div>
    </Shell>
  );
}
