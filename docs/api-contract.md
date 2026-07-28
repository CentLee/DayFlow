# DayFlow API Contract

Base path: `/v1`

Authentication: opaque DayFlow bearer session established from a Google ID
token. Google Sign-In is identity-only; the server does not request Google
Calendar scopes or retain Google tokens.

## Service Boundary

- The API and PostgreSQL run on the owner's iMac.
- Both iPhones reach the API only through the iMac's private Tailscale
  MagicDNS name.
- The API must not advertise or depend on a public URL, purchased domain, public
  reverse proxy, or internet-facing listener.
- PostgreSQL is not exposed to either phone; only the API accesses it.
- The iMac is authoritative but not assumed continuously available. Clients may
  read confirmed local cache data and enqueue supported mutations while it is
  unreachable.

## Auth

### `POST /auth/google/exchange`

Validates a Google ID token, checks its stable subject against the deployment's
exact two-entry allowlist, provisions deployment-owned resources if needed, and
returns a DayFlow session.

Request:

```json
{
  "id_token": "google-id-token",
  "device_id": "ios-installation-uuid"
}
```

Response:

```json
{
  "user": {
    "id": "usr_123",
    "email": "owner@example.com",
    "display_name": "DayFlow Owner",
    "household_role": "owner"
  },
  "token": "opaque-dayflow-session-token",
  "expires_at": "2026-08-27T00:00:00Z"
}
```

Validation requirements:

- verify Google signature, issuer, configured iOS audience, expiry, and
  `email_verified`
- resolve authorization by the stable `sub`
- require the normalized email to match the configured guard for that subject
- accept only the enabled `owner` or `partner` entry
- create no application data for rejected or mismatched identities
- discard the Google ID token after validation and never persist Google access
  or refresh tokens
- issue an opaque, revocable DayFlow session scoped to the matched user

Status codes:

- `200`: accepted and session established
- `401 google_token_invalid`: token validation failed
- `403 identity_not_allowlisted`: subject or email guard did not match
- `503 deployment_not_ready`: the allowlist does not contain exactly one owner
  and one partner

### `POST /auth/logout`

Revokes the current DayFlow bearer session. It has no effect on the person's
Google account.

Response:

```json
{
  "revoked": true
}
```

### `GET /me`

Returns the authenticated user, that user's personal calendar, the
pre-provisioned household calendar, and role-gated routing metadata.

Owner response:

```json
{
  "user": {
    "id": "usr_001",
    "email": "owner@example.com",
    "display_name": "DayFlow Owner",
    "household_role": "owner"
  },
  "personal_calendar": {
    "id": "cal_001",
    "kind": "personal",
    "name": "Personal",
    "color": "#1F6B5C",
    "updated_at": "2026-03-17T00:00:00Z"
  },
  "household_calendar": {
    "id": "cal_household",
    "kind": "household",
    "name": "Household",
    "color": "#D8A21D",
    "updated_at": "2026-03-17T00:00:00Z"
  },
  "budget_access": "owner",
  "current_budget_month_key": "2026-03",
  "sync_cursor": "cursor_123"
}
```

Partner response:

```json
{
  "user": {
    "id": "usr_002",
    "email": "partner@example.com",
    "display_name": "DayFlow Partner",
    "household_role": "partner"
  },
  "personal_calendar": {
    "id": "cal_002",
    "kind": "personal",
    "name": "Personal",
    "color": "#5B7FFF",
    "updated_at": "2026-03-17T00:00:00Z"
  },
  "household_calendar": {
    "id": "cal_household",
    "kind": "household",
    "name": "Household",
    "color": "#D8A21D",
    "updated_at": "2026-03-17T00:00:00Z"
  },
  "budget_access": "none",
  "sync_cursor": "cursor_456"
}
```

Notes:

- `/me` is the bootstrap source for identity, calendar routing, and cache scope
- `personal_calendar` is singular and always belongs to the session user
- `household_calendar` is singular and provisioned by deployment
- the partner payload omits `current_budget_month_key` and all budget data
- auth responses do not inline calendar events or budget-month payloads

## Calendars

### `GET /calendars`

Returns exactly the caller's personal calendar and the household calendar.

Response:

```json
{
  "items": [
    {
      "id": "cal_001",
      "kind": "personal",
      "name": "Personal",
      "color": "#1F6B5C",
      "updated_at": "2026-03-17T00:00:00Z"
    },
    {
      "id": "cal_household",
      "kind": "household",
      "name": "Household",
      "color": "#D8A21D",
      "updated_at": "2026-03-17T00:00:00Z"
    }
  ]
}
```

Notes:

- the other person's personal calendar is never returned
- this endpoint is canonical for calendar refresh; `/me` may seed the same two
  summaries during bootstrap
- calendar payloads never include budget fields

There is no calendar create, invite, invite-acceptance, membership, or
role-management endpoint in the target contract.

### Offline Mutation Rules

Event writes include a client-generated `client_mutation_id`. Updates and
deletes also include the last confirmed `base_updated_at`. The server:

