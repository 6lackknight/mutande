import { redirect } from "next/navigation";
import { BrandMark, ButtonLink, PageTitle, Shell } from "@/components/ui";
import { auth0 } from "@/lib/auth0";

export const dynamic = "force-dynamic";
export const metadata = { title: "Sign in" };

export default async function LoginPage({
  searchParams,
}: {
  searchParams: Promise<{ returnTo?: string }>;
}) {
  const session = await auth0.getSession();
  const { returnTo } = await searchParams;
  if (session) {
    redirect(returnTo || "/dashboard");
  }

  const loginHref = `/auth/login?returnTo=${encodeURIComponent(returnTo || "/signup")}`;
  const signupHref = `/auth/login?screen_hint=signup&returnTo=${encodeURIComponent(returnTo || "/signup")}`;

  return (
    <Shell>
      <BrandMark className="mb-10" />
      <PageTitle
        title="Sign in"
        subtitle="Magic link or email and password via Auth0. After sign-in you’ll create a team or join with an invite."
      />
      <div className="flex flex-col gap-3">
        <ButtonLink href={loginHref} className="w-full">
          Continue with Auth0
        </ButtonLink>
        <ButtonLink href={signupHref} variant="secondary" className="w-full">
          Create an account
        </ButtonLink>
      </div>
      <p className="mt-8 text-sm text-muted">
        Already joining a team?{" "}
        <a href="/join" className="text-stone-800 underline-offset-2 hover:underline">
          Have an invite
        </a>
      </p>
    </Shell>
  );
}
