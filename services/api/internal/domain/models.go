package domain

type User struct {
	ID          string `json:"id"`
	Email       string `json:"email"`
	DisplayName string `json:"display_name"`
}

type Me struct {
	User                  User       `json:"user"`
	PersonalCalendar      Calendar   `json:"personal_calendar"`
	SharedCalendars       []Calendar `json:"shared_calendars"`
	CurrentBudgetMonthKey string     `json:"current_budget_month_key"`
}

type Calendar struct {
	ID             string `json:"id"`
	Kind           string `json:"kind"`
	Name           string `json:"name"`
	Color          string `json:"color"`
	MembershipRole string `json:"membership_role,omitempty"`
	UpdatedAt      string `json:"updated_at"`
}

type CalendarInvite struct {
	ID                   string `json:"id"`
	CalendarID           string `json:"calendar_id"`
	CalendarName         string `json:"calendar_name,omitempty"`
	Email                string `json:"email"`
	DeliveryChannel      string `json:"delivery_channel,omitempty"`
	Role                 string `json:"role"`
	InviteCode           string `json:"invite_code"`
	InviteURL            string `json:"invite_url,omitempty"`
	InvitedByUserID      string `json:"invited_by_user_id,omitempty"`
	InvitedByDisplayName string `json:"invited_by_display_name,omitempty"`
	AcceptedByUserID     string `json:"accepted_by_user_id,omitempty"`
	AcceptedAt           string `json:"accepted_at,omitempty"`
	ExpiresAt            string `json:"expires_at,omitempty"`
	UpdatedAt            string `json:"updated_at"`
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

type BudgetTemplate struct {
	ID                string `json:"id"`
	Name              string `json:"name"`
	Kind              string `json:"kind"`
	DefaultAmount     int    `json:"default_amount"`
	DefaultEnabled    bool   `json:"default_enabled"`
	DefaultNote       string `json:"default_note,omitempty"`
	DefaultBillingDay string `json:"default_billing_day,omitempty"`
	SortOrder         int    `json:"sort_order"`
	UpdatedAt         string `json:"updated_at"`
}

type BudgetTemplates struct {
	FixedItems []BudgetTemplate `json:"fixed_items"`
}

type BudgetBoard struct {
	Month            BudgetMonth    `json:"month"`
	Summary          BudgetSummary  `json:"summary"`
	FixedItems       []BudgetItem   `json:"fixed_items"`
	VariableBuckets  []BudgetBucket `json:"variable_buckets"`
	BillingReminders []BudgetItem   `json:"billing_reminders"`
}
