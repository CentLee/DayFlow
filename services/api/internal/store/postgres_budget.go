package store

import (
	"context"
	"crypto/rand"
	"database/sql"
	"encoding/hex"
	"errors"
	"fmt"
	"time"

	"github.com/kakao-ent/dayflow/services/api/internal/domain"
)

type PostgresBudgetStore struct {
	db    *sql.DB
	now   func() time.Time
	newID func(prefix string) string
}

func NewPostgresBudgetStore(db *sql.DB) *PostgresBudgetStore {
	return &PostgresBudgetStore{
		db:    db,
		now:   func() time.Time { return time.Now().UTC() },
		newID: newStoreID,
	}
}

func (s *PostgresBudgetStore) LoadBudgetBoard(ctx context.Context, ownerUserID, monthKey string) (domain.BudgetBoard, error) {
	month, err := s.loadBudgetMonth(ctx, ownerUserID, monthKey)
	if err != nil {
		return domain.BudgetBoard{}, err
	}

	fixedItems, err := s.loadBudgetItems(ctx, month.ID)
	if err != nil {
		return domain.BudgetBoard{}, err
	}
	variableBuckets, err := s.loadBudgetBuckets(ctx, month.ID)
	if err != nil {
		return domain.BudgetBoard{}, err
	}
	billingReminders, err := s.loadBillingReminders(ctx, month.ID)
	if err != nil {
		return domain.BudgetBoard{}, err
	}

	summary, remaining := deriveBudgetSummary(month, fixedItems, variableBuckets)
	month.RemainingBudgetAmount = remaining

	return domain.BudgetBoard{
		Month:            month,
		Summary:          summary,
		FixedItems:       fixedItems,
		VariableBuckets:  variableBuckets,
		BillingReminders: billingReminders,
	}, nil
}

func (s *PostgresBudgetStore) SaveBudgetBoard(ctx context.Context, ownerUserID string, board domain.BudgetBoard) (domain.BudgetBoard, error) {
	if board.Month.MonthKey == "" {
		return domain.BudgetBoard{}, fmt.Errorf("budget month key is required: %w", ErrInvalidInput)
	}

	board.Summary, board.Month.RemainingBudgetAmount = deriveBudgetSummary(board.Month, board.FixedItems, board.VariableBuckets)
	now := s.now()
	board.Month.UpdatedAt = now.Format(time.RFC3339)

	tx, err := s.db.BeginTx(ctx, nil)
	if err != nil {
		return domain.BudgetBoard{}, fmt.Errorf("begin budget transaction: %w", err)
	}
	defer func() {
		if err != nil {
			_ = tx.Rollback()
		}
	}()

	expenseBookID, err := s.ensureExpenseBook(ctx, tx, ownerUserID, now)
	if err != nil {
		return domain.BudgetBoard{}, err
	}

	board.Month.ID, err = s.upsertBudgetMonth(ctx, tx, expenseBookID, board.Month, now)
	if err != nil {
		return domain.BudgetBoard{}, err
	}

	if err = s.replaceBudgetSnapshot(ctx, tx, board.Month.ID, &board, now); err != nil {
		return domain.BudgetBoard{}, err
	}

	if err = tx.Commit(); err != nil {
		return domain.BudgetBoard{}, fmt.Errorf("commit budget transaction: %w", err)
	}

	for index := range board.FixedItems {
		board.FixedItems[index].UpdatedAt = now.Format(time.RFC3339)
	}
	for index := range board.VariableBuckets {
		board.VariableBuckets[index].UpdatedAt = now.Format(time.RFC3339)
	}
	for index := range board.BillingReminders {
		board.BillingReminders[index].UpdatedAt = now.Format(time.RFC3339)
		if board.BillingReminders[index].Kind == "" {
			board.BillingReminders[index].Kind = "reminder"
		}
	}

	return board, nil
}

