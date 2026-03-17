package store

import (
	"errors"
	"fmt"
	"regexp"
	"sort"
	"strings"
	"sync"
	"time"

	"github.com/kakao-ent/dayflow/services/api/internal/domain"
)

const (
	RoleOwner  = "owner"
	RoleEditor = "editor"
	RoleViewer = "viewer"
)

var (
	ErrForbidden    = errors.New("forbidden")
	ErrNotFound     = errors.New("not_found")
	ErrInvalidInput = errors.New("invalid_input")

	calendarColorPattern = regexp.MustCompile(`^#[0-9A-Fa-f]{6}$`)
)

type CalendarInput struct {
	Name  string
	Color string
}

type CalendarPatch struct {
	Name  *string
	Color *string
}

type EventInput struct {
	Title    string
	Notes    string
	StartsAt time.Time
	EndsAt   time.Time
	AllDay   bool
}

type EventPatch struct {
	Title    *string
	Notes    *string
	StartsAt *time.Time
	EndsAt   *time.Time
	AllDay   *bool
}

type calendarRecord struct {
	Calendar    domain.Calendar
	OwnerUserID string
}

type eventRecord struct {
	Event           domain.Event
	CreatedByUserID string
}

type MemoryStore struct {
	mu              sync.RWMutex
	users           map[string]domain.User
	calendars       map[string]calendarRecord
	calendarMembers map[string]map[string]string
	events          map[string]eventRecord
	nextCalendarSeq int
	nextEventSeq    int
	now             func() time.Time
}

func NewMemoryStore() *MemoryStore {
	now := time.Now().UTC
	store := &MemoryStore{
		users: map[string]domain.User{
			"usr_001": {ID: "usr_001", Email: "owner@dayflow.local", DisplayName: "DayFlow Owner"},
			"usr_002": {ID: "usr_002", Email: "editor@dayflow.local", DisplayName: "Calendar Editor"},
			"usr_003": {ID: "usr_003", Email: "viewer@dayflow.local", DisplayName: "Calendar Viewer"},
			"usr_004": {ID: "usr_004", Email: "outside@dayflow.local", DisplayName: "Outside User"},
		},
		calendars:       map[string]calendarRecord{},
		calendarMembers: map[string]map[string]string{},
		events:          map[string]eventRecord{},
		nextCalendarSeq: 3,
		nextEventSeq:    3,
		now:             now,
	}

	personal := domain.Calendar{ID: "cal_001", Name: "Personal", Color: "#1F6B5C", UpdatedAt: now().Format(time.RFC3339)}
	shared := domain.Calendar{ID: "cal_002", Name: "Shared Home", Color: "#D8A21D", UpdatedAt: now().Format(time.RFC3339)}
	store.calendars[personal.ID] = calendarRecord{Calendar: personal, OwnerUserID: "usr_001"}
	store.calendars[shared.ID] = calendarRecord{Calendar: shared, OwnerUserID: "usr_001"}
	store.calendarMembers[personal.ID] = map[string]string{"usr_001": RoleOwner}
	store.calendarMembers[shared.ID] = map[string]string{"usr_001": RoleOwner, "usr_002": RoleEditor, "usr_003": RoleViewer}

	store.events["evt_001"] = eventRecord{
		Event: domain.Event{
			ID:         "evt_001",
			CalendarID: "cal_001",
			Title:      "월간 예산 점검",
			Notes:      "budget is private and stays personal",
			StartsAt:   now().Format(time.RFC3339),
			EndsAt:     now().Add(30 * time.Minute).Format(time.RFC3339),
			AllDay:     false,
			UpdatedAt:  now().Format(time.RFC3339),
		},
		CreatedByUserID: "usr_001",
	}
	store.events["evt_002"] = eventRecord{
		Event: domain.Event{
			ID:         "evt_002",
			CalendarID: "cal_002",
			Title:      "보험비 정산",
			Notes:      "25일 기준 확인",
			StartsAt:   now().Add(24 * time.Hour).Format(time.RFC3339),
			EndsAt:     now().Add(25 * time.Hour).Format(time.RFC3339),
			AllDay:     false,
			UpdatedAt:  now().Format(time.RFC3339),
		},
		CreatedByUserID: "usr_001",
	}

	return store
}

func (s *MemoryStore) Me(userID string) (domain.User, bool) {
	s.mu.RLock()
	defer s.mu.RUnlock()

	if userID == "" {
		userID = "usr_001"
	}
	user, ok := s.users[userID]
	return user, ok
}

