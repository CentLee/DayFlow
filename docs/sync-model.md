# DayFlow Sync Model

## Goals

- keep the MVP simple
- support quick budget edits
- avoid cross-user data leakage

## Session Bootstrap

1. login or register
2. fetch `/v1/me`
3. fetch `/v1/calendars`
4. fetch `/v1/budget/months/{current-month}`

## Budget Sync

- local edits immediately update visible KPIs
- client stores the last server snapshot
- client sends a full month payload on save
- server returns authoritative recalculated values
- if request fails, client restores the last confirmed snapshot and surfaces retry state

## Calendar Sync

- server is source of truth
- client caches lists and date-range event payloads
- last-write-wins by `updated_at` for MVP

## Conflict Rules

- budget: last confirmed server write wins
- calendar: latest update timestamp wins
- no merge UI in MVP

## Mock Data Requirements

- a current month budget mirroring the Excel categories
- one shared calendar and one personal calendar
- one invited collaborator account

