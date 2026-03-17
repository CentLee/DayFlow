package store

import (
	"crypto/rand"
	"encoding/hex"
	"errors"
	"fmt"
	"regexp"
	"sort"
	"strings"
	"sync"
	"time"

	"golang.org/x/crypto/bcrypt"

	"github.com/kakao-ent/dayflow/services/api/internal/domain"
)

const (
	RoleOwner  = "owner"
	RoleEditor = "editor"
	RoleViewer = "viewer"
)

var (
	ErrEmailTaken          = errors.New("email already registered")
	ErrInvalidCredentials  = errors.New("invalid credentials")
	ErrInvalidInvite       = errors.New("invalid invite")
	ErrInviteEmailMismatch = errors.New("invite email mismatch")
	ErrForbidden           = errors.New("forbidden")
	ErrNotFound            = errors.New("not_found")
	ErrInvalidInput        = errors.New("invalid_input")

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

type storedUser struct {
	User                  domain.User
	PasswordHash          []byte
	CurrentBudgetMonthKey string
}

type invite struct {
	Code              string
	Email             string
	SharedCalendarIDs []string
	Role              string
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
	mu              sync.Mutex
	users           map[string]storedUser
	userIDs         map[string]string
	sessions        map[string]string
	invites         map[string]invite
	calendars       map[string]calendarRecord
	calendarMembers map[string]map[string]string
	events          map[string]eventRecord
	counter         int
	nextCalendarSeq int
	nextEventSeq    int
	monthKey        string
	ownerID         string
	now             func() time.Time
}

func NewMemoryStore() *MemoryStore {
	nowFunc := time.Now().UTC
	now := nowFunc().Format(time.RFC3339)
	monthKey := nowFunc().Format("2006-01")

	store := &MemoryStore{
		users:           make(map[string]storedUser),
		userIDs:         make(map[string]string),
		sessions:        make(map[string]string),
		invites:         make(map[string]invite),
		calendars:       make(map[string]calendarRecord),
		calendarMembers: make(map[string]map[string]string),
		events:          make(map[string]eventRecord),
		counter:         4,
		nextCalendarSeq: 3,
		nextEventSeq:    3,
		monthKey:        monthKey,
		ownerID:         "usr_001",
		now:             nowFunc,
	}

	store.mustSeedUser(storedUser{
		User: domain.User{
			ID:          "usr_001",
			Email:       "owner@dayflow.local",
			DisplayName: "DayFlow Owner",
		},
		PasswordHash:          mustHashPassword("secret1234"),
		CurrentBudgetMonthKey: monthKey,
	})
	store.mustSeedUser(storedUser{
		User: domain.User{
			ID:          "usr_002",
			Email:       "editor@dayflow.local",
			DisplayName: "Calendar Editor",
		},
		PasswordHash:          mustHashPassword("secret1234"),
		CurrentBudgetMonthKey: monthKey,
	})
	store.mustSeedUser(storedUser{
		User: domain.User{
			ID:          "usr_003",
			Email:       "viewer@dayflow.local",
			DisplayName: "Calendar Viewer",
		},
		PasswordHash:          mustHashPassword("secret1234"),
		CurrentBudgetMonthKey: monthKey,
	})
	store.mustSeedUser(storedUser{
		User: domain.User{
			ID:          "usr_004",
			Email:       "outside@dayflow.local",
			DisplayName: "Outside User",
		},
		PasswordHash:          mustHashPassword("secret1234"),
		CurrentBudgetMonthKey: monthKey,
	})

	personalCalendar := domain.Calendar{ID: "cal_001", Name: "Personal", Color: "#1F6B5C", UpdatedAt: now}
	sharedCalendar := domain.Calendar{ID: "cal_002", Name: "Shared Home", Color: "#D8A21D", UpdatedAt: now}
	store.calendars[personalCalendar.ID] = calendarRecord{Calendar: personalCalendar, OwnerUserID: "usr_001"}
	store.calendars[sharedCalendar.ID] = calendarRecord{Calendar: sharedCalendar, OwnerUserID: "usr_001"}
	store.calendarMembers[personalCalendar.ID] = map[string]string{"usr_001": RoleOwner}
	store.calendarMembers[sharedCalendar.ID] = map[string]string{
		"usr_001": RoleOwner,
		"usr_002": RoleEditor,
		"usr_003": RoleViewer,
	}

	store.events["evt_001"] = eventRecord{
		Event: domain.Event{
			ID:         "evt_001",
			CalendarID: "cal_001",
			Title:      "월간 예산 점검",
			Notes:      "budget is private and stays personal",
			StartsAt:   now,
			EndsAt:     nowFunc().Add(30 * time.Minute).Format(time.RFC3339),
			AllDay:     false,
			UpdatedAt:  now,
		},
		CreatedByUserID: "usr_001",
	}
	store.events["evt_002"] = eventRecord{
		Event: domain.Event{
			ID:         "evt_002",
			CalendarID: "cal_002",
			Title:      "보험비 정산",
			Notes:      "25일 기준 확인",
			StartsAt:   nowFunc().Add(24 * time.Hour).Format(time.RFC3339),
			EndsAt:     nowFunc().Add(25 * time.Hour).Format(time.RFC3339),
			AllDay:     false,
			UpdatedAt:  now,
		},
		CreatedByUserID: "usr_001",
	}

	store.invites["invite_abc"] = invite{
		Code:              "invite_abc",
		Email:             "user@example.com",
		SharedCalendarIDs: []string{"cal_002"},
		Role:              RoleViewer,
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
		DisplayName: strings.TrimSpace(displayName),
	}
	stored := storedUser{
		User:                  user,
		PasswordHash:          mustHashPassword(password),
		CurrentBudgetMonthKey: s.monthKey,
	}
	s.users[normalizedEmail] = stored
	s.userIDs[user.ID] = normalizedEmail
	for _, calendarID := range inviteRecord.SharedCalendarIDs {
		if members, ok := s.calendarMembers[calendarID]; ok {
			role := inviteRecord.Role
			if role == "" {
				role = RoleViewer
			}
			members[user.ID] = role
		}
	}
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
	return s.meForUserIDLocked(userID)
}

func (s *MemoryStore) Me(userID string) (domain.User, bool) {
	s.mu.Lock()
	defer s.mu.Unlock()

	stored, ok := s.userByIDLocked(userID)
	if !ok {
		return domain.User{}, false
	}
	return stored.User, true
}

func (s *MemoryStore) Calendars() []domain.Calendar {
	items, _ := s.ListCalendars(s.ownerID), true
	return items
}

func (s *MemoryStore) Events(calendarID string) []domain.Event {
	items, err := s.ListEvents(s.ownerID, calendarID, nil, nil)
	if err != nil {
		return []domain.Event{}
	}
	return items
}

func (s *MemoryStore) ListCalendars(userID string) []domain.Calendar {
	s.mu.Lock()
	defer s.mu.Unlock()

	return s.listCalendarsLocked(userID)
}

func (s *MemoryStore) CreateCalendar(userID string, input CalendarInput) (domain.Calendar, error) {
	if err := validateCalendarInput(input); err != nil {
		return domain.Calendar{}, err
	}

	s.mu.Lock()
	defer s.mu.Unlock()

	if _, ok := s.userByIDLocked(userID); !ok {
		return domain.Calendar{}, ErrForbidden
	}

	id := fmt.Sprintf("cal_%03d", s.nextCalendarSeq)
	s.nextCalendarSeq++
	calendar := domain.Calendar{
		ID:        id,
		Name:      strings.TrimSpace(input.Name),
		Color:     strings.ToUpper(strings.TrimSpace(input.Color)),
		Role:      RoleOwner,
		UpdatedAt: s.now().Format(time.RFC3339),
	}
	s.calendars[id] = calendarRecord{Calendar: calendar, OwnerUserID: userID}
	s.calendarMembers[id] = map[string]string{userID: RoleOwner}
	return calendar, nil
}

func (s *MemoryStore) UpdateCalendar(userID, calendarID string, patch CalendarPatch) (domain.Calendar, error) {
	s.mu.Lock()
	defer s.mu.Unlock()

	record, role, err := s.calendarForMutationLocked(userID, calendarID)
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
	record.Calendar.Role = role
	record.Calendar.UpdatedAt = s.now().Format(time.RFC3339)
	s.calendars[calendarID] = record
	return record.Calendar, nil
}

func (s *MemoryStore) DeleteCalendar(userID, calendarID string) error {
	s.mu.Lock()
	defer s.mu.Unlock()

	_, role, err := s.calendarForMutationLocked(userID, calendarID)
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
	s.mu.Lock()
	defer s.mu.Unlock()

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
		end, err := time.Parse(time.RFC3339, record.Event.EndsAt)
		if err != nil {
			continue
		}
		if from != nil && end.Before(*from) {
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

	_, role, err := s.calendarForMutationLocked(userID, calendarID)
	if err != nil {
		return domain.Event{}, err
	}
	if !canEditEvents(role) {
		return domain.Event{}, ErrForbidden
	}

	id := fmt.Sprintf("evt_%03d", s.nextEventSeq)
	s.nextEventSeq++
	event := domain.Event{
		ID:         id,
		CalendarID: calendarID,
		Title:      strings.TrimSpace(input.Title),
		Notes:      strings.TrimSpace(input.Notes),
		StartsAt:   input.StartsAt.UTC().Format(time.RFC3339),
		EndsAt:     input.EndsAt.UTC().Format(time.RFC3339),
		AllDay:     input.AllDay,
		UpdatedAt:  s.now().Format(time.RFC3339),
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
	_, role, err := s.calendarForMutationLocked(userID, record.Event.CalendarID)
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
	_, role, err := s.calendarForMutationLocked(userID, record.Event.CalendarID)
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

func (s *MemoryStore) meForUserIDLocked(userID string) (domain.Me, bool) {
	stored, ok := s.userByIDLocked(userID)
	if !ok {
		return domain.Me{}, false
	}
	owned, shared := s.splitCalendarsForUserLocked(userID)
	return domain.Me{
		User:                  stored.User,
		OwnedCalendars:        owned,
		SharedCalendars:       shared,
		CurrentBudgetMonthKey: stored.CurrentBudgetMonthKey,
	}, true
}

func (s *MemoryStore) userByIDLocked(userID string) (storedUser, bool) {
	normalizedEmail, ok := s.userIDs[userID]
	if !ok {
		return storedUser{}, false
	}
	stored, ok := s.users[normalizedEmail]
	return stored, ok
}

func (s *MemoryStore) listCalendarsLocked(userID string) []domain.Calendar {
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

func (s *MemoryStore) splitCalendarsForUserLocked(userID string) ([]domain.Calendar, []domain.Calendar) {
	owned := make([]domain.Calendar, 0)
	shared := make([]domain.Calendar, 0)
	for _, calendar := range s.listCalendarsLocked(userID) {
		record := s.calendars[calendar.ID]
		if record.OwnerUserID == userID {
			owned = append(owned, calendar)
			continue
		}
		shared = append(shared, calendar)
	}
	return owned, shared
}

func (s *MemoryStore) calendarForAccessLocked(userID, calendarID string) (calendarRecord, string, error) {
	if _, ok := s.userByIDLocked(userID); !ok {
		return calendarRecord{}, "", ErrForbidden
	}
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

func (s *MemoryStore) calendarForMutationLocked(userID, calendarID string) (calendarRecord, string, error) {
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