func (s *MemoryStore) ListCalendars(userID string) []domain.Calendar {
	s.mu.RLock()
	defer s.mu.RUnlock()

	items := make([]domain.Calendar, 0)
	for calendarID, roles := range s.calendarMembers {
		role, ok := roles[userID]
		if !ok {
			continue
		}
		calendar := s.calendars[calendarID].Calendar
		calendar.Role = role
		items = append(items, calendar)
	}
	sort.Slice(items, func(i, j int) bool {
		return items[i].ID < items[j].ID
	})
	return items
}

func (s *MemoryStore) CreateCalendar(userID string, input CalendarInput) (domain.Calendar, error) {
	if err := validateCalendarInput(input); err != nil {
		return domain.Calendar{}, err
	}

	s.mu.Lock()
	defer s.mu.Unlock()

	if _, ok := s.users[userID]; !ok {
		return domain.Calendar{}, ErrForbidden
	}

	id := fmt.Sprintf("cal_%03d", s.nextCalendarSeq)
	s.nextCalendarSeq++
	now := s.now().Format(time.RFC3339)
	calendar := domain.Calendar{
		ID:        id,
		Name:      strings.TrimSpace(input.Name),
		Color:     strings.ToUpper(input.Color),
		Role:      RoleOwner,
		UpdatedAt: now,
	}
	s.calendars[id] = calendarRecord{Calendar: calendar, OwnerUserID: userID}
	s.calendarMembers[id] = map[string]string{userID: RoleOwner}
	return calendar, nil
}

func (s *MemoryStore) UpdateCalendar(userID, calendarID string, patch CalendarPatch) (domain.Calendar, error) {
	s.mu.Lock()
	defer s.mu.Unlock()

	record, role, err := s.calendarForMutationLocked(userID, calendarID, true)
	if err != nil {
		return domain.Calendar{}, err
	}
	if role != RoleOwner {
		return domain.Calendar{}, ErrForbidden
	}

	if patch.Name != nil {
		name := strings.TrimSpace(*patch.Name)
		if name == "" {
			return domain.Calendar{}, fmt.Errorf("calendar name is required: %w", ErrInvalidInput)
		}
		record.Calendar.Name = name
	}
	if patch.Color != nil {
		color := strings.ToUpper(strings.TrimSpace(*patch.Color))
		if !calendarColorPattern.MatchString(color) {
			return domain.Calendar{}, fmt.Errorf("calendar color must be #RRGGBB: %w", ErrInvalidInput)
		}
		record.Calendar.Color = color
	}
	record.Calendar.UpdatedAt = s.now().Format(time.RFC3339)
	record.Calendar.Role = role
	s.calendars[calendarID] = record
	return record.Calendar, nil
}

func (s *MemoryStore) DeleteCalendar(userID, calendarID string) error {
	s.mu.Lock()
	defer s.mu.Unlock()

	_, role, err := s.calendarForMutationLocked(userID, calendarID, true)
	if err != nil {
		return err
	}
	if role != RoleOwner {
		return ErrForbidden
	}

	delete(s.calendars, calendarID)
	delete(s.calendarMembers, calendarID)
	for eventID, record := range s.events {
		if record.Event.CalendarID == calendarID {
			delete(s.events, eventID)
		}
	}
	return nil
}

func (s *MemoryStore) ListEvents(userID, calendarID string, from, to *time.Time) ([]domain.Event, error) {
	s.mu.RLock()
	defer s.mu.RUnlock()

	if _, _, err := s.calendarForAccessLocked(userID, calendarID); err != nil {
		return nil, err
	}

	items := make([]domain.Event, 0)
	for _, record := range s.events {
		if record.Event.CalendarID != calendarID {
			continue
		}
		start, err := time.Parse(time.RFC3339, record.Event.StartsAt)
		if err != nil {
			continue
		}
		if from != nil && start.Before(*from) {
			continue
		}
		if to != nil && start.After(*to) {
			continue
		}
		items = append(items, record.Event)
	}
	sort.Slice(items, func(i, j int) bool {
		if items[i].StartsAt == items[j].StartsAt {
			return items[i].ID < items[j].ID
		}
		return items[i].StartsAt < items[j].StartsAt
	})
	return items, nil
}

func (s *MemoryStore) CreateEvent(userID, calendarID string, input EventInput) (domain.Event, error) {
	if err := validateEventInput(input); err != nil {
		return domain.Event{}, err
	}

	s.mu.Lock()
	defer s.mu.Unlock()

	_, role, err := s.calendarForMutationLocked(userID, calendarID, true)
	if err != nil {
		return domain.Event{}, err
	}
	if !canEditEvents(role) {
		return domain.Event{}, ErrForbidden
	}

	id := fmt.Sprintf("evt_%03d", s.nextEventSeq)
	s.nextEventSeq++
	now := s.now().Format(time.RFC3339)
	event := domain.Event{
		ID:         id,
		CalendarID: calendarID,
		Title:      strings.TrimSpace(input.Title),
		Notes:      strings.TrimSpace(input.Notes),
		StartsAt:   input.StartsAt.UTC().Format(time.RFC3339),
		EndsAt:     input.EndsAt.UTC().Format(time.RFC3339),
		AllDay:     input.AllDay,
		UpdatedAt:  now,
	}
	s.events[id] = eventRecord{Event: event, CreatedByUserID: userID}
	return event, nil
}

