# DayFlow API Contract Draft

Base path: `/v1`

Authentication: bearer token

## Auth

### `POST /auth/register`

Creates an invited account and returns the session token.

Request:

```json
{
  "email": "user@example.com",
  "display_name": "Kakao",
  "password": "secret1234",
  "invite_code": "invite_abc"
}
```

Response:

```json
{
  "user": {
    "id": "usr_123",
    "email": "user@example.com",
    "display_name": "Kakao"
  },
  "token": "jwt-or-session-token"
}
```

### `POST /auth/login`

Returns the session token for an existing account.

Request:

```json
{
  "email": "user@example.com",
  "password": "secret1234"
}
```

Response:

```json
{
  "user": {
    "id": "usr_123",
    "email": "user@example.com",
    "display_name": "Kakao"
  },
  "token": "jwt-or-session-token"
}
```

### `GET /me`

Returns current user, the default personal calendar, joined shared calendars, and current budget month key.

Response:

```json
{
  "user": {
    "id": "usr_001",
    "email": "owner@dayflow.local",
    "display_name": "DayFlow Owner"
  },
  "personal_calendar": {
    "id": "cal_001",
    "kind": "personal",
    "name": "Personal",
    "color": "#1F6B5C",
    "updated_at": "2026-03-17T00:00:00Z"
  },
  "shared_calendars": [],
  "current_budget_month_key": "2026-03"
}
```

Notes:

- auth responses stay minimal for MVP and do not inline calendar or budget payloads
- `/me` is the bootstrap source for session user data and current month routing
- `personal_calendar` is always singular in MVP and is automatically provisioned for each account
- current memory mocks return the owner view above for the seeded owner account

Invited collaborator example:

```json
{
  "user": {
    "id": "usr_005",
    "email": "user@example.com",
    "display_name": "Kakao"
  },
  "personal_calendar": {
    "id": "cal_101",
    "kind": "personal",
    "name": "Personal",
    "color": "#5B7FFF",
    "updated_at": "2026-03-17T00:00:00Z"
  },
  "shared_calendars": [
    {
      "id": "cal_002",
      "kind": "shared",
      "name": "Shared Home",
      "color": "#D8A21D",
      "updated_at": "2026-03-17T00:00:00Z"
    }
  ],
  "current_budget_month_key": "2026-03"
}
```

Notes:

- invited collaborators always keep their own personal calendar and do not receive budget data from anyone else
- the collaborator example is the intended grouped shape for session bootstrap after invite registration/login

## Calendars

### `GET /calendars`

Returns the current flat calendar list used for the shared calendar tab and calendar pickers.

Response:

```json
{
  "items": [
    {
      "id": "cal_001",
      "kind": "shared",
      "name": "Shared Home",
      "color": "#D8A21D",
      "updated_at": "2026-03-17T00:00:00Z",
      "membership_role": "owner"
    }
  ]
}
```

Notes:

- personal calendar bootstrap stays in `/me` and does not need to be duplicated in the shared calendar tab payload
- the list stays budget-free even when a calendar is shared

### `POST /calendars`

Creates a shared calendar.

Request:

```json
{
  "name": "Shared Home",
  "color": "#5B7FFF"
}
```

Response:

```json
{
  "id": "cal_003",
  "kind": "shared",
  "name": "Shared Home",
  "color": "#5B7FFF",
  "updated_at": "2026-03-17T00:00:00Z"
}
```

### `POST /calendars/{id}/invites`

Creates or reuses an invite for a target email.

Request:

```json
{
  "email": "friend@example.com",
  "delivery_channel": "sms",
  "role": "editor"
}
```

Response:

```json
{
  "id": "cinv_123",
  "calendar_id": "cal_002",
  "email": "friend@example.com",
  "delivery_channel": "sms",
  "role": "editor",
  "invite_code": "invite_abc",
  "invite_url": "https://dayflow.local/invites/invite_abc",
  "updated_at": "2026-03-17T00:00:00Z"
}
```

### `GET /invites/{invite_code}`

Returns invite preview data for an emailed or texted link before acceptance.

Response:

```json
{
  "invite": {
    "id": "cinv_123",
    "calendar_id": "cal_002",
    "calendar_name": "Shared Home",
    "email": "friend@example.com",
    "delivery_channel": "sms",
    "role": "editor",
    "invited_by_display_name": "DayFlow Owner",
    "expires_at": "2026-03-24T00:00:00Z"
  }
}
```

### `POST /invites/{invite_code}/accept`

Accepts an invite link for the authenticated user and adds membership to the shared calendar.

Response:

```json
{
  "calendar": {
    "id": "cal_002",
    "kind": "shared",
    "name": "Shared Home",
    "color": "#D8A21D",
    "membership_role": "editor",
    "updated_at": "2026-03-17T00:00:00Z"
  }
}
```

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
      "calendar_id": "cal_002",
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
  "all_day": false
}
```

### `POST /events/{id}/transfer`

Copies or moves an event into a shared calendar without converting the personal calendar itself.

Request:

```json
{
  "target_calendar_id": "cal_002",
  "mode": "copy"
}
```

Response:

```json
{
  "source_event_id": "evt_001",
  "target_event": {
    "id": "evt_101",
    "calendar_id": "cal_002",
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
  "all_day": false
}
```

### `DELETE /events/{id}`

## Budget

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

Upserts the month board. The client sends the full edited shape for simplicity.

Current MVP contract rules:

- the request is a current-month snapshot write, not a template update
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

Replaces the owner-scoped fixed-item template list for MVP.

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
- Budget responses are single-user scoped
- The iOS client should be able to render the budget screen from one budget-month response
- Auth and calendar payloads use snake_case JSON keys over the wire
- `/me` returns grouped calendar bootstrap data, while `/calendars` returns the shared-calendar list payload
- personal calendars are never shared directly; only shared calendars accept members
