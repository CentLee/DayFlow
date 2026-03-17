# DayFlow Domain Model

## Principles

- calendars are shareable
- budgets are personal-only
- month data is snapshot-based
- templates seed month entries but do not lock them

## Entities

### User

- `id`
- `email`
- `display_name`
- `password_hash`
- `created_at`
- `updated_at`

### Calendar

- `id`
- `owner_user_id`
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

## Derived Summary Rules

- `fixed_cost_total`: enabled fixed item amounts
- `variable_bucket_total`: sum of planned variable buckets
- `remaining_budget_amount`: `base_budget_amount - fixed_cost_total - saving_amount - variable_bucket_total + carry_over_amount`
- `free_cash_amount`: `current_cash_amount - enabled fixed item amounts - variable bucket actual amounts`

## Privacy Rules

- `BudgetMonth`, `BudgetItemEntry`, `BudgetBucket`, `BillingReminder` are accessible only by the expense book owner
- calendar membership never grants budget access

