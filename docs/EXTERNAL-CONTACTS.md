# L3 External contacts (cross-org pairing)

Implements directory.prd §§6.2–6.6, 6.3.1, 7.1, 13.

## Hub API

| Method | Path | Notes |
|--------|------|--------|
| GET | `/v1/contacts` | Same-org + broadcast (`kind: org\|broadcast`) |
| GET | `/v1/contacts/external` | Approved bilateral external contacts |
| DELETE | `/v1/contacts/external/:linkId` | Unpair; closes shared threads read-only |
| POST | `/v1/contacts/pairing/pin` | Issue 6-digit PIN (7-day TTL) + `qr_uri` |
| GET | `/v1/contacts/pairing/pin` | Current PIN or `{ pin: null }` |
| POST | `/v1/contacts/pairing/pin/rotate` | Invalidate + re-issue |
| POST | `/v1/contacts/pairing/request` | `{ handle, pin, intro? }` → pending request |
| GET | `/v1/contacts/pairing/pending` | `{ incoming, outgoing }` |
| POST | `/v1/contacts/pairing/:id/approve` | Bilateral link + connection ping thread |
| POST | `/v1/contacts/pairing/:id/deny` | Per-user block; ops flag at ≥5 denies/7d |
| GET | `/v1/admin/pairing-flags` | Ops SuperAdmin harassment signals |

Auth: same Auth0 Bearer as other `/v1/*` routes.

### Rate limits (§13)

- 5 wrong PIN → 1h lock per requester→target pair
- 10 submissions/day/requester · 20/day/target handle
- Uniform error `pairing_failed` / “Invalid handle or PIN” (no handle enumeration)
- 200 messages/day/external link velocity

### Routing

Cross-org `createThread` requires an approved external link; thread gets
`encryption_mode: "app_envelope"`, `external_link_id`, `participant_user_ids`.
Uses the L2 app_envelope store for connection-ping + subsequent external mail.

## Daemon RPC

`list_external_contacts`, `issue_pairing_pin`, `get_pairing_pin`,
`rotate_pairing_pin`, `submit_pair_request`, `list_pending_pair_requests`,
`approve_pair_request`, `deny_pair_request`, `unpair_external_contact`.

## Flutter

Contacts tab → **External** section: Share PIN (QR), Add (handle+PIN),
Approve/Deny pending, Message / Remove linked contacts.

## Tests

`hub/store/external_contacts_test.ts` — PIN, rotate, uniform errors, lockout,
approve+ping, deny block, unpair, ops flags.
