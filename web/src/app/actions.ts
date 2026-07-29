"use server";

import { redirect } from "next/navigation";
import {
  createInvite,
  createOrg,
  formatHubError,
  getMe,
  joinOrg,
} from "@/lib/hub";
import { sendInviteEmail } from "@/lib/plunk";
import { joinUrlForCode, requireSession } from "@/lib/session";

export type ActionState = {
  error?: string;
  ok?: string;
  inviteCode?: string;
  inviteEmail?: string;
  joinUrl?: string;
  emailSkipped?: string;
};

function slugify(raw: string): string {
  return raw
    .toLowerCase()
    .trim()
    .replace(/[^a-z0-9-]+/g, "-")
    .replace(/^-+|-+$/g, "")
    .slice(0, 48);
}

export async function createOrgAction(
  _prev: ActionState,
  formData: FormData,
): Promise<ActionState> {
  await requireSession();

  const slug = slugify(String(formData.get("slug") ?? ""));
  const name = String(formData.get("name") ?? "").trim() || slug;
  const handle = String(formData.get("handle") ?? "").trim();

  if (!slug || slug.length < 2) {
    return { error: "Choose an org slug with at least 2 characters." };
  }
  if (!handle || !handle.includes("@")) {
    return { error: "Handle must look like local@org." };
  }

  try {
    await createOrg({ slug, name, handle });
  } catch (err) {
    return { error: formatHubError(err) };
  }

  redirect("/dashboard");
}

export async function joinOrgAction(
  _prev: ActionState,
  formData: FormData,
): Promise<ActionState> {
  await requireSession();

  const invite_code = String(formData.get("invite_code") ?? "").trim();
  const handle = String(formData.get("handle") ?? "").trim();

  if (!invite_code) return { error: "Invite code is required." };
  if (!handle || !handle.includes("@")) {
    return { error: "Handle must look like local@org." };
  }

  try {
    await joinOrg({ invite_code, handle });
  } catch (err) {
    return { error: formatHubError(err) };
  }

  redirect("/dashboard");
}

export async function createInviteAction(
  _prev: ActionState,
  formData: FormData,
): Promise<ActionState> {
  await requireSession();

  const email = String(formData.get("email") ?? "").trim();

  try {
    const { invite } = await createInvite(email || undefined);
    const joinUrl = joinUrlForCode(invite.code);
    const inviteEmail = invite.email ?? (email || undefined);

    if (email) {
      const me = await getMe();
      const orgName = me.org?.name ?? me.org?.slug ?? "your team";
      const sent = await sendInviteEmail({
        to: email,
        orgName,
        joinUrl,
        inviteCode: invite.code,
      });

      if (!sent.ok) {
        return {
          ok: "Invite created. Email failed — copy the link below.",
          inviteCode: invite.code,
          inviteEmail,
          joinUrl,
          error: sent.error,
        };
      }

      if (sent.skipped) {
        return {
          ok: "Invite created.",
          inviteCode: invite.code,
          inviteEmail,
          joinUrl,
          emailSkipped: sent.reason,
        };
      }

      return {
        ok: `Invite created and emailed to ${email}.`,
        inviteCode: invite.code,
        inviteEmail,
        joinUrl,
      };
    }

    return {
      ok: "Invite created.",
      inviteCode: invite.code,
      inviteEmail,
      joinUrl,
    };
  } catch (err) {
    return { error: formatHubError(err) };
  }
}
