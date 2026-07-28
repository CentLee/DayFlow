# DayFlow Sync Model

## Scope and Authority

- PostgreSQL on the owner's iMac is authoritative.
- Both iPhones contact the API only at the iMac's Tailscale MagicDNS name.
- The iMac can be unavailable; the client may render last-confirmed data and
  queue supported writes for later reconciliation.
- Google Sign-In is used only to establish DayFlow identity. No Google Calendar
  data, scope, token, or Google sync participates in this model.
- Cache, session, cursor, and mutation records are partitioned by the
  authenticated Google subject/DayFlow user. Signing out or changing identity
  removes that identity's local cache and pending mutations.

## Bootstrap and Reconciliation

When online, the iOS client:

1. exchanges a Google ID token at `POST /v1/auth/google/exchange` and stores
   only the returned revocable DayFlow session;
2. fetches `GET /v1/me` to establish the identity, two allowed calendar
   summaries, role-gated cache scope, and cursor;
3. fetches `GET /v1/calendars` and the visible event ranges, replacing stale
   cache entries with authorized server records;
4. only when `/me` declares `budget_access: "owner"`, fetches the current
   `GET /v1/budget/months/{yyyy-mm}` board; and
5. records the returned cursor, then consumes `GET /v1/sync/changes` until
   `has_more` is false.

On reconnect, the client first validates its DayFlow session, pulls changes
from its last confirmed cursor, replays its outbox in creation order, resolves
any conflict, and pulls changes again. A rejected identity or expired session
does not replay anything.

The partner never calls budget endpoints, never creates an owner-budget cache
or outbox, and never receives budget changes, identifiers, or placeholders in
`/sync/changes`.

## Local State and Outbox

- The cache contains only the caller's personal calendar and the household
  calendar; it never stores the other person's personal calendar.
- Cached data is last-confirmed server data plus visibly marked pending local
  overlays.
- Each queued mutation has a stable `client_mutation_id`, resource type,
  payload, last confirmed `base_updated_at` where required, and retry state.
- Retrying the same mutation ID is safe: the server returns the already-applied
  result rather than applying it twice.
- Pending work is retained across temporary offline periods, but is removed on
  successful acknowledgement, explicit discard, sign-out, or identity change.
- The client must not synthesize a successful server timestamp or cursor for a
  pending overlay.

Supported offline mutations are event create, update, delete, explicit
personal-to-household copy/move, and owner budget-month/template writes.
Authentication, calendar provisioning, membership, role, invite, and public
ingress changes are never client-side offline actions.

## Calendar Reconciliation

- `GET /calendars` returns exactly the caller's personal calendar and the
  pre-provisioned household calendar.
- Event creates are idempotent by `client_mutation_id`.
- Event updates, deletes, copies, and moves carry `base_updated_at` from the
  last confirmed event version.
- If `base_updated_at` is current, the server applies the mutation and returns
  the authoritative resource. If stale, it returns `409 conflict` with the
  current resource or tombstone; the client keeps the local draft visibly
  pending for explicit retry, discard, or user re-edit.
- There is no silent last-write-wins overwrite for stale event edits.
- A copy leaves the personal source unchanged and creates a household event.
  A move creates the household event first and deletes the personal source only
  after that target write is accepted atomically by the server.
- Deletions appear as tombstones in `/sync/changes` until both device cursors
  can reasonably observe them; a tombstone removes cached data and cannot be
  resurrected by an older queued mutation.

## Budget Reconciliation

- Only the owner has a budget board, cache, mutations, and budget change-feed
  scope.
- The client calculates KPI previews locally using the contract formulas, but
  the server recalculates all derived values and is final.
- A month or template write carries `base_updated_at` and
  `client_mutation_id`; retrying it is idempotent.
- If the board version is stale, the server returns `409 conflict` with the
  current full board. The client does not merge snapshots or derived KPI fields
  automatically; it preserves the pending edits for an explicit rebase, retry,
  or discard.
- A confirmed response replaces the local board and clears the acknowledged
  pending overlay.

## Failure and Privacy Rules

- Network, sleep, or Tailscale reachability failure leaves confirmed cache
  readable and marks affected writes pending; it does not log the person out.
- `401` clears the DayFlow session and stops replay. `403` removes inaccessible
  pending data and does not reveal whether another user's resource exists.
- A budget `403 budget_owner_only` is a privacy boundary, not an empty-board
  response.
- The API reauthorizes every replay against the current session and current
  fixed calendar topology.
- No local state or reconciliation path can create a third user, a new calendar,
  a calendar membership, a Google Calendar connection, or public ingress.

## Legacy Migration Targets

Password/register/login sessions, invite acceptance, arbitrary membership and
shared-calendar sync, and public/custom-domain transport are legacy migration
inputs only. They are not fallback bootstrap or reconciliation behavior. The
cutover starts from the fixed two-identity Google exchange and Tailscale
MagicDNS path; legacy records are retired only after backup and data-mapping
verification.