func (s *MemoryStore) UpdateEvent(userID, eventID string, patch EventPatch) (domain.Event, error) {
	s.mu.Lock()
	defer s.mu.Unlock()

	record, ok := s.events[eventID]
	if !ok {
		return domain.Event{}, ErrNotFound
	}
	_, role, err := s.calendarForMutationLocked(userID, record.Event.CalendarID, true)
	if err != nil {
		return domain.Event{}, err
	}
	if !canEditEvents(role) {
		return domain.Event{}, ErrForbidden
	}

	if patch.Title != nil {
		title := strings.TrimSpace(*patch.Title)
		if title == "" {
			return domain.Event{}, fmt.Errorf("event title is required: %w", ErrInvalidInput)
		}
		record.Event.Title = title
	}
	if patch.Notes != nil {
		record.Event.Notes = strings.TrimSpace(*patch.Notes)
	}
	if patch.StartsAt != nil {
		record.Event.StartsAt = patch.StartsAt.UTC().Format(time.RFC3339)
	}
	if patch.EndsAt != nil {
		record.Event.EndsAt = patch.EndsAt.UTC().Format(time.RFC3339)
	}
	if patch.AllDay != nil {
		record.Event.AllDay = *patch.AllDay
	}
	if err := validateEventRecord(record.Event); err != nil {
		return domain.Event{}, err
	}
	record.Event.UpdatedAt = s.now().Format(time.RFC3339)
	s.events[eventID] = record
	return record.Event, nil
}

func (s *MemoryStore) DeleteEvent(userID, eventID string) error {
	s.mu.Lock()
	defer s.mu.Unlock()

	record, ok := s.events[eventID]
	if !ok {
		return ErrNotFound
	}
	_, role, err := s.calendarForMutationLocked(userID, record.Event.CalendarID, true)
	if err != nil {
		return err
	}
	if !canEditEvents(role) {
		return ErrForbidden
	}
	delete(s.events, eventID)
	return nil
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

func (s *MemoryStore) calendarForAccessLocked(userID, calendarID string) (calendarRecord, string, error) {
	record, ok := s.calendars[calendarID]
	if !ok {
		return calendarRecord{}, "", ErrNotFound
	}
	role, ok := s.calendarMembers[calendarID][userID]
	if !ok {
		return calendarRecord{}, "", ErrForbidden
	}
	return record, role, nil
}

func (s *MemoryStore) calendarForMutationLocked(userID, calendarID string, requireUser bool) (calendarRecord, string, error) {
	if requireUser {
		if _, ok := s.users[userID]; !ok {
			return calendarRecord{}, "", ErrForbidden
		}
	}
	return s.calendarForAccessLocked(userID, calendarID)
}

func validateCalendarInput(input CalendarInput) error {
	if strings.TrimSpace(input.Name) == "" {
		return fmt.Errorf("calendar name is required: %w", ErrInvalidInput)
	}
	color := strings.ToUpper(strings.TrimSpace(input.Color))
	if !calendarColorPattern.MatchString(color) {
		return fmt.Errorf("calendar color must be #RRGGBB: %w", ErrInvalidInput)
	}
	return nil
}

func validateEventInput(input EventInput) error {
	if strings.TrimSpace(input.Title) == "" {
		return fmt.Errorf("event title is required: %w", ErrInvalidInput)
	}
	if input.EndsAt.Before(input.StartsAt) {
		return fmt.Errorf("event end must be on or after start: %w", ErrInvalidInput)
	}
	return nil
}

func validateEventRecord(event domain.Event) error {
	if strings.TrimSpace(event.Title) == "" {
		return fmt.Errorf("event title is required: %w", ErrInvalidInput)
	}
	startsAt, err := time.Parse(time.RFC3339, event.StartsAt)
	if err != nil {
		return fmt.Errorf("event start must be RFC3339: %w", ErrInvalidInput)
	}
	endsAt, err := time.Parse(time.RFC3339, event.EndsAt)
	if err != nil {
		return fmt.Errorf("event end must be RFC3339: %w", ErrInvalidInput)
	}
	if endsAt.Before(startsAt) {
		return fmt.Errorf("event end must be on or after start: %w", ErrInvalidInput)
	}
	return nil
}

func canEditEvents(role string) bool {
	return role == RoleOwner || role == RoleEditor
}
