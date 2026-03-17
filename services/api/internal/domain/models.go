package domain

type User struct {
	ID          string `json:"id"`
	Email       string `json:"email"`
	DisplayName string `json:"display_name"`
}

type Calendar struct {
	ID        string `json:"id"`
	Name      string `json:"name"`
	Color     string `json:"color"`
	UpdatedAt string `json:"updated_at"`
}

type Event struct {
	ID         string `json:"id"`
	CalendarID string `json:"calendar_id"`
	Title      string `json:"title"`
	Notes      string `json:"notes"`
	StartsAt   string `json:"starts_at"`
	EndsAt     string `json:"ends_at"`
	AllDay     bool   `json:"all_day"`
	UpdatedAt  string `json:"updated_at"`
}

type BudgetMonth struct {
	ID                    string `json:"id"`
	MonthKey              string `json:"month_key"`
	BaseBudgetAmount      int    `json:"base_budget_amount"`
	CurrentCashAmount     int    `json:"current_cash_amount"`
	SavingAmount          int    `json:"saving_amount"`
	CarryOverAmount       int    `json:"carry_over_amount"`
	RemainingBudgetAmount int    `json:"remaining_budget_amount"`
	UpdatedAt             string `json:"updated_at"`
}

type BudgetItem struct {
	ID              string `json:"id"`
	Name            string `json:"name"`
	Kind            string `json:"kind"`
	Amount          int    `json:"amount"`
	Enabled         bool   `json:"enabled"`
	Note            string `json:"note,omitempty"`
	BillingDayLabel string `json:"billing_day_label,omitempty"`
	UpdatedAt       string `json:"updated_at"`
}

type BudgetBucket struct {
	ID            string `json:"id"`
	Name          string `json:"name"`
	PlannedAmount int    `json:"planned_amount"`
	ActualAmount  int    `json:"actual_amount"`
	FormulaHint   string `json:"formula_hint,omitempty"`
	UpdatedAt     string `json:"updated_at"`
}

type BudgetSummary struct {
	FixedCostTotal      int `json:"fixed_cost_total"`
	VariableBucketTotal int `json:"variable_bucket_total"`
	FreeCashAmount      int `json:"free_cash_amount"`
}

type BudgetBoard struct {
	Month            BudgetMonth    `json:"month"`
	Summary          BudgetSummary  `json:"summary"`
	FixedItems       []BudgetItem   `json:"fixed_items"`
	VariableBuckets  []BudgetBucket `json:"variable_buckets"`
	BillingReminders []BudgetItem   `json:"billing_reminders"`
}