func (s *PostgresBudgetStore) loadBudgetMonth(ctx context.Context, ownerUserID, monthKey string) (domain.BudgetMonth, error) {
	const query = `
SELECT bm.id, bm.month_key, bm.base_budget_amount, bm.current_cash_amount, bm.saving_amount, bm.carry_over_amount, bm.updated_at
FROM budget_months bm
JOIN expense_books eb ON eb.id = bm.expense_book_id
WHERE eb.owner_user_id = $1 AND bm.month_key = $2`

	var month domain.BudgetMonth
	var updatedAt time.Time
	if err := s.db.QueryRowContext(ctx, query, ownerUserID, monthKey).Scan(
		&month.ID,
		&month.MonthKey,
		&month.BaseBudgetAmount,
		&month.CurrentCashAmount,
		&month.SavingAmount,
		&month.CarryOverAmount,
		&updatedAt,
	); err != nil {
		if errors.Is(err, sql.ErrNoRows) {
			return domain.BudgetMonth{}, ErrNotFound
		}
		return domain.BudgetMonth{}, fmt.Errorf("load budget month: %w", err)
	}
	month.UpdatedAt = updatedAt.UTC().Format(time.RFC3339)
	return month, nil
}

func (s *PostgresBudgetStore) loadBudgetItems(ctx context.Context, budgetMonthID string) ([]domain.BudgetItem, error) {
	const query = `
SELECT id, name, kind, amount, enabled, note, billing_day_label, updated_at
FROM budget_item_entries
WHERE budget_month_id = $1
ORDER BY sort_order ASC, id ASC`

	rows, err := s.db.QueryContext(ctx, query, budgetMonthID)
	if err != nil {
		return nil, fmt.Errorf("load budget items: %w", err)
	}
	defer rows.Close()

	items := make([]domain.BudgetItem, 0)
	for rows.Next() {
		var item domain.BudgetItem
		var updatedAt time.Time
		if err := rows.Scan(&item.ID, &item.Name, &item.Kind, &item.Amount, &item.Enabled, &item.Note, &item.BillingDayLabel, &updatedAt); err != nil {
			return nil, fmt.Errorf("scan budget item: %w", err)
		}
		item.UpdatedAt = updatedAt.UTC().Format(time.RFC3339)
		items = append(items, item)
	}
	if err := rows.Err(); err != nil {
		return nil, fmt.Errorf("iterate budget items: %w", err)
	}
	return items, nil
}

func (s *PostgresBudgetStore) loadBudgetBuckets(ctx context.Context, budgetMonthID string) ([]domain.BudgetBucket, error) {
	const query = `
SELECT id, name, planned_amount, actual_amount, formula_hint, updated_at
FROM budget_buckets
WHERE budget_month_id = $1
ORDER BY id ASC`

	rows, err := s.db.QueryContext(ctx, query, budgetMonthID)
	if err != nil {
		return nil, fmt.Errorf("load budget buckets: %w", err)
	}
	defer rows.Close()

	buckets := make([]domain.BudgetBucket, 0)
	for rows.Next() {
		var bucket domain.BudgetBucket
		var updatedAt time.Time
		if err := rows.Scan(&bucket.ID, &bucket.Name, &bucket.PlannedAmount, &bucket.ActualAmount, &bucket.FormulaHint, &updatedAt); err != nil {
			return nil, fmt.Errorf("scan budget bucket: %w", err)
		}
		bucket.UpdatedAt = updatedAt.UTC().Format(time.RFC3339)
		buckets = append(buckets, bucket)
	}
	if err := rows.Err(); err != nil {
		return nil, fmt.Errorf("iterate budget buckets: %w", err)
	}
	return buckets, nil
}

