package store

import (
	"crypto/rand"
	"encoding/hex"
	"errors"
	"fmt"
	"strings"
	"sync"
	"time"

	"golang.org/x/crypto/bcrypt"

	"github.com/kakao-ent/dayflow/services/api/internal/domain"
)

var (
	ErrEmailTaken          = errors.New("email already registered")
	ErrInvalidCredentials  = errors.New("invalid credentials")
	ErrInvalidInvite       = errors.New("invalid invite")
	ErrInviteEmailMismatch = errors.New("invite email mismatch")
)

type MemoryStore struct {
	mu       sync.Mutex
	users    map[string]storedUser
	userIDs  map[string]string
	sessions map[string]string
	invites  map[string]invite
	counter  int
	monthKey string
	ownerID  string
}

type storedUser struct {
	User                  domain.User
	PasswordHash          []byte
	OwnedCalendars        []domain.Calendar
	SharedCalendars       []domain.Calendar
	CurrentBudgetMonthKey string
}

type invite struct {
	Code            string
	Email           string
	SharedCalendars []domain.Calendar
}

func NewMemoryStore() *MemoryStore {
	now := time.Now().UTC().Format(time.RFC3339)
	monthKey := time.Now().UTC().Format("2006-01")
	owner := domain.User{
		ID:          "usr_001",
		Email:       "owner@dayflow.local",
		DisplayName: "DayFlow Owner",
	}
	personalCalendar := domain.Calendar{ID: "cal_001", Name: "Personal", Color: "#1F6B5C", UpdatedAt: now}
	sharedCalendar := domain.Calendar{ID: "cal_002", Name: "Shared Home", Color: "#D8A21D", UpdatedAt: now}

	store := &MemoryStore{
		users:    make(map[string]storedUser),
		userIDs:  make(map[string]string),
		sessions: make(map[string]string),
		invites:  make(map[string]invite),
		counter:  1,
		monthKey: monthKey,
		ownerID:  owner.ID,
	}

	store.mustSeedUser(storedUser{
		User:                  owner,
		PasswordHash:          mustHashPassword("secret1234"),
		OwnedCalendars:        []domain.Calendar{personalCalendar, sharedCalendar},
		SharedCalendars:       []domain.Calendar{},
		CurrentBudgetMonthKey: monthKey,
	})

	store.invites["invite_abc"] = invite{
		Code:  "invite_abc",
		Email: "user@example.com",
		SharedCalendars: []domain.Calendar{
			sharedCalendar,
		},
	}

	return store
}

func (s *MemoryStore) mustSeedUser(user storedUser) {
	s.users[normalizeEmail(user.User.Email)] = user
	s.userIDs[user.User.ID] = normalizeEmail(user.User.Email)
}

func (s *MemoryStore) Register(email, displayName, password, inviteCode string) (domain.User, string, error) {
	s.mu.Lock()
	defer s.mu.Unlock()

	normalizedEmail := normalizeEmail(email)
	inviteRecord, ok := s.invites[inviteCode]
	if !ok {
		return domain.User{}, "", ErrInvalidInvite
	}
	if normalizeEmail(inviteRecord.Email) != normalizedEmail {
		return domain.User{}, "", ErrInviteEmailMismatch
	}
	if _, exists := s.users[normalizedEmail]; exists {
		return domain.User{}, "", ErrEmailTaken
	}

	s.counter++
	user := domain.User{
		ID:          fmt.Sprintf("usr_%03d", s.counter),
		Email:       normalizedEmail,
		DisplayName: displayName,
	}
	stored := storedUser{
		User:                  user,
		PasswordHash:          mustHashPassword(password),
		OwnedCalendars:        []domain.Calendar{},
		SharedCalendars:       cloneCalendars(inviteRecord.SharedCalendars),
		CurrentBudgetMonthKey: s.monthKey,
	}
	s.users[normalizedEmail] = stored
	s.userIDs[user.ID] = normalizedEmail
	delete(s.invites, inviteCode)

	token := newToken()
	s.sessions[token] = user.ID
	return user, token, nil
}

func (s *MemoryStore) Login(email, password string) (domain.User, string, error) {
	s.mu.Lock()
	defer s.mu.Unlock()

	stored, ok := s.users[normalizeEmail(email)]
	if !ok {
		return domain.User{}, "", ErrInvalidCredentials
	}
	if err := bcrypt.CompareHashAndPassword(stored.PasswordHash, []byte(password)); err != nil {
		return domain.User{}, "", ErrInvalidCredentials
	}

	token := newToken()
	s.sessions[token] = stored.User.ID
	return stored.User, token, nil
}

func (s *MemoryStore) AuthenticatedMe(token string) (domain.Me, bool) {
	s.mu.Lock()
	defer s.mu.Unlock()

	userID, ok := s.sessions[token]
	if !ok {
		return domain.Me{}, false
	}
	normalizedEmail, ok := s.userIDs[userID]
	if !ok {
		return domain.Me{}, false
	}
	stored, ok := s.users[normalizedEmail]
	if !ok {
		return domain.Me{}, false
	}

	return domain.Me{
		User:                  stored.User,
		OwnedCalendars:        cloneCalendars(stored.OwnedCalendars),
		SharedCalendars:       cloneCalendars(stored.SharedCalendars),
		CurrentBudgetMonthKey: stored.CurrentBudgetMonthKey,
	}, true
}

func (s *MemoryStore) Calendars() []domain.Calendar {
	s.mu.Lock()
	defer s.mu.Unlock()

	me, ok := s.userByID(s.ownerID)
	if !ok {
		return nil
	}
	return cloneCalendars(me.OwnedCalendars)
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

func (s *MemoryStore) userByID(userID string) (storedUser, bool) {
	normalizedEmail, ok := s.userIDs[userID]
	if !ok {
		return storedUser{}, false
	}
	stored, ok := s.users[normalizedEmail]
	return stored, ok
}

func cloneCalendars(calendars []domain.Calendar) []domain.Calendar {
	if len(calendars) == 0 {
		return []domain.Calendar{}
	}
	cloned := make([]domain.Calendar, len(calendars))
	copy(cloned, calendars)
	return cloned
}

func mustHashPassword(password string) []byte {
	hash, err := bcrypt.GenerateFromPassword([]byte(password), bcrypt.DefaultCost)
	if err != nil {
		panic(err)
	}
	return hash
}

func newToken() string {
	buf := make([]byte, 24)
	if _, err := rand.Read(buf); err != nil {
		panic(err)
	}
	return "tok_" + hex.EncodeToString(buf)
}

func normalizeEmail(email string) string {
	return strings.ToLower(strings.TrimSpace(email))
}