- authorizes every replay against the current session
- returns the already-applied result for a repeated mutation ID
- returns `409 conflict` plus the current server resource when
  `base_updated_at` is stale
- retains deletion tombstones in the change feed long enough for both phones to
  observe them

### `GET /calendars/{id}/events`

Query params:

- `from`
- `to`

Response:

```json
{
  "items": [
    {
      "id": "evt_001",
      "calendar_id": "cal_household",
      "title": "보험비 정산",
      "notes": "25일 기준 확인",
      "starts_at": "2026-03-25T09:00:00Z",
      "ends_at": "2026-03-25T09:30:00Z",
      "all_day": false,
      "updated_at": "2026-03-17T00:00:00Z"
    }
  ]
}
```

### `POST /calendars/{id}/events`

Request:

```json
{
  "title": "보험비 정산",
  "notes": "25일 기준 확인",
  "starts_at": "2026-03-25T09:00:00Z",
  "ends_at": "2026-03-25T09:30:00Z",
  "all_day": false,
  "client_mutation_id": "mut_device_a_001"
}
```

### `POST /events/{id}/transfer`

Copies or moves the caller's personal event into the household calendar without
changing the personal calendar itself.

Request:

```json
{
  "target_calendar_id": "cal_household",
  "mode": "copy",
  "base_updated_at": "2026-03-17T00:00:00Z",
  "client_mutation_id": "mut_device_a_002"
}
```

Response:

```json
{
  "source_event_id": "evt_001",
  "target_event": {
    "id": "evt_101",
    "calendar_id": "cal_household",
    "title": "보험비 정산",
    "notes": "25일 기준 확인",
    "starts_at": "2026-03-25T09:00:00Z",
    "ends_at": "2026-03-25T09:30:00Z",
    "all_day": false,
    "updated_at": "2026-03-17T00:00:00Z"
  }
}
```

### `PATCH /events/{id}`

Request:

```json
{
  "title": "보험비 정산",
  "notes": "입금 후 확인",
  "starts_at": "2026-03-25T09:00:00Z",
  "ends_at": "2026-03-25T09:30:00Z",
  "all_day": false,
  "base_updated_at": "2026-03-17T00:00:00Z",
  "client_mutation_id": "mut_device_a_003"
}
```

### `DELETE /events/{id}`

Request body:

```json
{
  "base_updated_at": "2026-03-17T00:00:00Z",
  "client_mutation_id": "mut_device_a_004"
}
```

### `GET /sync/changes`

Query params:

- `cursor` (omit for the first identity bootstrap)

Returns authorized calendar changes and, for the owner only, owner-budget
changes after the cursor. The partner feed contains no budget scope, identifiers,
or placeholders.

```json
{
  "changes": [
    {
      "resource_type": "event",
      "operation": "upsert",
      "resource": {
        "id": "evt_101",
        "calendar_id": "cal_household",
        "updated_at": "2026-03-17T00:00:00Z"
      }
    }
  ],
  "next_cursor": "cursor_789",
  "has_more": false
}
```

## Budget

Every budget endpoint requires `household_role = owner`. The partner receives
`403 budget_owner_only`; the server does not resolve or serialize an expense
book before that role check.

### `GET /budget/months/{yyyy-mm}`

Returns the full month board in one call.

Current KPI derivation assumptions:

- `base_budget_amount`, `current_cash_amount`, `saving_amount`, and `carry_over_amount` are manual month inputs
- `fixed_cost_total` is the sum of enabled `fixed_items[].amount`
- `variable_bucket_total` is the sum of `variable_buckets[].planned_amount`
- `free_cash_amount` is `current_cash_amount - enabled fixed item amounts - variable_buckets[].actual_amount`
- `remaining_budget_amount` is `base_budget_amount - fixed_cost_total - saving_amount - variable_bucket_total + carry_over_amount`
- `billing_reminders` and `formula_hint` are informational and do not affect KPI math

Worked example for the response below:

- `fixed_cost_total = 21 + 36 + 8 + 88 = 153`
- `variable_bucket_total = 12 + 0 = 12`
- `free_cash_amount = 118 - 153 - (0 + 0) = -35`
- `remaining_budget_amount = 510 - 153 - 200 - 12 + 0 = 145`

Response shape:

