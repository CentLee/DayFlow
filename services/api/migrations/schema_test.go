package migrations

import (
	"os"
	"strings"
	"testing"
)

func TestInitSchemaDefinesBaseUserAuthColumns(t *testing.T) {
	contents := mustReadMigration(t, "0001_init.sql")
	requireContainsAll(t, contents,
		"CREATE TABLE users (",
		"email TEXT NOT NULL UNIQUE",
		"password_hash TEXT NOT NULL",
		"created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()",
		"updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()",
	)
}

func TestInitSchemaDefinesBudgetStorageTables(t *testing.T) {
	contents := mustReadMigration(t, "0001_init.sql")
	requireContainsAll(t, contents,
		"CREATE TABLE expense_books (",
		"owner_user_id TEXT NOT NULL UNIQUE REFERENCES users(id)",
		"CREATE TABLE budget_months (",
		"expense_book_id TEXT NOT NULL REFERENCES expense_books(id) ON DELETE CASCADE",
		"month_key TEXT NOT NULL",
		"remaining_budget_amount INTEGER NOT NULL DEFAULT 0",
		"UNIQUE (expense_book_id, month_key)",
		"CREATE TABLE budget_item_entries (",
		"budget_month_id TEXT NOT NULL REFERENCES budget_months(id) ON DELETE CASCADE",
		"billing_day_label TEXT NOT NULL DEFAULT ''",
		"CREATE TABLE budget_buckets (",
		"planned_amount INTEGER NOT NULL DEFAULT 0",
		"actual_amount INTEGER NOT NULL DEFAULT 0",
		"CREATE TABLE billing_reminders (",
		"budget_item_entry_id TEXT REFERENCES budget_item_entries(id) ON DELETE SET NULL",
		"due_day_label TEXT NOT NULL",
	)
}

func TestAuthSchemaDefinesCalendarInvites(t *testing.T) {
	contents := mustReadMigration(t, "0002_auth_schema.sql")
	requireContainsAll(t, contents,
		"CREATE TABLE calendar_invites (",
		"calendar_id TEXT NOT NULL REFERENCES calendars(id) ON DELETE CASCADE",
		"invite_code TEXT NOT NULL UNIQUE",
		"invited_by_user_id TEXT NOT NULL REFERENCES users(id)",
		"accepted_by_user_id TEXT REFERENCES users(id)",
		"CHECK (role IN ('editor', 'viewer'))",
		"CREATE UNIQUE INDEX calendar_invites_calendar_email_lower_idx ON calendar_invites (calendar_id, LOWER(email));",
	)
}

func TestAuthSchemaDefinesUserSessions(t *testing.T) {
	contents := mustReadMigration(t, "0002_auth_schema.sql")
	requireContainsAll(t, contents,
		"CREATE TABLE user_sessions (",
		"user_id TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE",
		"token_hash TEXT NOT NULL UNIQUE",
		"last_used_at TIMESTAMPTZ NOT NULL DEFAULT NOW()",
		"expires_at TIMESTAMPTZ NOT NULL",
		"revoked_at TIMESTAMPTZ",
		"CHECK (expires_at > created_at)",
		"CREATE INDEX user_sessions_active_lookup_idx ON user_sessions (user_id, revoked_at, expires_at);",
	)
}

func TestAuthSchemaExtendsUsersForInviteRegistration(t *testing.T) {
	contents := mustReadMigration(t, "0002_auth_schema.sql")
	requireContainsAll(t, contents,
		"ALTER TABLE users",
		"ADD COLUMN registered_by_invite_id TEXT REFERENCES calendar_invites(id);",
		"CREATE UNIQUE INDEX users_email_lower_idx ON users (LOWER(email));",
	)
}

func TestCalendarEventFoundationSchemaAddsIndexesAndConstraints(t *testing.T) {
	contents := mustReadMigration(t, "0003_calendar_event_foundation.sql")
	requireContainsAll(t, contents,
		"CREATE INDEX idx_calendar_members_user_id ON calendar_members(user_id);",
		"CREATE INDEX idx_events_calendar_id_starts_at ON events(calendar_id, starts_at);",
		"ADD CONSTRAINT calendar_members_role_check",
		"CHECK (role IN ('owner', 'editor', 'viewer'))",
		"ADD CONSTRAINT events_time_range_check",
		"CHECK (ends_at >= starts_at);",
	)
}

func TestBudgetStorageSchemaAddsReminderTimestampsAndIndexes(t *testing.T) {
	contents := mustReadMigration(t, "0004_budget_storage.sql")
	requireContainsAll(t, contents,
		"ALTER TABLE billing_reminders",
		"ADD COLUMN updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW();",
		"CREATE INDEX idx_budget_months_expense_book_month_key ON budget_months(expense_book_id, month_key);",
		"CREATE INDEX idx_budget_item_entries_budget_month_id_sort_order ON budget_item_entries(budget_month_id, sort_order);",
		"CREATE INDEX idx_budget_buckets_budget_month_id ON budget_buckets(budget_month_id);",
		"CREATE INDEX idx_billing_reminders_budget_month_id ON billing_reminders(budget_month_id);",
	)
}

func TestCalendarRuntimeColumnsSchemaAddsKindAndDeliveryChannel(t *testing.T) {
	contents := mustReadMigration(t, "0005_calendar_runtime_columns.sql")
	requireContainsAll(t, contents,
		"ALTER TABLE calendars",
		"ADD COLUMN kind TEXT NOT NULL DEFAULT 'shared';",
		"ADD CONSTRAINT calendars_kind_check",
		"CHECK (kind IN ('personal', 'shared'));",
		"ALTER TABLE calendar_invites",
		"ADD COLUMN delivery_channel TEXT NOT NULL DEFAULT 'email';",
		"ADD CONSTRAINT calendar_invites_delivery_channel_check",
		"CHECK (delivery_channel IN ('email', 'sms'));",
	)
}

func mustReadMigration(t *testing.T, name string) string {
	t.Helper()
	contents, err := os.ReadFile(name)
	if err != nil {
		t.Fatalf("read migration %s: %v", name, err)
	}
	return string(contents)
}

func requireContainsAll(t *testing.T, contents string, snippets ...string) {
	t.Helper()
	for _, snippet := range snippets {
		if !strings.Contains(contents, snippet) {
			t.Fatalf("expected migration to contain %q", snippet)
		}
	}
}
