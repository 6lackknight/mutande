import { SiteHeader } from "@/components/site-header";
import { ProfileForm } from "@/components/profile-form";
import { PageTitle, Shell } from "@/components/ui";
import { requireOnboarded } from "@/lib/session";

export const dynamic = "force-dynamic";
export const metadata = { title: "Profile" };

export default async function ProfilePage() {
  const me = await requireOnboarded();

  return (
    <Shell wide>
      <SiteHeader />
      <PageTitle
        title="Profile"
        subtitle="How you appear to teammates. You can change your display name and handle."
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
