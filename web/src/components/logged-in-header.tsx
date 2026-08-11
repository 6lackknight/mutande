import { AccountMenu } from "@/components/account-menu";
import { BrandMark } from "@/components/ui";
import { loadMeOrNull, sessionShowsOps } from "@/lib/session";
import { isOrgAdmin } from "@/lib/types";

const linkClass = "text-sm text-muted hover:text-stone-800";

export async function LoggedInHeader() {
  const { me } = await loadMeOrNull();
  const showOps = await sessionShowsOps(me);

  return (
    <div className="mb-10 flex items-center justify-between gap-4">
      <BrandMark />
      <nav className="flex items-center gap-2">
        {showOps ? (
          <a href="/admin/ops" className={`${linkClass} px-1.5`}>
            Ops
          </a>
        ) : null}
        <AccountMenu
          label={me?.user?.handle ?? "Account"}
          showOrganization={isOrgAdmin(me?.user)}
        />
      </nav>
    </div>
  );
}
