# DayFlow API Contract Draft

Base path: `/v1`

Authentication: bearer token

## Auth

### `POST /auth/register`

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

### `GET /me`

Returns current user, owned calendars, shared calendars, and current budget month key.

## Calendars

### `GET /calendars`

Returns calendars visible to the user.

### `POST /calendars`

Creates a personal calendar.

### `POST /calendars/{id}/invites`

Creates or reuses an invite for a target email.

Request:

```json
{
  "email": "friend@example.com",
  "role": "editor"
}
```

### `GET /calendars/{id}/events`

Query params:

- `from`
- `to`

### `POST /calendars/{id}/events`

### `PATCH /events/{id}`

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

