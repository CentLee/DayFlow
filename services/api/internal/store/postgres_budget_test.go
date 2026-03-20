package store

import (
	"context"
	"database/sql"
	"errors"
	"fmt"
	"regexp"
	"testing"
	"time"

	"github.com/DATA-DOG/go-sqlmock"
	"github.com/kakao-ent/dayflow/services/api/internal/domain"
)

func TestPostgresBudgetStoreLoadBudgetBoard(t *testing.T) {
	db, mock, err := sqlmock.New()
	if err != nil {
		t.Fatalf("sqlmock: %v", err)
	}
	defer db.Close()

	store := NewPostgresBudgetStore(db)
	updatedAt := time.Date(2026, 3, 17, 0, 0, 0, 0, time.UTC)

	mock.ExpectQuery(regexp.QuoteMeta(`
SELECT bm.id, bm.month_key, bm.base_budget_amount, bm.current_cash_amount, bm.saving_amount, bm.carry_over_amount, bm.updated_at
FROM budget_months bm
JOIN expense_books eb ON eb.id = bm.expense_book_id
WHERE eb.owner_user_id = $1 AND bm.month_key = $2`)).
		WithArgs("usr_001", "2026-03").
		WillReturnRows(sqlmock.NewRows([]string{"id", "month_key", "base_budget_amount", "current_cash_amount", "saving_amount", "carry_over_amount", "updated_at"}).
			AddRow("bmon_001", "2026-03", 510, 118, 200, 5, updatedAt))

	mock.ExpectQuery(regexp.QuoteMeta(`
SELECT id, name, kind, amount, enabled, note, billing_day_label, updated_at
FROM budget_item_entries
WHERE budget_month_id = $1
ORDER BY sort_order ASC, id ASC`)).
		WithArgs("bmon_001").
		WillReturnRows(sqlmock.NewRows([]string{"id", "name", "kind", "amount", "enabled", "note", "billing_day_label", "updated_at"}).
			AddRow("bitm_001", "Rent", "fixed", 100, true, "", "20일", updatedAt).
			AddRow("bitm_002", "Gym", "fixed", 30, false, "paused", "5일", updatedAt))

	mock.ExpectQuery(regexp.QuoteMeta(`
SELECT id, name, planned_amount, actual_amount, formula_hint, updated_at
FROM budget_buckets
WHERE budget_month_id = $1
ORDER BY id ASC`)).
		WithArgs("bmon_001").
		WillReturnRows(sqlmock.NewRows([]string{"id", "name", "planned_amount", "actual_amount", "formula_hint", "updated_at"}).
			AddRow("bbkt_001", "Food", 20, 18, "weekday + weekend", updatedAt))

	mock.ExpectQuery(regexp.QuoteMeta(`
SELECT id, label, due_day_label, note, updated_at
FROM billing_reminders
WHERE budget_month_id = $1
ORDER BY id ASC`)).
		WithArgs("bmon_001").
		WillReturnRows(sqlmock.NewRows([]string{"id", "label", "due_day_label", "note", "updated_at"}).
			AddRow("brem_001", "Internet", "25일", "check invoice", updatedAt))

	board, err := store.LoadBudgetBoard(context.Background(), "usr_001", "2026-03")
	if err != nil {
		t.Fatalf("load budget board: %v", err)
	}

	if board.Month.ID != "bmon_001" || board.Month.RemainingBudgetAmount != 195 {
		t.Fatalf("unexpected month payload: %#v", board.Month)
	}
	if board.Summary.FixedCostTotal != 100 || board.Summary.VariableBucketTotal != 20 || board.Summary.FreeCashAmount != 0 {
		t.Fatalf("unexpected summary: %#v", board.Summary)
	}
	if len(board.FixedItems) != 2 || len(board.VariableBuckets) != 1 || len(board.BillingReminders) != 1 {
		t.Fatalf("unexpected board collections: %#v", board)
	}
	if board.BillingReminders[0].Kind != "reminder" || board.BillingReminders[0].BillingDayLabel != "25일" {
		t.Fatalf("unexpected reminder payload: %#v", board.BillingReminders[0])
	}

	if err := mock.ExpectationsWereMet(); err != nil {
		t.Fatalf("expectations: %v", err)
	}
}

