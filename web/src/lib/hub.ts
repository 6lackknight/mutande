import { auth0 } from "@/lib/auth0";
import {
  HubError,
  type CreateInviteResponse,
  type CreateOrgInput,
  type JoinOrgInput,
  type ListFeedbackResponse,
  type ListInvitesResponse,
  type ListWaitlistResponse,
  type MeResponse,
  type SeedProfileInput,
  type UpdateProfileInput,
} from "@/lib/types";

const DEFAULT_HUB = "https://hub.mutande.online";

export function hubBaseUrl(): string {
  return (process.env.MUTANDE_HUB_URL ?? DEFAULT_HUB).replace(/\/$/, "");
}

async function getBearerToken(): Promise<string> {
  const { token } = await auth0.getAccessToken();
  if (!token) {
    throw new HubError("No Auth0 access token — sign in again", 401);
  }
  return token;
}

async function hubFetch<T>(path: string, init: RequestInit = {}): Promise<T> {
  const token = await getBearerToken();
  const url = `${hubBaseUrl()}${path}`;

  let res: Response;
  try {
    res = await fetch(url, {
      ...init,
      headers: {
        Accept: "application/json",
        Authorization: `Bearer ${token}`,
        ...(init.body ? { "Content-Type": "application/json" } : {}),
        ...init.headers,
      },
      cache: "no-store",
    });
  } catch (err) {
    const message =
      err instanceof Error ? err.message : "Network error talking to hub";
    throw new HubError(
      `Hub unreachable (${hubBaseUrl()}): ${message}`,
      503,
    );
  }

  const text = await res.text();
  let body: unknown = null;
  if (text) {
    try {
      body = JSON.parse(text);
    } catch {
      body = text;
    }
  }

  if (!res.ok) {
    const detail =
      typeof body === "object" &&
      body !== null &&
      "error" in body &&
      typeof (body as { error: unknown }).error === "string"
        ? (body as { error: string }).error
        : typeof body === "object" &&
            body !== null &&
            "message" in body &&
            typeof (body as { message: unknown }).message === "string"
          ? (body as { message: string }).message
          : res.statusText || "Request failed";
    throw new HubError(detail, res.status, body);
  }

  return body as T;
}

export async function getMe(): Promise<MeResponse> {
  const raw = await hubFetch<MeResponse & { needs_onboarding?: boolean }>(
    "/v1/auth/me",
  );
  const onboarded =
    typeof raw.onboarded === "boolean"
      ? raw.onboarded
      : typeof raw.needs_onboarding === "boolean"
        ? !raw.needs_onboarding
        : Boolean(raw.user?.handle);
  return { ...raw, onboarded };
}

export async function updateProfile(
  input: UpdateProfileInput,
): Promise<MeResponse> {
  return hubFetch<MeResponse>("/v1/me/profile", {
    method: "PATCH",
    body: JSON.stringify(input),
  });
}

/** One-shot Auth0 → mutande seed (empty fields only). */
export async function seedProfile(
  input: SeedProfileInput = {},
): Promise<MeResponse> {
  return hubFetch<MeResponse>("/v1/me/profile/seed", {
    method: "POST",
    body: JSON.stringify(input),
  });
}

export async function createOrg(input: CreateOrgInput): Promise<MeResponse> {
  return hubFetch<MeResponse>("/v1/orgs", {
    method: "POST",
    body: JSON.stringify(input),
  });
}

export async function joinOrg(input: JoinOrgInput): Promise<MeResponse> {
  return hubFetch<MeResponse>("/v1/onboarding/join", {
    method: "POST",
    body: JSON.stringify(input),
  });
}

export async function listInvites(): Promise<ListInvitesResponse> {
  const data = await hubFetch<ListInvitesResponse | InviteLike[]>(
    "/v1/admin/invites",
  );
  if (Array.isArray(data)) {
    return { invites: data };
  }
  if (Array.isArray(data.invites)) {
    return data;
  }
  return { invites: [] };
}

export async function createInvite(email?: string): Promise<CreateInviteResponse> {
  return hubFetch<CreateInviteResponse>("/v1/admin/invites", {
    method: "POST",
    body: JSON.stringify(email ? { email } : {}),
  });
}

export async function listFeedback(): Promise<ListFeedbackResponse> {
  const data = await hubFetch<ListFeedbackResponse | ListFeedbackResponse["feedback"]>(
    "/v1/admin/feedback",
  );
  if (Array.isArray(data)) return { feedback: data };
  if (Array.isArray(data.feedback)) return data;
  return { feedback: [] };
}

export async function listWaitlistAdmin(): Promise<ListWaitlistResponse> {
  const data = await hubFetch<
    ListWaitlistResponse | ListWaitlistResponse["waitlist"]
  >("/v1/admin/waitlist");
  if (Array.isArray(data)) return { waitlist: data };
  if (Array.isArray(data.waitlist)) return data;
  return { waitlist: [] };
}

export async function listRegistryAdmin(): Promise<{
  listings: import("@/lib/types").RegistryListing[];
}> {
  return hubFetch("/v1/admin/registry");
}

export async function verifyRegistryListing(
  id: string,
  orgSlug?: string,
): Promise<{ listing: import("@/lib/types").RegistryListing }> {
  return hubFetch(`/v1/admin/registry/${id}/verify`, {
    method: "POST",
    body: JSON.stringify(orgSlug ? { org_slug: orgSlug } : {}),
  });
}

export async function publishRegistryListing(
  id: string,
): Promise<{ listing: import("@/lib/types").RegistryListing }> {
  return hubFetch(`/v1/admin/registry/${id}/publish`, { method: "POST" });
}

export async function suspendRegistryListing(
  id: string,
): Promise<{ listing: import("@/lib/types").RegistryListing }> {
  return hubFetch(`/v1/admin/registry/${id}/suspend`, { method: "POST" });
}

export async function topUpCredits(input: {
  org_id: string;
  amount_usd: string;
  note?: string;
}): Promise<{
  ledger: import("@/lib/types").BillingLedger;
}> {
  return hubFetch("/v1/admin/billing/credits", {
    method: "POST",
    body: JSON.stringify(input),
  });
}

export async function listEnterpriseMetrics(): Promise<{
  metrics: import("@/lib/types").EnterpriseDeliveryMetric[];
}> {
  return hubFetch("/v1/admin/enterprise/metrics?limit=100");
}

export function formatHubError(err: unknown): string {
  if (err instanceof HubError) {
    if (err.status === 503) {
      return `${err.message}. The hub may still be deploying Auth0 routes — UI will work once it lands.`;
    }
    return err.message;
  }
  if (err instanceof Error) return err.message;
  return "Something went wrong";
}

type InviteLike = ListInvitesResponse["invites"][number];
