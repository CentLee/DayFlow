ALTER TABLE billing_reminders
    ADD COLUMN updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW();

CREATE INDEX idx_budget_months_expense_book_month_key ON budget_months(expense_book_id, month_key);
CREATE INDEX idx_budget_item_entries_budget_month_id_sort_order ON budget_item_entries(budget_month_id, sort_order);
CREATE INDEX idx_budget_buckets_budget_month_id ON budget_buckets(budget_month_id);
CREATE INDEX idx_billing_reminders_budget_month_id ON billing_reminders(budget_month_id);
