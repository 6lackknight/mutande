import { BrandMark } from "@/components/ui";
import { loadMeOrNull, sessionShowsOps } from "@/lib/session";

const linkClass = "text-sm text-muted hover:text-stone-800";

export async function LoggedInHeader() {
  const { me } = await loadMeOrNull();
  const showOps = await sessionShowsOps(me);

  return (
    <div className="mb-10 flex items-center justify-between gap-4">
      <BrandMark />
      <nav className="flex items-center gap-4">
        {showOps ? (
          <a href="/admin/ops" className={linkClass}>
            Ops
          </a>
        ) : null}
        <a href="/auth/logout" className={linkClass}>
          Sign out
        </a>
      </nav>
    </div>
  );
}
