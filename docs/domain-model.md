# DayFlow Domain Model

## Invariants

- A DayFlow deployment has exactly two users: one `owner` and one `partner`.
- Each user has exactly one private personal calendar.
- The deployment has exactly one household shared calendar.
- Personal calendars never have members other than their owner.
- Both users are provisioned as editors of the household calendar.
- Only the owner has an expense book or any budget data.
- Google identity establishes a DayFlow session; it does not connect Google
  Calendar.
- iPhones use the iMac's Tailscale MagicDNS name; no public or alternate remote
  endpoint exists.
- The server on the owner's iMac is authoritative; device state is a
  per-identity cache plus pending mutations.

## Identity and Session Entities

### IdentityAllowlistEntry

Deployment configuration rather than user-managed application data:

- `household_role` (`owner`, `partner`; unique)
- `google_subject` (stable Google `sub`; unique)
- `expected_email_normalized` (unique deployment guard)
- `enabled`

Exactly two enabled entries must exist before the service accepts exchanges.
Authorization uses `google_subject`; email cannot substitute for it.

### User

- `id`
- `household_role` (`owner`, `partner`; unique)
- `google_subject` (unique, immutable after verified migration)
- `email_normalized`
- `display_name`
- `created_at`
- `updated_at`

There is no password hash, registration state, invite relationship, or
user-managed role.

### Session

- `id`
- `user_id`
- `token_hash`
- `last_used_at`
- `expires_at`
- `revoked_at`
- `created_at`

Sessions are opaque, revocable DayFlow credentials. Google ID/access tokens are
not stored in the session or used after the exchange completes.

## Calendar Entities

### Calendar

- `id`
- `kind` (`personal`, `household`)
- `owner_user_id` (required only for `personal`)
- `name`
- `color`
- `created_at`
- `updated_at`

Cardinality constraints:

- one `personal` calendar for each user
- one `household` calendar per deployment
- `household.owner_user_id` is null because it is deployment-provisioned
- no API changes `kind` or creates additional calendars

### CalendarMember

- `calendar_id`
- `user_id`
- `role` (`editor`)
- `created_at`

Rows exist only for the household calendar and the two allowlisted users.
Personal-calendar access derives from `Calendar.owner_user_id`, not membership.
Membership has no create, update, or delete flow in MVP.

### Event

- `id`
- `calendar_id`
- `title`
- `notes`
- `starts_at`
- `ends_at`
- `all_day`
- `created_by_user_id`
- `origin_event_id` (optional copy lineage)
- `client_mutation_id` (optional idempotency key)
- `updated_at`
- `deleted_at` (optional synchronization tombstone)

## Budget Entities

### ExpenseBook

- `id`
- `owner_user_id` (unique; must reference the `owner` role)
- `name`
- `currency_code`
- `created_at`
- `updated_at`

No row may reference the partner.

### BudgetMonth

- `id`
- `expense_book_id`
- `month_key` (`YYYY-MM`; unique within the book)
- `base_budget_amount`
- `current_cash_amount`
- `saving_amount`
- `carry_over_amount`
- `remaining_budget_amount` (server-derived)
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

Reminders are budget metadata and never imply a calendar event, Google Calendar
record, or notification.

## Device Synchronization Entities

### DeviceCursor

- `user_id`
- `device_id`
- `resource_scope`
- `server_cursor`
- `updated_at`

The partner has calendar scopes only. The owner may also have an owner-budget
scope.

### AppliedMutation

- `user_id`
- `client_mutation_id`
- `resource_type`
- `resource_id`
- `applied_at`

The uniqueness of (`user_id`, `client_mutation_id`) makes retry after an
ambiguous network failure idempotent. Pending outbox items live on-device, not
as a server authority.

## Behavior Rules

### Identity Provisioning

- The server validates a Google ID token before resolving its allowlist entry.
- The allowlisted subject resolves one immutable household role and one `User`.
- First accepted exchange may create the matching user and personal calendar.
- A deployment migration, not a user request, creates the household calendar,
  both memberships, and the owner's expense book.
- A rejected subject creates no user, calendar, membership, session, or budget
  row.

### Calendar Privacy

- A user can read and mutate their own personal events.
- Neither person can list or address the other personal calendar.
- Both users can read and mutate household events.
- Copy creates a new household event and may set `origin_event_id`; the personal
  source remains private.
- Move commits the household target before removing the personal source.
- Listing calendars never returns budget data or the other personal calendar.

### Budget Privacy

- All budget entities are reachable only through the owner's `ExpenseBook`.
- Authorization checks the authenticated user's `household_role = owner` before
  resolving a budget resource.
- The partner receives `forbidden`, not an empty owner board.
- Calendar membership, household event lineage, device cursors, and session
  ownership never grant budget access.
- Partner devices never create an owner-budget cache or mutation outbox.

### Monthly Board

- templates seed month entries and buckets without locking month snapshots
- current-month item edits change `enabled`, `amount`, and `note`
- current-month bucket edits change `planned_amount` and `actual_amount`
- names, kinds, ordering, and defaults remain template-managed
- KPI values are derived and cannot be overridden by a client write

Derived values:

- `fixed_cost_total`: sum of enabled fixed item amounts
- `variable_bucket_total`: sum of planned bucket amounts
- `remaining_budget_amount`: `base_budget_amount - fixed_cost_total -
  saving_amount - variable_bucket_total + carry_over_amount`
- `free_cash_amount`: `current_cash_amount - fixed_cost_total - variable bucket
  actual amounts`

### Synchronization

- PostgreSQL on the iMac is authoritative.
- Every mutation is authorized again when synchronized; a cached session or
  pending write never bypasses current access rules.
- `client_mutation_id` deduplicates retries.
- Event conflicts use server `updated_at` with the explicit rules in
  `docs/sync-model.md`.
- Budget-month conflicts use the last confirmed server version and never merge
  derived KPI fields.
- Tombstones are retained long enough for both devices to observe deletions.

## Legacy Migration Targets

Legacy `password_hash`, password/register/login flows, invite and
delivery-channel records, arbitrary membership, extra shared-calendar records,
and public/custom-domain ingress configuration are migration inputs only. They
are not target entities or supported behavior.

- User IDs and personal-calendar ownership are preserved when binding the two
  Google subjects.
- Exactly one existing shared calendar may be designated as `household`; extra
  calendars are archived only after event disposition is verified.
- The owner's existing expense book is retained.
- Partner or unknown-user budget rows are exported or quarantined and then
  removed; they are never copied to the owner.
- Legacy secrets are removed only after the new exchange and client cutover is
  verified against a restorable backup.