```json
{
  "month": {
    "id": "bmon_001",
    "month_key": "2026-03",
    "base_budget_amount": 510,
    "current_cash_amount": 118,
    "saving_amount": 200,
    "carry_over_amount": 0,
    "remaining_budget_amount": 145,
    "updated_at": "2026-03-17T00:00:00Z"
  },
  "summary": {
    "fixed_cost_total": 153,
    "variable_bucket_total": 12,
    "free_cash_amount": -35
  },
  "fixed_items": [
    {
      "id": "bitm_001",
      "name": "월세 및 관리비",
      "kind": "fixed",
      "amount": 21,
      "enabled": true,
      "billing_day_label": "20일",
      "updated_at": "2026-03-17T00:00:00Z"
    },
    {
      "id": "bitm_002",
      "name": "대출이자",
      "kind": "fixed",
      "amount": 36,
      "enabled": true,
      "billing_day_label": "5일",
      "updated_at": "2026-03-17T00:00:00Z"
    },
    {
      "id": "bitm_003",
      "name": "핸드폰요금",
      "kind": "fixed",
      "amount": 8,
      "enabled": true,
      "billing_day_label": "15일",
      "updated_at": "2026-03-17T00:00:00Z"
    },
    {
      "id": "bitm_004",
      "name": "신용카드",
      "kind": "fixed",
      "amount": 88,
      "enabled": true,
      "billing_day_label": "26일",
      "updated_at": "2026-03-17T00:00:00Z"
    }
  ],
  "variable_buckets": [
    {
      "id": "bkt_001",
      "name": "점심 및 주말 식대",
      "planned_amount": 12,
      "actual_amount": 0,
      "formula_hint": "평일 1 + 주말 3",
      "updated_at": "2026-03-17T00:00:00Z"
    },
    {
      "id": "bkt_002",
      "name": "유동 금액",
      "planned_amount": 0,
      "actual_amount": 0,
      "updated_at": "2026-03-17T00:00:00Z"
    }
  ],
  "billing_reminders": [
    {
      "id": "rem_001",
      "name": "인터넷",
      "kind": "reminder",
      "amount": 0,
      "enabled": false,
      "billing_day_label": "25일",
      "updated_at": "2026-03-17T00:00:00Z"
    },
    {
      "id": "rem_002",
      "name": "전기 정산",
      "kind": "reminder",
      "amount": 0,
      "enabled": false,
      "billing_day_label": "월말일",
      "updated_at": "2026-03-17T00:00:00Z"
    }
  ]
}
```

### `PUT /budget/months/{yyyy-mm}`

Upserts the owner's month board. The client sends the full edited shape plus:

```json
{
  "base_updated_at": "2026-03-17T00:00:00Z",
  "client_mutation_id": "mut_owner_phone_005"
}
```

Current MVP contract rules:

- the request is a current-month snapshot write, not a template update
- retrying the same `client_mutation_id` returns the prior applied result
- a stale `base_updated_at` returns `409 conflict` with the current server board;
  the server does not silently merge month snapshots
- clients should treat KPI summary values as derived from the submitted month data rather than as authoritative write inputs
- the server recalculates `fixed_cost_total`, `variable_bucket_total`, `free_cash_amount`, and `remaining_budget_amount` on every save and ignores conflicting submitted summary values
- `fixed_items` are month-entry values; clients may edit fields such as `enabled`, `amount`, and notes while preserving template-owned structure fields
- `variable_buckets` are month-entry values; clients may edit planned and actual amounts while preserving template-owned structure fields
- `billing_reminders` are informational metadata for budget planning and do not create calendar events or notifications

### `GET /budget/templates`

Returns the owner-scoped fixed-item template defaults used to seed future month boards.

Response shape:

```json
{
  "fixed_items": [
    {
      "id": "tmpl_123",
      "name": "월세 및 관리비",
      "kind": "fixed",
      "default_amount": 21,
      "default_enabled": true,
      "default_note": "",
      "default_billing_day": "20일",
      "sort_order": 0,
      "updated_at": "2026-03-17T00:00:00Z"
    }
  ]
}
```

### `PUT /budget/templates`

Replaces the owner-scoped fixed-item template list for MVP. Writes use the same
`base_updated_at` and `client_mutation_id` concurrency rules as month writes.

Current MVP contract rules:

- the request is a full template-set write for simplicity
- only owner-scoped fixed-item templates are editable in this endpoint
- future unsaved month boards use the updated defaults
- existing month snapshots do not change when template defaults change

## Error Model

```json
{
  "error": {
    "code": "forbidden",
    "message": "calendar access denied"
  }
}
```

## Contract Rules

- Every mutable resource returns `updated_at`
- Calendar responses exclude private budget fields
- Budget responses and sync changes are owner-only
- The iOS client should be able to render the budget screen from one budget-month response
- Auth and calendar payloads use snake_case JSON keys over the wire
- `/me` returns role-gated bootstrap data, while `/calendars` returns exactly the
  caller's personal calendar and the household calendar
- personal calendars are never shared; the deployment-provisioned household
  calendar is the only calendar with members
- no endpoint supports registration, password login, invitations, arbitrary
  calendar creation, membership changes, or role changes
- all remote requests arrive through the iMac's Tailscale MagicDNS base URL;
  no public base URL is part of this contract

## Legacy Migration Targets

`POST /auth/register`, `POST /auth/login`, password credentials and recovery,
calendar creation, invite creation and acceptance, membership or role changes,
and every public/custom-domain ingress path are legacy migration targets. They
are not target endpoints and must not be retained as compatibility behavior.

Migration removes or disables those paths only after the two Google subjects,
fixed calendar topology, iOS client cutover, and a restorable database backup
have been verified. Google Calendar synchronization is neither a migration
path nor a target capability.
