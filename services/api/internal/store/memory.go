package store

import (
	"time"

	"github.com/kakao-ent/dayflow/services/api/internal/domain"
)

type MemoryStore struct{}

func NewMemoryStore() *MemoryStore {
	return &MemoryStore{}
}

func (s *MemoryStore) Me() domain.User {
	return domain.User{
		ID:          "usr_001",
		Email:       "owner@dayflow.local",
		DisplayName: "DayFlow Owner",
	}
}

func (s *MemoryStore) Calendars() []domain.Calendar {
	now := time.Now().UTC().Format(time.RFC3339)
	return []domain.Calendar{
		{ID: "cal_001", Name: "Personal", Color: "#1F6B5C", UpdatedAt: now},
		{ID: "cal_002", Name: "Shared Home", Color: "#D8A21D", UpdatedAt: now},
	}
}

func (s *MemoryStore) Events(calendarID string) []domain.Event {
	now := time.Now().UTC().Format(time.RFC3339)
	return []domain.Event{
		{
			ID:         "evt_001",
			CalendarID: calendarID,
			Title:      "보험비 정산",
			Notes:      "25일 기준 확인",
			StartsAt:   now,
			EndsAt:     now,
			AllDay:     false,
			UpdatedAt:  now,
		},
	}
}

func (s *MemoryStore) BudgetBoard(monthKey string) domain.BudgetBoard {
	now := time.Now().UTC().Format(time.RFC3339)
	fixed := []domain.BudgetItem{
		{ID: "itm_001", Name: "월세 및 관리비", Kind: "fixed", Amount: 21, Enabled: true, BillingDayLabel: "20일", UpdatedAt: now},
		{ID: "itm_002", Name: "대출이자", Kind: "fixed", Amount: 36, Enabled: true, BillingDayLabel: "5일", UpdatedAt: now},
		{ID: "itm_003", Name: "핸드폰요금", Kind: "fixed", Amount: 8, Enabled: true, BillingDayLabel: "15일", UpdatedAt: now},
		{ID: "itm_004", Name: "신용카드", Kind: "fixed", Amount: 88, Enabled: true, BillingDayLabel: "26일", UpdatedAt: now},
	}
	buckets := []domain.BudgetBucket{
		{ID: "bkt_001", Name: "점심 및 주말 식대", PlannedAmount: 12, ActualAmount: 0, FormulaHint: "평일 1 + 주말 3", UpdatedAt: now},
		{ID: "bkt_002", Name: "유동 금액", PlannedAmount: 0, ActualAmount: 0, UpdatedAt: now},
	}
	return domain.BudgetBoard{
		Month: domain.BudgetMonth{
			ID:                    "bmon_001",
			MonthKey:              monthKey,
			BaseBudgetAmount:      510,
			CurrentCashAmount:     118,
			SavingAmount:          200,
			CarryOverAmount:       0,
			RemainingBudgetAmount: 145,
			UpdatedAt:             now,
		},
		Summary: domain.BudgetSummary{
			FixedCostTotal:      153,
			VariableBucketTotal: 12,
			FreeCashAmount:      118,
		},
		FixedItems:      fixed,
		VariableBuckets: buckets,
		BillingReminders: []domain.BudgetItem{
			{ID: "rem_001", Name: "인터넷", Kind: "reminder", BillingDayLabel: "25일", UpdatedAt: now},
			{ID: "rem_002", Name: "전기 정산", Kind: "reminder", BillingDayLabel: "월말일", UpdatedAt: now},
		},
	}
}
