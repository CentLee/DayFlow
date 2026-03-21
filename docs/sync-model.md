# DayFlow Sync Model

## Goals

- keep the MVP simple
- support quick budget edits
- avoid cross-user data leakage

## Session Bootstrap

1. login or register and persist the bearer token
2. fetch `/v1/me` for session user, grouped calendar bootstrap data, and `current_budget_month_key`
3. fetch `/v1/calendars` for the canonical flat calendar list
4. fetch `/v1/budget/months/{current_budget_month_key}` from step 2

Notes:

- auth stays minimal for MVP and does not inline calendars or budget data
- after `/v1/me`, the client may request `/v1/calendars` and `/v1/budget/months/{current_budget_month_key}` in parallel
- if `/v1/calendars` is still loading, the client may temporarily seed the list from `/v1/me`

## Budget Sync

- local edits immediately update visible KPIs
- client stores the last server snapshot
- client sends a full month payload on save
- server returns authoritative recalculated values
- if request fails, client restores the last confirmed snapshot and surfaces retry state

Current KPI sync assumptions:

- optimistic client calculations should mirror the server formulas in `docs/api-contract.md`
- `fixed_cost_total` uses only enabled fixed items
- `variable_bucket_total` uses planned bucket amounts
- `free_cash_amount` uses actual bucket amounts
- `billing_reminders` and `formula_hint` do not affect KPI math

## Calendar Sync

- server is source of truth
- client caches the flat calendar list and date-range event payloads
- `/v1/me` is a bootstrap seed, not a replacement for `/v1/calendars`
- last-write-wins by `updated_at` for MVP

## Conflict Rules

- budget: last confirmed server write wins
- calendar: latest update timestamp wins
- no merge UI in MVP

## Mock Data Requirements

- a current month budget mirroring the Excel categories
- one shared calendar and one personal calendar
- one invited collaborator account
- auth mocks use the same `user` and `token` response shape for login and register
- calendar mocks reuse the same minimal calendar summary shape in `/v1/me` and `/v1/calendars`
- event mocks include one shared-calendar event with `notes`, `starts_at`, `ends_at`, and `updated_at`

## Current Contract Gaps

- none for the current budget KPI formulas or budget-month payload shape; the served backend response, sync rules, and API examples now match
- follow-up work remains in `[iOS] connect budget board to live API`, but that is a wiring task rather than a current payload mismatch
