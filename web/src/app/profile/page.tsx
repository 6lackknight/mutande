import { LoggedInHeader } from "@/components/logged-in-header";
import { ProfileForm } from "@/components/profile-form";
import { PageTitle, Shell } from "@/components/ui";
import { requireOnboarded } from "@/lib/session";

export const dynamic = "force-dynamic";
export const metadata = { title: "Profile" };

export default async function ProfilePage() {
  const me = await requireOnboarded();

  return (
    <Shell wide>
      <LoggedInHeader />
      <PageTitle
        title="Profile"
        subtitle="How you appear to teammates. Your handle stays fixed."
      />
      <ProfileForm
        initialName={me.user?.display_name ?? ""}
        initialAvatarUrl={me.user?.avatar_url ?? null}
        handle={me.user?.handle ?? "—"}
        email={me.email ?? "—"}
      />
    </Shell>
  );
}
