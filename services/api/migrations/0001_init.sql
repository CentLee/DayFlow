CREATE TABLE users (
    id TEXT PRIMARY KEY,
    email TEXT NOT NULL UNIQUE,
    display_name TEXT NOT NULL,
    password_hash TEXT NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE calendars (
    id TEXT PRIMARY KEY,
    owner_user_id TEXT NOT NULL REFERENCES users(id),
    name TEXT NOT NULL,
    color TEXT NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE calendar_members (
    calendar_id TEXT NOT NULL REFERENCES calendars(id) ON DELETE CASCADE,
    user_id TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    role TEXT NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    PRIMARY KEY (calendar_id, user_id)
);

CREATE TABLE events (
    id TEXT PRIMARY KEY,
    calendar_id TEXT NOT NULL REFERENCES calendars(id) ON DELETE CASCADE,
    title TEXT NOT NULL,
    notes TEXT NOT NULL DEFAULT '',
    starts_at TIMESTAMPTZ NOT NULL,
    ends_at TIMESTAMPTZ NOT NULL,
    all_day BOOLEAN NOT NULL DEFAULT FALSE,
    created_by_user_id TEXT NOT NULL REFERENCES users(id),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE expense_books (
    id TEXT PRIMARY KEY,
    owner_user_id TEXT NOT NULL UNIQUE REFERENCES users(id),
    name TEXT NOT NULL,
    currency_code TEXT NOT NULL DEFAULT 'KRW',
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE budget_months (
    id TEXT PRIMARY KEY,
    expense_book_id TEXT NOT NULL REFERENCES expense_books(id) ON DELETE CASCADE,
    month_key TEXT NOT NULL,
    base_budget_amount INTEGER NOT NULL DEFAULT 0,
    current_cash_amount INTEGER NOT NULL DEFAULT 0,
    saving_amount INTEGER NOT NULL DEFAULT 0,
    carry_over_amount INTEGER NOT NULL DEFAULT 0,
    remaining_budget_amount INTEGER NOT NULL DEFAULT 0,
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    UNIQUE (expense_book_id, month_key)
);

CREATE TABLE budget_item_templates (
    id TEXT PRIMARY KEY,
    expense_book_id TEXT NOT NULL REFERENCES expense_books(id) ON DELETE CASCADE,
    name TEXT NOT NULL,
    kind TEXT NOT NULL,
    default_amount INTEGER NOT NULL DEFAULT 0,
    default_enabled BOOLEAN NOT NULL DEFAULT TRUE,
    default_note TEXT NOT NULL DEFAULT '',
    default_billing_day TEXT NOT NULL DEFAULT '',
    sort_order INTEGER NOT NULL DEFAULT 0,
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE budget_item_entries (
    id TEXT PRIMARY KEY,
    budget_month_id TEXT NOT NULL REFERENCES budget_months(id) ON DELETE CASCADE,
    template_id TEXT REFERENCES budget_item_templates(id),
    name TEXT NOT NULL,
    kind TEXT NOT NULL,
    amount INTEGER NOT NULL DEFAULT 0,
    enabled BOOLEAN NOT NULL DEFAULT TRUE,
    note TEXT NOT NULL DEFAULT '',
    billing_day_label TEXT NOT NULL DEFAULT '',
    sort_order INTEGER NOT NULL DEFAULT 0,
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE budget_buckets (
    id TEXT PRIMARY KEY,
    budget_month_id TEXT NOT NULL REFERENCES budget_months(id) ON DELETE CASCADE,
    name TEXT NOT NULL,
    planned_amount INTEGER NOT NULL DEFAULT 0,
    actual_amount INTEGER NOT NULL DEFAULT 0,
    formula_hint TEXT NOT NULL DEFAULT '',
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE billing_reminders (
    id TEXT PRIMARY KEY,
    budget_month_id TEXT NOT NULL REFERENCES budget_months(id) ON DELETE CASCADE,
    budget_item_entry_id TEXT REFERENCES budget_item_entries(id) ON DELETE SET NULL,
    label TEXT NOT NULL,
    due_day_label TEXT NOT NULL,
    note TEXT NOT NULL DEFAULT ''
);

