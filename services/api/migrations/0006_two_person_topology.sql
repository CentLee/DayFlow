ALTER TABLE users
    ADD COLUMN household_role TEXT,
    ADD COLUMN google_subject TEXT,
    ADD COLUMN email_normalized TEXT;

ALTER TABLE calendars
    ALTER COLUMN owner_user_id DROP NOT NULL;

ALTER TABLE calendars
    DROP CONSTRAINT calendars_kind_check,
    ADD CONSTRAINT calendars_kind_check
    CHECK (kind IN ('personal', 'shared', 'household', 'archived'));

CREATE UNIQUE INDEX users_household_role_idx
    ON users (household_role)
    WHERE household_role IS NOT NULL;

CREATE UNIQUE INDEX users_google_subject_idx
    ON users (google_subject)
    WHERE google_subject IS NOT NULL;

CREATE UNIQUE INDEX users_email_normalized_idx
    ON users (email_normalized)
    WHERE email_normalized IS NOT NULL;

CREATE UNIQUE INDEX calendars_one_household_idx
    ON calendars (kind)
    WHERE kind = 'household';

CREATE TABLE budget_quarantine (
    id BIGSERIAL PRIMARY KEY,
    source_expense_book_id TEXT NOT NULL,
    source_owner_user_id TEXT NOT NULL,
    reason TEXT NOT NULL,
    payload JSONB NOT NULL,
    quarantined_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    UNIQUE (source_expense_book_id)
);