func TestPostgresBudgetStoreLoadBudgetBoardReturnsNotFoundForForeignOwner(t *testing.T) {
	db, mock, err := sqlmock.New()
	if err != nil {
		t.Fatalf("sqlmock: %v", err)
	}
	defer db.Close()

	store := NewPostgresBudgetStore(db)
	mock.ExpectQuery(regexp.QuoteMeta(`
SELECT bm.id, bm.month_key, bm.base_budget_amount, bm.current_cash_amount, bm.saving_amount, bm.carry_over_amount, bm.updated_at
FROM budget_months bm
JOIN expense_books eb ON eb.id = bm.expense_book_id
WHERE eb.owner_user_id = $1 AND bm.month_key = $2`)).
		WithArgs("usr_999", "2026-03").
		WillReturnError(sql.ErrNoRows)

	_, err = store.LoadBudgetBoard(context.Background(), "usr_999", "2026-03")
	if !errors.Is(err, ErrNotFound) {
		t.Fatalf("expected not found, got %v", err)
	}
}

func TestPostgresBudgetStoreSaveBudgetBoardReplacesMonthSnapshot(t *testing.T) {
	db, mock, err := sqlmock.New()
	if err != nil {
		t.Fatalf("sqlmock: %v", err)
	}
	defer db.Close()

	now := time.Date(2026, 3, 18, 8, 30, 0, 0, time.UTC)
	store := NewPostgresBudgetStore(db)
	store.now = func() time.Time { return now }
	idSequence := 0
	store.newID = func(prefix string) string {
		idSequence++
		return fmt.Sprintf("%s_gen_%d", prefix, idSequence)
	}

	board := domain.BudgetBoard{
		Month: domain.BudgetMonth{
			MonthKey:          "2026-03",
			BaseBudgetAmount:  510,
			CurrentCashAmount: 118,
			SavingAmount:      200,
		},
		FixedItems: []domain.BudgetItem{
			{ID: "bitm_keep", Name: "Rent", Kind: "fixed", Amount: 100, Enabled: true, BillingDayLabel: "20일"},
		},
		VariableBuckets: []domain.BudgetBucket{
			{Name: "Food", PlannedAmount: 20, ActualAmount: 12, FormulaHint: "weekday + weekend"},
		},
		BillingReminders: []domain.BudgetItem{
			{Name: "Internet", BillingDayLabel: "25일", Note: "check invoice"},
		},
	}

	mock.ExpectBegin()
	mock.ExpectQuery(regexp.QuoteMeta(`SELECT id FROM expense_books WHERE owner_user_id = $1`)).
		WithArgs("usr_001").
		WillReturnRows(sqlmock.NewRows([]string{"id"}).AddRow("book_001"))
	mock.ExpectQuery(regexp.QuoteMeta(`SELECT id FROM budget_months WHERE expense_book_id = $1 AND month_key = $2`)).
		WithArgs("book_001", "2026-03").
		WillReturnRows(sqlmock.NewRows([]string{"id"}).AddRow("bmon_existing"))
	mock.ExpectExec(regexp.QuoteMeta(`
UPDATE budget_months
SET base_budget_amount = $2,
    current_cash_amount = $3,
    saving_amount = $4,
    carry_over_amount = $5,
    remaining_budget_amount = $6,
    updated_at = $7
WHERE id = $1`)).
		WithArgs("bmon_existing", 510, 118, 200, 0, 190, now).
		WillReturnResult(sqlmock.NewResult(0, 1))
	mock.ExpectExec(regexp.QuoteMeta(`DELETE FROM billing_reminders WHERE budget_month_id = $1`)).
		WithArgs("bmon_existing").
		WillReturnResult(sqlmock.NewResult(0, 1))
	mock.ExpectExec(regexp.QuoteMeta(`DELETE FROM budget_item_entries WHERE budget_month_id = $1`)).
		WithArgs("bmon_existing").
		WillReturnResult(sqlmock.NewResult(0, 2))
	mock.ExpectExec(regexp.QuoteMeta(`DELETE FROM budget_buckets WHERE budget_month_id = $1`)).
		WithArgs("bmon_existing").
		WillReturnResult(sqlmock.NewResult(0, 2))
	mock.ExpectExec(regexp.QuoteMeta(`
INSERT INTO budget_item_entries (
    id, budget_month_id, template_id, name, kind, amount, enabled,
    note, billing_day_label, sort_order, updated_at
)
VALUES ($1, $2, NULL, $3, $4, $5, $6, $7, $8, $9, $10)`)).
		WithArgs("bitm_keep", "bmon_existing", "Rent", "fixed", 100, true, "", "20일", 0, now).
		WillReturnResult(sqlmock.NewResult(0, 1))
	mock.ExpectExec(regexp.QuoteMeta(`
INSERT INTO budget_buckets (
    id, budget_month_id, name, planned_amount, actual_amount, formula_hint, updated_at
)
VALUES ($1, $2, $3, $4, $5, $6, $7)`)).
		WithArgs("bbkt_gen_1", "bmon_existing", "Food", 20, 12, "weekday + weekend", now).
		WillReturnResult(sqlmock.NewResult(0, 1))
	mock.ExpectExec(regexp.QuoteMeta(`
INSERT INTO billing_reminders (
    id, budget_month_id, budget_item_entry_id, label, due_day_label, note, updated_at
)
VALUES ($1, $2, NULL, $3, $4, $5, $6)`)).
		WithArgs("brem_gen_2", "bmon_existing", "Internet", "25일", "check invoice", now).
		WillReturnResult(sqlmock.NewResult(0, 1))
	mock.ExpectCommit()

	saved, err := store.SaveBudgetBoard(context.Background(), "usr_001", board)
	if err != nil {
		t.Fatalf("save budget board: %v", err)
	}

	if saved.Month.ID != "bmon_existing" || saved.Month.RemainingBudgetAmount != 190 {
		t.Fatalf("unexpected saved month: %#v", saved.Month)
	}
	if saved.Summary.FixedCostTotal != 100 || saved.Summary.VariableBucketTotal != 20 || saved.Summary.FreeCashAmount != 6 {
		t.Fatalf("unexpected saved summary: %#v", saved.Summary)
	}
	if saved.FixedItems[0].UpdatedAt != now.Format(time.RFC3339) {
		t.Fatalf("expected fixed item updated_at, got %#v", saved.FixedItems[0])
	}
	if saved.BillingReminders[0].Kind != "reminder" {
		t.Fatalf("expected reminder kind to be set, got %#v", saved.BillingReminders[0])
	}

	if err := mock.ExpectationsWereMet(); err != nil {
		t.Fatalf("expectations: %v", err)
	}
}

