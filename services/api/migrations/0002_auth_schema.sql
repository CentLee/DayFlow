CREATE TABLE calendar_invites (
    id TEXT PRIMARY KEY,
    calendar_id TEXT NOT NULL REFERENCES calendars(id) ON DELETE CASCADE,
    email TEXT NOT NULL,
    role TEXT NOT NULL,
    invite_code TEXT NOT NULL UNIQUE,
    invited_by_user_id TEXT NOT NULL REFERENCES users(id),
    accepted_by_user_id TEXT REFERENCES users(id),
    accepted_at TIMESTAMPTZ,
    expires_at TIMESTAMPTZ,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    CHECK (role IN ('editor', 'viewer')),
    CHECK (
        (accepted_by_user_id IS NULL AND accepted_at IS NULL)
        OR (accepted_by_user_id IS NOT NULL AND accepted_at IS NOT NULL)
    ),
    CHECK (expires_at IS NULL OR expires_at > created_at)
);

CREATE UNIQUE INDEX calendar_invites_calendar_email_lower_idx ON calendar_invites (calendar_id, LOWER(email));
CREATE INDEX calendar_invites_invited_by_user_id_idx ON calendar_invites (invited_by_user_id, created_at DESC);
CREATE INDEX calendar_invites_accepted_by_user_id_idx ON calendar_invites (accepted_by_user_id) WHERE accepted_by_user_id IS NOT NULL;

CREATE TABLE user_sessions (
    id TEXT PRIMARY KEY,
    user_id TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    token_hash TEXT NOT NULL UNIQUE,
    last_used_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    expires_at TIMESTAMPTZ NOT NULL,
    revoked_at TIMESTAMPTZ,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    CHECK (expires_at > created_at)
);

CREATE INDEX user_sessions_user_id_idx ON user_sessions (user_id, created_at DESC);
CREATE INDEX user_sessions_active_lookup_idx ON user_sessions (user_id, revoked_at, expires_at);

ALTER TABLE users
    ADD COLUMN registered_by_invite_id TEXT REFERENCES calendar_invites(id);

CREATE UNIQUE INDEX users_email_lower_idx ON users (LOWER(email));
