# DayFlow Product Spec

## Summary

DayFlow combines a shared calendar with a personal-first monthly budget board.

The budget experience is modeled directly after the provided Excel workbook:

- top-level monthly KPIs are always visible
- fixed costs are edited in place
- variable spending is handled as buckets rather than mandatory transaction rows
- billing reminders are attached to budget items for quick planning

## Mandatory Input Insights

### Harness Patterns Used

The provided harness references influenced the repo and agent structure:

- pipeline for requirement to implementation flow
- fan-out/fan-in for backend, iOS, and integration work
- producer-reviewer for final validation by the review agent

### Excel Insights

Observed structure from the workbook:

- monthly summary: current money, monthly budget, fixed costs, savings, remaining budget
- fixed items: named recurring costs with on/off state and base value
- variable buckets: lunch/weekend meals, flexible money
- calendar-like reminders: settlement days attached to items

These insights shape the MVP:

- budget board is the main expense UI
- single-month editing is optimized for speed
- category and bucket editing matters more than detailed transaction history

## Users

- primary: you and a small number of invited collaborators
- environment: local or self-hosted on a personal iMac server

## Core Flows

1. User signs in.
2. App loads the user profile, calendars, and current month budget.
3. User creates or edits personal events.
4. User shares a calendar with another invited account.
5. User edits monthly budget values in one screen and sees summary changes immediately.

## MVP Features

### Calendar

- personal calendar creation
- calendar list
- month and week views
- event CRUD
- invite user to a specific calendar
- member role: owner, editor, viewer

### Budget

- one personal expense book per user
- month board with KPI summary
- fixed item template editing
- variable buckets
- savings target
- billing reminder metadata
- notes per item

## Monthly Budget Board Rules

### Current MVP Board Scope

- the month board is the main editing surface for one `YYYY-MM` snapshot
- board edits are private to the owner and never inherit calendar sharing permissions
- board edits update the visible KPI summary immediately
- KPI cards are display-only derived views and never accept direct user overrides on the board
- template management stays separate from month-board value editing

### Fixed Item Rules

- fixed items appear on the board as month-scoped copies of the user template
- the board supports fast edits to `enabled`, `amount`, and item notes for the current month
- fixed-item names, default values, and ordering are managed in template editing, not inline on the month board
- the board does not support inline add, delete, rename, or reorder actions for fixed items in MVP
- editing a fixed item changes only the current month snapshot and does not rewrite other months or template defaults

### Variable Bucket Rules

- variable buckets stay bucket-based rather than becoming transaction rows
- the board supports inline edits to planned and actual amounts for the current month
- planned amounts affect remaining budget immediately
- actual amounts affect free cash calculations immediately
- bucket structure and defaults stay template-driven for MVP, rather than open-ended inline board customization
- bucket names, ordering, and formula hints stay outside inline month-board editing

### Billing Reminder Rules

- reminders are planning metadata attached to budget items, not standalone schedule objects
- the board supports editing reminder label, due-day label, and note text for the current month
- reminders stay informational in MVP and do not create calendar events, notifications, or KPI changes
- the board does not create, detach, or automate reminders beyond editing attached metadata for the current month
- reminder edits are saved with the month board and remain private to the budget owner

### Current KPI Truth

- `current money` maps to `current_cash_amount` and is a manual month value
- `monthly budget` maps to `base_budget_amount`
- `carry over` maps to `carry_over_amount` and is a manual month value
- `fixed costs` is the sum of enabled fixed-item amounts
- `savings` maps to `saving_amount`
- `variable bucket total` is the sum of bucket `planned_amount` values
- `remaining budget` is `base_budget_amount - fixed_cost_total - saving_amount - variable_bucket_total + carry_over_amount`
- `free cash` remains a supporting derived value: `current_cash_amount - enabled fixed item amounts - variable bucket actual amounts`
- bucket `actual_amount` values affect `free cash` but do not change `remaining budget`
- `billing_reminders` and bucket `formula_hint` text are informational and do not affect KPI calculations

### Follow-up Notes

- future work may allow richer inline structure edits such as add, delete, rename, and reorder directly on the board
- future work may separate reminder automation from reminder metadata, including calendar or notification hooks
- future work may add transaction drill-down or formula-driven bucket behavior, but that is not part of the MVP board contract

### Authentication

- invited account registration
- password hash authentication
- session token auth for iOS client

## Out of Scope

- bank sync
- full accounting ledger
- event comments
- push notifications
- web frontend
- real-time collaborative editing

## Success Criteria

- a user can manage a monthly budget without leaving the month board
- fixed-cost toggles and amount edits update KPI totals correctly
- invited users can access only shared calendars
- budget data remains private per user
