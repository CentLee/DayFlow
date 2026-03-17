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