func (s *PostgresBudgetStore) loadBillingReminders(ctx context.Context, budgetMonthID string) ([]domain.BudgetItem, error) {
	const query = `
SELECT id, label, due_day_label, note, updated_at
FROM billing_reminders
WHERE budget_month_id = $1
ORDER BY id ASC`

	rows, err := s.db.QueryContext(ctx, query, budgetMonthID)
	if err != nil {
		return nil, fmt.Errorf("load billing reminders: %w", err)
	}
	defer rows.Close()

	items := make([]domain.BudgetItem, 0)
	for rows.Next() {
		var item domain.BudgetItem
		var updatedAt time.Time
		if err := rows.Scan(&item.ID, &item.Name, &item.BillingDayLabel, &item.Note, &updatedAt); err != nil {
			return nil, fmt.Errorf("scan billing reminder: %w", err)
		}
		item.Kind = "reminder"
		item.UpdatedAt = updatedAt.UTC().Format(time.RFC3339)
		items = append(items, item)
	}
	if err := rows.Err(); err != nil {
		return nil, fmt.Errorf("iterate billing reminders: %w", err)
	}
	return items, nil
}

func (s *PostgresBudgetStore) ensureExpenseBook(ctx context.Context, tx *sql.Tx, ownerUserID string, now time.Time) (string, error) {
	const selectQuery = `SELECT id FROM expense_books WHERE owner_user_id = $1`

	var expenseBookID string
	if err := tx.QueryRowContext(ctx, selectQuery, ownerUserID).Scan(&expenseBookID); err == nil {
		return expenseBookID, nil
	} else if !errors.Is(err, sql.ErrNoRows) {
		return "", fmt.Errorf("load expense book: %w", err)
	}

	expenseBookID = s.newID("book")
	const insertQuery = `
INSERT INTO expense_books (id, owner_user_id, name, currency_code, created_at, updated_at)
VALUES ($1, $2, $3, $4, $5, $5)`
	if _, err := tx.ExecContext(ctx, insertQuery, expenseBookID, ownerUserID, "Personal Budget", "KRW", now); err != nil {
		return "", fmt.Errorf("create expense book: %w", err)
	}
	return expenseBookID, nil
}

func (s *PostgresBudgetStore) upsertBudgetMonth(ctx context.Context, tx *sql.Tx, expenseBookID string, month domain.BudgetMonth, now time.Time) (string, error) {
	const selectQuery = `SELECT id FROM budget_months WHERE expense_book_id = $1 AND month_key = $2`

	var monthID string
	if err := tx.QueryRowContext(ctx, selectQuery, expenseBookID, month.MonthKey).Scan(&monthID); err != nil {
		if !errors.Is(err, sql.ErrNoRows) {
			return "", fmt.Errorf("load budget month for upsert: %w", err)
		}
		monthID = month.ID
		if monthID == "" {
			monthID = s.newID("bmon")
		}
		const insertQuery = `
INSERT INTO budget_months (
    id, expense_book_id, month_key, base_budget_amount, current_cash_amount,
    saving_amount, carry_over_amount, remaining_budget_amount, updated_at
)
VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9)`
		if _, err := tx.ExecContext(ctx, insertQuery,
			monthID,
			expenseBookID,
			month.MonthKey,
			month.BaseBudgetAmount,
			month.CurrentCashAmount,
			month.SavingAmount,
			month.CarryOverAmount,
			month.RemainingBudgetAmount,
			now,
		); err != nil {
			return "", fmt.Errorf("insert budget month: %w", err)
		}
		return monthID, nil
	}

	const updateQuery = `
UPDATE budget_months
SET base_budget_amount = $2,
    current_cash_amount = $3,
    saving_amount = $4,
    carry_over_amount = $5,
    remaining_budget_amount = $6,
    updated_at = $7
WHERE id = $1`
	if _, err := tx.ExecContext(ctx, updateQuery,
		monthID,
		month.BaseBudgetAmount,
		month.CurrentCashAmount,
		month.SavingAmount,
		month.CarryOverAmount,
		month.RemainingBudgetAmount,
		now,
	); err != nil {
		return "", fmt.Errorf("update budget month: %w", err)
	}
	return monthID, nil
}

