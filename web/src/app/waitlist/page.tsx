import { redirect } from "next/navigation";
import { SiteHeader } from "@/components/site-header";
import { PageTitle, Shell } from "@/components/ui";
import { WaitlistForm } from "@/components/waitlist-form";
import { auth0 } from "@/lib/auth0";
import {
  downloadNextFromSearch,
  hasDownloadUnlock,
} from "@/lib/download-gate";

export async function generateMetadata({
  searchParams,
}: {
  searchParams: Promise<{ next?: string }>;
}) {
  const { next } = await searchParams;
  return {
    title: downloadNextFromSearch(next) ? "Try Alpha" : "Join waitlist",
  };
}

export default async function WaitlistPage({
  searchParams,
}: {
  searchParams: Promise<{ next?: string }>;
}) {
  const { next } = await searchParams;
  const downloadNext = downloadNextFromSearch(next);

  if (await hasDownloadUnlock()) {
    redirect(downloadNext ?? "/download");
  }

  const session = await auth0.getSession();
  const email =
    typeof session?.user?.email === "string" ? session.user.email : "";

  return (
    <Shell>
      <SiteHeader />

      <PageTitle
        title={downloadNext ? "Try Alpha" : "Join waitlist"}
        subtitle={
          downloadNext
            ? "Five quick questions, then your download starts."
            : "Five quick questions. We’ll use this to prioritize who gets in next."
        }
      />

      <WaitlistForm defaultEmail={email} next={downloadNext} />
    </Shell>
  );
}
