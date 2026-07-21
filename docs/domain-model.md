# DayFlow Domain Model

## Principles

- every user has one personal calendar
- shared calendars are separate resources joined by invite
- budgets are personal-only
- month data is snapshot-based
- templates seed month entries but do not lock them

## Entities

### User

- `id`
- `email`
- `display_name`
- `password_hash`
- `registered_by_invite_id` (optional)
- `created_at`
- `updated_at`

### Invite

- `id`
- `calendar_id`
- `email`
- `delivery_channel` (`email`, `sms`)
- `role` (`editor`, `viewer`)
- `invite_code`
- `invite_url`
- `invited_by_user_id`
- `accepted_by_user_id`
- `accepted_at`
- `expires_at`
- `created_at`
- `updated_at`

### Session

- `id`
- `user_id`
- `token_hash`
- `last_used_at`
- `expires_at`
- `revoked_at`
- `created_at`

### Calendar

- `id`
- `owner_user_id`
- `kind` (`personal`, `shared`)
- `name`
- `color`
- `created_at`
- `updated_at`

### CalendarMember

- `calendar_id`
- `user_id`
- `role` (`owner`, `editor`, `viewer`)
- `created_at`

### Event

- `id`
- `calendar_id`
- `title`
- `notes`
- `starts_at`
- `ends_at`
- `all_day`
- `created_by_user_id`
- `origin_event_id` (optional)
- `updated_at`

### ExpenseBook

- `id`
- `owner_user_id`
- `name`
- `currency_code`
- `created_at`
- `updated_at`

### BudgetMonth

- `id`
- `expense_book_id`
- `month_key` (`YYYY-MM`)
- `base_budget_amount`
- `current_cash_amount`
- `saving_amount`
- `carry_over_amount`
- `remaining_budget_amount`
- `updated_at`

### BudgetItemTemplate

- `id`
- `expense_book_id`
- `name`
- `kind` (`fixed`, `saving`, `variable_bucket`)
- `default_amount`
- `default_enabled`
- `default_note`
- `default_billing_day`
- `sort_order`
- `updated_at`

### BudgetItemEntry

- `id`
- `budget_month_id`
- `template_id`
- `name`
- `kind`
- `amount`
- `enabled`
- `note`
- `billing_day_label`
- `sort_order`
- `updated_at`

### BudgetBucket

- `id`
- `budget_month_id`
- `name`
- `planned_amount`
- `actual_amount`
- `formula_hint`
- `updated_at`

### BillingReminder

- `id`
- `budget_month_id`
- `budget_item_entry_id`
- `label`
- `due_day_label`
- `note`
- `updated_at`

## Derived Summary Rules

- `fixed_cost_total`: enabled fixed item amounts
- `variable_bucket_total`: sum of planned variable buckets
- `remaining_budget_amount`: `base_budget_amount - fixed_cost_total - saving_amount - variable_bucket_total + carry_over_amount`
- `free_cash_amount`: `current_cash_amount - enabled fixed item amounts - variable bucket actual amounts`

## Month Board Edit Boundaries

- templates seed month entries and buckets, but month-board edits do not rewrite template defaults or prior months
- `BudgetItemEntry` is the editable current-month snapshot for fixed-item values such as `enabled`, `amount`, and `note`
- `BudgetBucket` is the editable current-month snapshot for `planned_amount` and `actual_amount`
- names, sort order, and formula-style structure fields remain template-owned instead of month-board editable
- `BillingReminder` stays attached to a month item as informational metadata and does not imply calendar event creation
- KPI summary values are derived from the month snapshot and are not direct user-editable fields
- the current product summary prioritizes `current_cash_amount`, `base_budget_amount`, `fixed_cost_total`, `saving_amount`, and `remaining_budget_amount`; `free_cash_amount` remains a supporting derived field

## Privacy Rules

- `BudgetMonth`, `BudgetItemEntry`, `BudgetBucket`, `BillingReminder` are accessible only by the expense book owner
- calendar membership never grants budget access
- invite acceptance grants calendar access only after membership is created
- sessions authenticate one user account and do not widen budget visibility

## Calendar Behavior Rules

- a user personal calendar is provisioned automatically and is never converted into a shared calendar
- `Calendar.kind = personal` is private to its owner and never accepts members
- `Calendar.kind = shared` is the only calendar kind that accepts invites and members
- event visibility follows the calendar that currently contains the event
- moving or copying an event from a personal calendar into a shared calendar is an explicit user action
- `origin_event_id` may link a copied shared event back to its personal source when the product chooses copy instead of move
