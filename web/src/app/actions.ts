"use server";

import { redirect } from "next/navigation";
import {
  createInvite,
  createOrg,
  denyPairRequest,
  formatHubError,
  getMe,
  issuePairingPin,
  joinOrg,
  listEnterpriseMetrics,
  listFeedback,
  listOpsCensus,
  listRegistryAdmin,
  listWaitlistAdmin,
  publishRegistryListing,
  rotatePairingPin,
  submitPairRequest,
  suspendRegistryListing,
  topUpCredits,
  unpairExternalContact,
  updateOrg,
  updateProfile,
  verifyRegistryListing,
  approvePairRequest,
} from "@/lib/hub";
import { sendInviteEmail } from "@/lib/plunk";
import { joinUrlForCode, requireSession } from "@/lib/session";
import type { Feedback, OpsCensus, WaitlistEntry } from "@/lib/types";

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

export async function updateProfileAction(
  _prev: ActionState,
  formData: FormData,
): Promise<ActionState> {
  await requireSession("/profile");

  const display_name = String(formData.get("display_name") ?? "").trim();
  if (display_name.length > 128) {
    return { error: "Name is too long (max 128 characters)." };
  }

  const handleLocal = String(formData.get("handle_local") ?? "").trim().toLowerCase();
  if (!handleLocal) {
    return { error: "Handle is required." };
  }
  if (!/^[a-z0-9](?:[a-z0-9._-]{0,126}[a-z0-9])?$/.test(handleLocal)) {
    return {
      error:
        "Handle must be 1–128 lowercase letters, digits, dots, underscores, or hyphens.",
    };
  }

  const input: {
    display_name: string;
    handle: string;
    avatar_url?: string;
  } = {
    display_name,
    handle: handleLocal,
  };
  // Hidden field is only submitted when the avatar changed; empty string clears.
  const avatar = formData.get("avatar_url");
  if (typeof avatar === "string") {
    input.avatar_url = avatar;
  }

  try {
    await updateProfile(input);
  } catch (err) {
    return { error: formatHubError(err) };
  }

  return { ok: "Profile saved." };
}

export async function updateOrgSlugAction(
  _prev: ActionState,
  formData: FormData,
): Promise<ActionState> {
  await requireSession("/admin/invites");

  const slug = slugify(String(formData.get("slug") ?? ""));
  if (!slug || slug.length < 2) {
    return { error: "Choose an org slug with at least 2 characters." };
  }

  try {
    await updateOrg({ slug });
  } catch (err) {
    return { error: formatHubError(err) };
  }

  return { ok: "Organization handle updated." };
}

export async function issuePairingPinAction(
  _prev: ActionState,
  _formData: FormData,
): Promise<ActionState> {
  await requireSession("/contacts");
  try {
    await issuePairingPin();
  } catch (err) {
    return { error: formatHubError(err) };
  }
  return { ok: "Pairing PIN created." };
}

export async function rotatePairingPinAction(
  _prev: ActionState,
  _formData: FormData,
): Promise<ActionState> {
  await requireSession("/contacts");
  try {
    await rotatePairingPin();
  } catch (err) {
    return { error: formatHubError(err) };
  }
  return { ok: "Pairing PIN rotated." };
}

export async function submitPairRequestAction(
  _prev: ActionState,
  formData: FormData,
): Promise<ActionState> {
  await requireSession("/contacts");

  const handle = String(formData.get("handle") ?? "").trim().toLowerCase();
  const pin = String(formData.get("pin") ?? "").trim();
  const intro = String(formData.get("intro") ?? "").trim();

  if (!handle.includes("@")) {
    return { error: "Enter their full handle (local@org)." };
  }
  if (!/^\d{6}$/.test(pin)) {
    return { error: "PIN must be exactly 6 digits." };
  }

  try {
    await submitPairRequest({
      handle,
      pin,
      ...(intro ? { intro } : {}),
    });
  } catch (err) {
    return { error: formatHubError(err) };
  }

  return { ok: "Pairing request sent — waiting for approval." };
}

export async function approvePairRequestAction(
  _prev: ActionState,
  formData: FormData,
): Promise<ActionState> {
  await requireSession("/contacts");
  const requestId = String(formData.get("request_id") ?? "").trim();
  if (!requestId) return { error: "Missing request." };
  try {
    await approvePairRequest(requestId);
  } catch (err) {
    return { error: formatHubError(err) };
  }
  return { ok: "Contact connected." };
}

export async function denyPairRequestAction(
  _prev: ActionState,
  formData: FormData,
): Promise<ActionState> {
  await requireSession("/contacts");
  const requestId = String(formData.get("request_id") ?? "").trim();
  if (!requestId) return { error: "Missing request." };
  try {
    await denyPairRequest(requestId);
  } catch (err) {
    return { error: formatHubError(err) };
  }
  return { ok: "Request denied." };
}

export async function unpairExternalContactAction(
  _prev: ActionState,
  formData: FormData,
): Promise<ActionState> {
  await requireSession("/contacts");
  const linkId = String(formData.get("link_id") ?? "").trim();
  if (!linkId) return { error: "Missing contact." };
  try {
    await unpairExternalContact(linkId);
  } catch (err) {
    return { error: formatHubError(err) };
  }
  return { ok: "Contact removed." };
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

export async function refreshOpsAction(): Promise<{
  feedback?: Feedback[];
  waitlist?: WaitlistEntry[];
  listings?: import("@/lib/types").RegistryListing[];
  metrics?: import("@/lib/types").EnterpriseDeliveryMetric[];
  census?: OpsCensus;
  error?: string;
}> {
  await requireSession("/admin/ops");
  try {
    const [fb, wl, reg, metrics, census] = await Promise.all([
      listFeedback(),
      listWaitlistAdmin(),
      listRegistryAdmin().catch(() => ({ listings: [] })),
      listEnterpriseMetrics().catch(() => ({ metrics: [] })),
      listOpsCensus().catch(() => undefined),
    ]);
    return {
      feedback: fb.feedback,
      waitlist: wl.waitlist,
      listings: reg.listings,
      metrics: metrics.metrics,
      census,
    };
  } catch (err) {
    return { error: formatHubError(err) };
  }
}

export async function opsVerifyListingAction(
  id: string,
): Promise<{ listing?: import("@/lib/types").RegistryListing; error?: string }> {
  await requireSession("/admin/ops");
  try {
    const { listing } = await verifyRegistryListing(id);
    return { listing };
  } catch (err) {
    return { error: formatHubError(err) };
  }
}

export async function opsPublishListingAction(
  id: string,
): Promise<{ listing?: import("@/lib/types").RegistryListing; error?: string }> {
  await requireSession("/admin/ops");
  try {
    const { listing } = await publishRegistryListing(id);
    return { listing };
  } catch (err) {
    return { error: formatHubError(err) };
  }
}

export async function opsSuspendListingAction(
  id: string,
): Promise<{ listing?: import("@/lib/types").RegistryListing; error?: string }> {
  await requireSession("/admin/ops");
  try {
    const { listing } = await suspendRegistryListing(id);
    return { listing };
  } catch (err) {
    return { error: formatHubError(err) };
  }
}

export async function opsTopUpCreditsAction(input: {
  org_id: string;
  amount_usd: string;
  note?: string;
}): Promise<{ balance_cents?: number; error?: string }> {
  await requireSession("/admin/ops");
  try {
    const { ledger } = await topUpCredits(input);
    return { balance_cents: ledger.balance_cents };
  } catch (err) {
    return { error: formatHubError(err) };
  }
}
