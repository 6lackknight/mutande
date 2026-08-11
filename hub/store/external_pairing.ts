/**
 * L3 external contacts — PIN pairing, rate limits, blocks, ops flags (§6.2–6.6 / §13).
 */

import { HubError } from "./errors.ts";
import type {
  ExternalContactLink,
  PairRequest,
  PairingOpsFlag,
  PairingPin,
  PairingPinResponse,
} from "./types.ts";
import {
  EXTERNAL_LINK_MSGS_PER_DAY,
  PAIR_DENY_OPS_THRESHOLD,
  PAIR_DENY_OPS_WINDOW_MS,
  PAIR_PIN_LENGTH,
  PAIR_PIN_TTL_MS,
  PAIR_SUBMISSIONS_PER_REQUESTER_DAY,
  PAIR_SUBMISSIONS_PER_TARGET_DAY,
  PAIR_WRONG_PIN_LIMIT,
  PAIR_WRONG_PIN_LOCK_MS,
} from "./types.ts";

export const PAIRING_FAILED_MESSAGE = "Invalid handle or PIN";
export const PAIRING_RATE_LIMIT_MESSAGE = "Pairing temporarily unavailable";

export function pairingFailed(): HubError {
  return new HubError(PAIRING_FAILED_MESSAGE, "pairing_failed", 400);
}

export function pairingRateLimited(): HubError {
  return new HubError(PAIRING_RATE_LIMIT_MESSAGE, "pairing_rate_limited", 429);
}

export function pairingPinKey(userId: string): Deno.KvKey {
  return ["pairing_pins", userId];
}

export function pairRequestKey(id: string): Deno.KvKey {
  return ["pair_requests", id];
}

export function pairRequestsByTargetPrefix(targetUserId: string): Deno.KvKey {
  return ["pair_requests_by_target", targetUserId];
}

export function pairRequestByTargetKey(
  targetUserId: string,
  requestId: string,
): Deno.KvKey {
  return ["pair_requests_by_target", targetUserId, requestId];
}

export function pairRequestsByRequesterPrefix(requesterUserId: string): Deno.KvKey {
  return ["pair_requests_by_requester", requesterUserId];
}

export function pairRequestByRequesterKey(
  requesterUserId: string,
  requestId: string,
): Deno.KvKey {
  return ["pair_requests_by_requester", requesterUserId, requestId];
}

export function externalLinkKey(id: string): Deno.KvKey {
  return ["external_contacts", id];
}

export function externalLinkPairKey(userA: string, userB: string): Deno.KvKey {
  const [lo, hi] = userA < userB ? [userA, userB] : [userB, userA];
  return ["external_contact_pair", lo, hi];
}

export function externalLinksByUserPrefix(userId: string): Deno.KvKey {
  return ["external_contacts_by_user", userId];
}

export function externalLinkByUserKey(userId: string, linkId: string): Deno.KvKey {
  return ["external_contacts_by_user", userId, linkId];
}

export function pairBlockKey(blockerUserId: string, blockedHandle: string): Deno.KvKey {
  return ["pair_blocks", blockerUserId, blockedHandle.toLowerCase()];
}

export function pairFailureKey(
  requesterUserId: string,
  targetHandle: string,
): Deno.KvKey {
  return ["pair_failures", requesterUserId, targetHandle.toLowerCase()];
}

export function pairSubmitRequesterKey(requesterUserId: string, day: string): Deno.KvKey {
  return ["pair_submissions_requester", requesterUserId, day];
}

export function pairSubmitTargetKey(targetHandle: string, day: string): Deno.KvKey {
  return ["pair_submissions_target", targetHandle.toLowerCase(), day];
}

export function pairDenyKey(targetHandle: string, denyId: string): Deno.KvKey {
  return ["pair_denies", targetHandle.toLowerCase(), denyId];
}

export function pairDeniesPrefix(targetHandle: string): Deno.KvKey {
  return ["pair_denies", targetHandle.toLowerCase()];
}

export function pairingOpsFlagKey(id: string): Deno.KvKey {
  return ["pairing_ops_flags", id];
}

export function pairingOpsFlagsPrefix(): Deno.KvKey {
  return ["pairing_ops_flags"];
}

export function externalLinkMsgCountKey(linkId: string, day: string): Deno.KvKey {
  return ["external_link_msgs", linkId, day];
}

export function utcDay(iso = new Date().toISOString()): string {
  return iso.slice(0, 10);
}

export function generateSixDigitPin(): string {
  const buf = new Uint32Array(1);
  crypto.getRandomValues(buf);
  const n = buf[0]! % 1_000_000;
  return String(n).padStart(PAIR_PIN_LENGTH, "0");
}

export function buildPairingQrUri(handle: string, pin: string): string {
  const q = new URLSearchParams({ handle, pin });
  return `mutande://pair?${q.toString()}`;
}

export function toPairingPinResponse(pin: PairingPin): PairingPinResponse {
  return {
    pin: pin.pin,
    handle: pin.handle,
    expires_at: pin.expires_at,
    qr_uri: buildPairingQrUri(pin.handle, pin.pin),
  };
}

export function issuePairingPinRecord(
  userId: string,
  handle: string,
  now = new Date(),
): PairingPin {
  const created_at = now.toISOString();
  return {
    user_id: userId,
    handle,
    pin: generateSixDigitPin(),
    created_at,
    expires_at: new Date(now.getTime() + PAIR_PIN_TTL_MS).toISOString(),
  };
}

export function pinIsValid(pin: PairingPin | null, now = new Date()): boolean {
  if (!pin) return false;
  return Date.parse(pin.expires_at) > now.getTime();
}

export interface PairFailureState {
  count: number;
  locked_until?: string;
  updated_at: string;
}

export function isPairLocked(
  state: PairFailureState | null,
  now = new Date(),
): boolean {
  if (!state?.locked_until) return false;
  return Date.parse(state.locked_until) > now.getTime();
}

export function recordWrongPin(
  prev: PairFailureState | null,
  now = new Date(),
): PairFailureState {
  const count = (prev?.count ?? 0) + 1;
  const updated_at = now.toISOString();
  if (count >= PAIR_WRONG_PIN_LIMIT) {
    return {
      count,
      updated_at,
      locked_until: new Date(now.getTime() + PAIR_WRONG_PIN_LOCK_MS).toISOString(),
    };
  }
  return { count, updated_at, locked_until: prev?.locked_until };
}

export function clearPairFailures(): PairFailureState {
  return { count: 0, updated_at: new Date().toISOString() };
}

export function assertUnderDailyCap(count: number, limit: number): void {
  if (count >= limit) throw pairingRateLimited();
}

export {
  EXTERNAL_LINK_MSGS_PER_DAY,
  PAIR_DENY_OPS_THRESHOLD,
  PAIR_DENY_OPS_WINDOW_MS,
  PAIR_PIN_LENGTH,
  PAIR_PIN_TTL_MS,
  PAIR_SUBMISSIONS_PER_REQUESTER_DAY,
  PAIR_SUBMISSIONS_PER_TARGET_DAY,
  PAIR_WRONG_PIN_LIMIT,
  PAIR_WRONG_PIN_LOCK_MS,
};

export type {
  ExternalContactLink,
  PairRequest,
  PairingOpsFlag,
  PairingPin,
  PairingPinResponse,
};