func TestPostgresBudgetStoreSaveBudgetBoardCreatesOwnerSnapshot(t *testing.T) {
	db, mock, err := sqlmock.New()
	if err != nil {
		t.Fatalf("sqlmock: %v", err)
	}
	defer db.Close()

	now := time.Date(2026, 4, 1, 9, 0, 0, 0, time.UTC)
	store := NewPostgresBudgetStore(db)
	store.now = func() time.Time { return now }
	idSequence := 0
	store.newID = func(prefix string) string {
		idSequence++
		return fmt.Sprintf("%s_gen_%d", prefix, idSequence)
	}

	board := domain.BudgetBoard{
		Month: domain.BudgetMonth{
			MonthKey:          "2026-04",
			BaseBudgetAmount:  300,
			CurrentCashAmount: 150,
			SavingAmount:      50,
			CarryOverAmount:   10,
		},
		FixedItems: []domain.BudgetItem{
			{Name: "Rent", Kind: "fixed", Amount: 90, Enabled: true, BillingDayLabel: "5일"},
		},
		VariableBuckets: []domain.BudgetBucket{
			{Name: "Food", PlannedAmount: 40, ActualAmount: 15},
		},
		BillingReminders: []domain.BudgetItem{
			{Name: "Insurance", BillingDayLabel: "10일"},
		},
	}

	mock.ExpectBegin()
	mock.ExpectQuery(regexp.QuoteMeta(`SELECT id FROM expense_books WHERE owner_user_id = $1`)).
		WithArgs("usr_002").
		WillReturnError(sql.ErrNoRows)
	mock.ExpectExec(regexp.QuoteMeta(`
INSERT INTO expense_books (id, owner_user_id, name, currency_code, created_at, updated_at)
VALUES ($1, $2, $3, $4, $5, $5)`)).
		WithArgs("book_gen_1", "usr_002", "Personal Budget", "KRW", now).
		WillReturnResult(sqlmock.NewResult(0, 1))
	mock.ExpectQuery(regexp.QuoteMeta(`SELECT id FROM budget_months WHERE expense_book_id = $1 AND month_key = $2`)).
		WithArgs("book_gen_1", "2026-04").
		WillReturnError(sql.ErrNoRows)
	mock.ExpectExec(regexp.QuoteMeta(`
INSERT INTO budget_months (
    id, expense_book_id, month_key, base_budget_amount, current_cash_amount,
    saving_amount, carry_over_amount, remaining_budget_amount, updated_at
)
VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9)`)).
		WithArgs("bmon_gen_2", "book_gen_1", "2026-04", 300, 150, 50, 10, 130, now).
		WillReturnResult(sqlmock.NewResult(0, 1))
	mock.ExpectExec(regexp.QuoteMeta(`DELETE FROM billing_reminders WHERE budget_month_id = $1`)).
		WithArgs("bmon_gen_2").
		WillReturnResult(sqlmock.NewResult(0, 0))
	mock.ExpectExec(regexp.QuoteMeta(`DELETE FROM budget_item_entries WHERE budget_month_id = $1`)).
		WithArgs("bmon_gen_2").
		WillReturnResult(sqlmock.NewResult(0, 0))
	mock.ExpectExec(regexp.QuoteMeta(`DELETE FROM budget_buckets WHERE budget_month_id = $1`)).
		WithArgs("bmon_gen_2").
		WillReturnResult(sqlmock.NewResult(0, 0))
	mock.ExpectExec(regexp.QuoteMeta(`
INSERT INTO budget_item_entries (
    id, budget_month_id, template_id, name, kind, amount, enabled,
    note, billing_day_label, sort_order, updated_at
)
VALUES ($1, $2, NULL, $3, $4, $5, $6, $7, $8, $9, $10)`)).
		WithArgs("bitm_gen_3", "bmon_gen_2", "Rent", "fixed", 90, true, "", "5일", 0, now).
		WillReturnResult(sqlmock.NewResult(0, 1))
	mock.ExpectExec(regexp.QuoteMeta(`
INSERT INTO budget_buckets (
    id, budget_month_id, name, planned_amount, actual_amount, formula_hint, updated_at
)
VALUES ($1, $2, $3, $4, $5, $6, $7)`)).
		WithArgs("bbkt_gen_4", "bmon_gen_2", "Food", 40, 15, "", now).
		WillReturnResult(sqlmock.NewResult(0, 1))
	mock.ExpectExec(regexp.QuoteMeta(`
INSERT INTO billing_reminders (
    id, budget_month_id, budget_item_entry_id, label, due_day_label, note, updated_at
)
VALUES ($1, $2, NULL, $3, $4, $5, $6)`)).
		WithArgs("brem_gen_5", "bmon_gen_2", "Insurance", "10일", "", now).
		WillReturnResult(sqlmock.NewResult(0, 1))
	mock.ExpectCommit()

	saved, err := store.SaveBudgetBoard(context.Background(), "usr_002", board)
	if err != nil {
		t.Fatalf("save budget board: %v", err)
	}

	if saved.Month.ID != "bmon_gen_2" || saved.Month.UpdatedAt != now.Format(time.RFC3339) {
		t.Fatalf("unexpected created month: %#v", saved.Month)
	}
	if saved.Month.RemainingBudgetAmount != 130 {
		t.Fatalf("unexpected remaining budget: %#v", saved.Month)
	}
	if saved.Summary.FixedCostTotal != 90 || saved.Summary.VariableBucketTotal != 40 || saved.Summary.FreeCashAmount != 45 {
		t.Fatalf("unexpected summary: %#v", saved.Summary)
	}
	if saved.FixedItems[0].ID != "bitm_gen_3" || saved.VariableBuckets[0].ID != "bbkt_gen_4" || saved.BillingReminders[0].ID != "brem_gen_5" {
		t.Fatalf("expected generated IDs, got %#v", saved)
	}
	if saved.BillingReminders[0].Kind != "reminder" {
		t.Fatalf("expected reminder kind, got %#v", saved.BillingReminders[0])
	}

	if err := mock.ExpectationsWereMet(); err != nil {
		t.Fatalf("expectations: %v", err)
	}
}
