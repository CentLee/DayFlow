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

Returns current user, owned calendars, shared calendars, and current budget month key.

Response:

```json
{
  "user": {
    "id": "usr_001",
    "email": "owner@dayflow.local",
    "display_name": "DayFlow Owner"
  },
  "owned_calendars": [
    {
      "id": "cal_001",
      "name": "Personal",
      "color": "#1F6B5C",
      "updated_at": "2026-03-17T00:00:00Z"
    },
    {
      "id": "cal_002",
      "name": "Shared Home",
      "color": "#D8A21D",
      "updated_at": "2026-03-17T00:00:00Z"
    }
  ],
  "shared_calendars": [],
  "current_budget_month_key": "2026-03"
}
```

Notes:

- auth responses stay minimal for MVP and do not inline calendar or budget payloads
- `/me` is the bootstrap source for session user data and current month routing
- current memory mocks return the owner view above for the seeded owner account

Invited collaborator example:

```json
{
  "user": {
    "id": "usr_005",
    "email": "user@example.com",
    "display_name": "Kakao"
  },
  "owned_calendars": [],
  "shared_calendars": [
    {
      "id": "cal_002",
      "name": "Shared Home",
      "color": "#D8A21D",
      "updated_at": "2026-03-17T00:00:00Z"
    }
  ],
  "current_budget_month_key": "2026-03"
}
```

Notes:

- invited collaborators move shared calendars into `shared_calendars` and do not receive budget data
- the collaborator example is the intended grouped shape for session bootstrap after invite registration/login

## Calendars

### `GET /calendars`

Returns the current flat calendar list from the backend memory mock.

Response:

```json
{
  "items": [
    {
      "id": "cal_001",
      "name": "Personal",
      "color": "#1F6B5C",
      "updated_at": "2026-03-17T00:00:00Z"
    }
  ]
}
```

Notes:

- the seeded owner mock currently returns only `owned_calendars` here
- shared calendars for collaborators are documented in `/me` above and remain a follow-up for the flat `/calendars` mock
- the list stays budget-free even when a calendar is shared

### `POST /calendars`

Creates a personal calendar.

Request:

```json
{
  "name": "Trips",
  "color": "#5B7FFF"
}
```

Response:

```json
{
  "id": "cal_003",
  "name": "Trips",
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
  "role": "editor"
}
```

Response:

```json
{
  "id": "cinv_123",
  "calendar_id": "cal_002",
  "email": "friend@example.com",
  "role": "editor",
  "invite_code": "invite_abc",
  "updated_at": "2026-03-17T00:00:00Z"
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

Response shape:

```json
{
  "month": {
    "id": "bmon_123",
    "month_key": "2026-03",
    "base_budget_amount": 510,
    "current_cash_amount": 118,
    "saving_amount": 200,
    "carry_over_amount": 0,
    "remaining_budget_amount": 16,
    "updated_at": "2026-03-17T00:00:00Z"
  },
  "summary": {
    "fixed_cost_total": 294,
    "variable_bucket_total": 0,
    "free_cash_amount": 118
  },
  "fixed_items": [],
  "variable_buckets": [],
  "billing_reminders": []
}
```

### `PUT /budget/months/{yyyy-mm}`

Upserts the month board. The client sends the full edited shape for simplicity.

### `GET /budget/templates`

### `PUT /budget/templates`

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
- `/me` returns grouped calendar bootstrap data, while `/calendars` returns the canonical flat list payload