func (s *PostgresBudgetStore) replaceBudgetSnapshot(ctx context.Context, tx *sql.Tx, budgetMonthID string, board *domain.BudgetBoard, now time.Time) error {
	deleteStatements := []string{
		`DELETE FROM billing_reminders WHERE budget_month_id = $1`,
		`DELETE FROM budget_item_entries WHERE budget_month_id = $1`,
		`DELETE FROM budget_buckets WHERE budget_month_id = $1`,
	}
	for _, statement := range deleteStatements {
		if _, err := tx.ExecContext(ctx, statement, budgetMonthID); err != nil {
			return fmt.Errorf("reset budget snapshot: %w", err)
		}
	}

	const insertItemQuery = `
INSERT INTO budget_item_entries (
    id, budget_month_id, template_id, name, kind, amount, enabled,
    note, billing_day_label, sort_order, updated_at
)
VALUES ($1, $2, NULL, $3, $4, $5, $6, $7, $8, $9, $10)`
	for index, item := range board.FixedItems {
		itemID := item.ID
		if itemID == "" {
			itemID = s.newID("bitm")
		}
		board.FixedItems[index].ID = itemID
		if _, err := tx.ExecContext(ctx, insertItemQuery,
			itemID,
			budgetMonthID,
			item.Name,
			item.Kind,
			item.Amount,
			item.Enabled,
			item.Note,
			item.BillingDayLabel,
			index,
			now,
		); err != nil {
			return fmt.Errorf("insert budget item: %w", err)
		}
	}

	const insertBucketQuery = `
INSERT INTO budget_buckets (
    id, budget_month_id, name, planned_amount, actual_amount, formula_hint, updated_at
)
VALUES ($1, $2, $3, $4, $5, $6, $7)`
	for index, bucket := range board.VariableBuckets {
		bucketID := bucket.ID
		if bucketID == "" {
			bucketID = s.newID("bbkt")
		}
		board.VariableBuckets[index].ID = bucketID
		if _, err := tx.ExecContext(ctx, insertBucketQuery,
			bucketID,
			budgetMonthID,
			bucket.Name,
			bucket.PlannedAmount,
			bucket.ActualAmount,
			bucket.FormulaHint,
			now,
		); err != nil {
			return fmt.Errorf("insert budget bucket: %w", err)
		}
	}

	const insertReminderQuery = `
INSERT INTO billing_reminders (
    id, budget_month_id, budget_item_entry_id, label, due_day_label, note, updated_at
)
VALUES ($1, $2, NULL, $3, $4, $5, $6)`
	for index, reminder := range board.BillingReminders {
		reminderID := reminder.ID
		if reminderID == "" {
			reminderID = s.newID("brem")
		}
		board.BillingReminders[index].ID = reminderID
		if _, err := tx.ExecContext(ctx, insertReminderQuery,
			reminderID,
			budgetMonthID,
			reminder.Name,
			reminder.BillingDayLabel,
			reminder.Note,
			now,
		); err != nil {
			return fmt.Errorf("insert billing reminder: %w", err)
		}
	}

	return nil
}

func deriveBudgetSummary(month domain.BudgetMonth, fixedItems []domain.BudgetItem, variableBuckets []domain.BudgetBucket) (domain.BudgetSummary, int) {
	fixedCostTotal := 0
	for _, item := range fixedItems {
		if item.Kind == "fixed" && item.Enabled {
			fixedCostTotal += item.Amount
		}
	}

	variableBucketTotal := 0
	variableActualTotal := 0
	for _, bucket := range variableBuckets {
		variableBucketTotal += bucket.PlannedAmount
		variableActualTotal += bucket.ActualAmount
	}

	remaining := month.BaseBudgetAmount - fixedCostTotal - month.SavingAmount - variableBucketTotal + month.CarryOverAmount
	return domain.BudgetSummary{
		FixedCostTotal:      fixedCostTotal,
		VariableBucketTotal: variableBucketTotal,
		FreeCashAmount:      month.CurrentCashAmount - fixedCostTotal - variableActualTotal,
	}, remaining
}

func newStoreID(prefix string) string {
	buffer := make([]byte, 6)
	if _, err := rand.Read(buffer); err != nil {
		return fmt.Sprintf("%s_%d", prefix, time.Now().UTC().UnixNano())
	}
	return prefix + "_" + hex.EncodeToString(buffer)
}
