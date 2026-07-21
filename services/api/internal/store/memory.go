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
	RoleOwner            = "owner"
	RoleEditor           = "editor"
	RoleViewer           = "viewer"
	CalendarKindPersonal = "personal"
	CalendarKindShared   = "shared"
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

type InviteInput struct {
	Email           string
	DeliveryChannel string
	Role            string
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
	Invite domain.CalendarInvite
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
	budgetBoards    map[string]map[string]domain.BudgetBoard
	budgetTemplates map[string]domain.BudgetTemplates
	counter         int
	nextCalendarSeq int
	nextInviteSeq   int
	nextEventSeq    int
	nextBudgetSeq   int
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
		budgetBoards:    make(map[string]map[string]domain.BudgetBoard),
		budgetTemplates: make(map[string]domain.BudgetTemplates),
		counter:         4,
		nextCalendarSeq: 3,
		nextInviteSeq:   2,
		nextEventSeq:    3,
		nextBudgetSeq:   1,
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

	personalCalendar := domain.Calendar{ID: "cal_001", Kind: CalendarKindPersonal, Name: "Personal", Color: "#1F6B5C", UpdatedAt: now}
	sharedCalendar := domain.Calendar{ID: "cal_002", Kind: CalendarKindShared, Name: "Shared Home", Color: "#D8A21D", UpdatedAt: now}
	store.calendars[personalCalendar.ID] = calendarRecord{Calendar: personalCalendar, OwnerUserID: "usr_001"}
	store.calendars[sharedCalendar.ID] = calendarRecord{Calendar: sharedCalendar, OwnerUserID: "usr_001"}
	store.calendarMembers[personalCalendar.ID] = map[string]string{"usr_001": RoleOwner}
	store.calendarMembers[sharedCalendar.ID] = map[string]string{
		"usr_001": RoleOwner,
		"usr_002": RoleEditor,
		"usr_003": RoleViewer,
	}
	store.provisionPersonalCalendarLocked("usr_002", "#5B7FFF")
	store.provisionPersonalCalendarLocked("usr_003", "#A657D6")
	store.provisionPersonalCalendarLocked("usr_004", "#FF7A59")

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
		Invite: domain.CalendarInvite{
			ID:                   "cinv_001",
			CalendarID:           "cal_002",
			CalendarName:         "Shared Home",
			Email:                "user@example.com",
			DeliveryChannel:      "sms",
			Role:                 RoleViewer,
			InviteCode:           "invite_abc",
			InviteURL:            "https://dayflow.local/invites/invite_abc",
			InvitedByUserID:      "usr_001",
			InvitedByDisplayName: "DayFlow Owner",
			ExpiresAt:            nowFunc().Add(7 * 24 * time.Hour).Format(time.RFC3339),
			UpdatedAt:            now,
		},
	}

	return store
}

func (s *MemoryStore) mustSeedUser(user storedUser) {
	s.users[normalizeEmail(user.User.Email)] = user
	s.userIDs[user.User.ID] = normalizeEmail(user.User.Email)
}

func (s *MemoryStore) provisionPersonalCalendarLocked(userID, color string) domain.Calendar {
	calendarID := fmt.Sprintf("cal_%03d", s.nextCalendarSeq)
	s.nextCalendarSeq++
	calendar := domain.Calendar{
		ID:        calendarID,
		Kind:      CalendarKindPersonal,
		Name:      "Personal",
		Color:     color,
		UpdatedAt: s.now().Format(time.RFC3339),
	}
	s.calendars[calendarID] = calendarRecord{Calendar: calendar, OwnerUserID: userID}
	s.calendarMembers[calendarID] = map[string]string{userID: RoleOwner}
	return calendar
}

func (s *MemoryStore) Register(email, displayName, password, inviteCode string) (domain.User, string, error) {
	s.mu.Lock()
	defer s.mu.Unlock()

	normalizedEmail := normalizeEmail(email)
	inviteRecord, ok := s.invites[inviteCode]
	if !ok {
		return domain.User{}, "", ErrInvalidInvite
	}
	if normalizeEmail(inviteRecord.Invite.Email) != normalizedEmail {
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
	personalCalendar := s.provisionPersonalCalendarLocked(user.ID, "#5B7FFF")
	if _, err := s.acceptInviteLocked(user.ID, normalizedEmail, inviteCode); err != nil {
		delete(s.users, normalizedEmail)
		delete(s.userIDs, user.ID)
		delete(s.calendars, personalCalendar.ID)
		delete(s.calendarMembers, personalCalendar.ID)
		return domain.User{}, "", err
	}

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

	return s.listSharedCalendarsLocked(userID)
}

func (s *MemoryStore) CreateInvite(userID, calendarID string, input InviteInput) (domain.CalendarInvite, error) {
	if err := validateInviteInput(input); err != nil {
		return domain.CalendarInvite{}, err
	}

	s.mu.Lock()
	defer s.mu.Unlock()

	record, role, err := s.calendarForMutationLocked(userID, calendarID)
	if err != nil {
		return domain.CalendarInvite{}, err
	}
	if role != RoleOwner || record.OwnerUserID != userID {
		return domain.CalendarInvite{}, ErrForbidden
	}
	if record.Calendar.Kind != CalendarKindShared {
		return domain.CalendarInvite{}, fmt.Errorf("invites are allowed only for shared calendars: %w", ErrInvalidInput)
	}

	normalizedEmail := normalizeEmail(input.Email)
	if owner, ok := s.userByIDLocked(record.OwnerUserID); ok && normalizeEmail(owner.User.Email) == normalizedEmail {
		return domain.CalendarInvite{}, fmt.Errorf("calendar owner cannot be invited: %w", ErrInvalidInput)
	}
	for memberUserID := range s.calendarMembers[calendarID] {
		member, ok := s.userByIDLocked(memberUserID)
		if ok && normalizeEmail(member.User.Email) == normalizedEmail {
			return domain.CalendarInvite{}, fmt.Errorf("user is already a calendar member: %w", ErrInvalidInput)
		}
	}

	for code, existing := range s.invites {
		if existing.Invite.CalendarID != calendarID || normalizeEmail(existing.Invite.Email) != normalizedEmail {
			continue
		}
		if existing.Invite.AcceptedByUserID != "" {
			continue
		}
		existing.Invite.Role = input.Role
		existing.Invite.DeliveryChannel = input.DeliveryChannel
		existing.Invite.UpdatedAt = s.now().Format(time.RFC3339)
		s.invites[code] = existing
		return existing.Invite, nil
	}

	createdInvite := domain.CalendarInvite{
		ID:              fmt.Sprintf("cinv_%03d", s.nextInviteSeq),
		CalendarID:      calendarID,
		CalendarName:    record.Calendar.Name,
		Email:           normalizedEmail,
		DeliveryChannel: input.DeliveryChannel,
		Role:            input.Role,
		InvitedByUserID: userID,
		ExpiresAt:       s.now().Add(7 * 24 * time.Hour).Format(time.RFC3339),
		UpdatedAt:       s.now().Format(time.RFC3339),
	}
	createdInvite.InviteCode = s.nextInviteCodeLocked()
	createdInvite.InviteURL = fmt.Sprintf("https://dayflow.local/invites/%s", createdInvite.InviteCode)
	if inviter, ok := s.userByIDLocked(userID); ok {
		createdInvite.InvitedByDisplayName = inviter.User.DisplayName
	}
	s.nextInviteSeq++
	s.invites[createdInvite.InviteCode] = invite{Invite: createdInvite}
	return createdInvite, nil
}

func (s *MemoryStore) PreviewInvite(inviteCode string) (domain.CalendarInvite, error) {
	s.mu.Lock()
	defer s.mu.Unlock()

	inviteRecord, _, err := s.sharedCalendarInviteLocked(inviteCode)
	if err != nil {
		return domain.CalendarInvite{}, err
	}
	return inviteRecord.Invite, nil
}

func (s *MemoryStore) AcceptInvite(userID, inviteCode string) (domain.CalendarInvite, error) {
	s.mu.Lock()
	defer s.mu.Unlock()

	stored, ok := s.userByIDLocked(userID)
	if !ok {
		return domain.CalendarInvite{}, ErrForbidden
	}
	return s.acceptInviteLocked(userID, stored.User.Email, inviteCode)
}

func (s *MemoryStore) AcceptInviteCalendar(userID, inviteCode string) (domain.Calendar, error) {
	s.mu.Lock()
	defer s.mu.Unlock()

	stored, ok := s.userByIDLocked(userID)
	if !ok {
		return domain.Calendar{}, ErrForbidden
	}
	inviteRecord, err := s.acceptInviteLocked(userID, stored.User.Email, inviteCode)
	if err != nil {
		return domain.Calendar{}, err
	}

	record, ok := s.calendars[inviteRecord.CalendarID]
	if !ok {
		return domain.Calendar{}, ErrNotFound
	}
	calendar := record.Calendar
	calendar.MembershipRole = inviteRecord.Role
	return calendar, nil
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
		Kind:      CalendarKindShared,
		Name:      strings.TrimSpace(input.Name),
		Color:     strings.ToUpper(strings.TrimSpace(input.Color)),
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
	record.Calendar.MembershipRole = role
	record.Calendar.UpdatedAt = s.now().Format(time.RFC3339)
	s.calendars[calendarID] = record
	return record.Calendar, nil
}

func (s *MemoryStore) DeleteCalendar(userID, calendarID string) error {
	s.mu.Lock()
	defer s.mu.Unlock()

	record, role, err := s.calendarForMutationLocked(userID, calendarID)
	if err != nil {
		return err
	}
	if role != RoleOwner {
		return ErrForbidden
	}
	if record.Calendar.Kind == CalendarKindPersonal {
		return fmt.Errorf("personal calendars cannot be deleted: %w", ErrInvalidInput)
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
	board, err := s.LoadBudgetBoard(s.ownerID, monthKey)
	if err != nil {
		return domain.BudgetBoard{}
	}
	return board
}

func (s *MemoryStore) LoadBudgetBoard(userID, monthKey string) (domain.BudgetBoard, error) {
	s.mu.Lock()
	defer s.mu.Unlock()

	if _, ok := s.userByIDLocked(userID); !ok {
		return domain.BudgetBoard{}, ErrForbidden
	}
	if boards, ok := s.budgetBoards[userID]; ok {
		if board, ok := boards[monthKey]; ok {
			return cloneBudgetBoard(board), nil
		}
	}

	board := s.defaultBudgetBoardLocked(userID, monthKey)
	if _, ok := s.budgetBoards[userID]; !ok {
		s.budgetBoards[userID] = make(map[string]domain.BudgetBoard)
	}
	s.budgetBoards[userID][monthKey] = board
	return cloneBudgetBoard(board), nil
}

func (s *MemoryStore) SaveBudgetBoard(userID string, board domain.BudgetBoard) (domain.BudgetBoard, error) {
	s.mu.Lock()
	defer s.mu.Unlock()

	if _, ok := s.userByIDLocked(userID); !ok {
		return domain.BudgetBoard{}, ErrForbidden
	}
	if strings.TrimSpace(board.Month.MonthKey) == "" {
		return domain.BudgetBoard{}, fmt.Errorf("budget month key is required: %w", ErrInvalidInput)
	}

	now := s.now().Format(time.RFC3339)
	stored := cloneBudgetBoard(board)
	if stored.Month.ID == "" {
		stored.Month.ID = s.nextBudgetIDLocked("bmon")
	}
	stored.Month.UpdatedAt = now

	for index := range stored.FixedItems {
		if stored.FixedItems[index].ID == "" {
			stored.FixedItems[index].ID = s.nextBudgetIDLocked("bitm")
		}
		stored.FixedItems[index].UpdatedAt = now
	}
	for index := range stored.VariableBuckets {
		if stored.VariableBuckets[index].ID == "" {
			stored.VariableBuckets[index].ID = s.nextBudgetIDLocked("bbkt")
		}
		stored.VariableBuckets[index].UpdatedAt = now
	}
	for index := range stored.BillingReminders {
		if stored.BillingReminders[index].ID == "" {
			stored.BillingReminders[index].ID = s.nextBudgetIDLocked("brem")
		}
		if stored.BillingReminders[index].Kind == "" {
			stored.BillingReminders[index].Kind = "reminder"
		}
		stored.BillingReminders[index].UpdatedAt = now
	}

	stored.Summary, stored.Month.RemainingBudgetAmount = deriveBudgetSummary(stored.Month, stored.FixedItems, stored.VariableBuckets)
	if _, ok := s.budgetBoards[userID]; !ok {
		s.budgetBoards[userID] = make(map[string]domain.BudgetBoard)
	}
	s.budgetBoards[userID][stored.Month.MonthKey] = stored
	return cloneBudgetBoard(stored), nil
}

func (s *MemoryStore) LoadBudgetTemplates(userID string) (domain.BudgetTemplates, error) {
	s.mu.Lock()
	defer s.mu.Unlock()

	if _, ok := s.userByIDLocked(userID); !ok {
		return domain.BudgetTemplates{}, ErrForbidden
	}
	templates, ok := s.budgetTemplates[userID]
	if !ok {
		templates = s.defaultBudgetTemplatesLocked()
		s.budgetTemplates[userID] = templates
	}
	return cloneBudgetTemplates(templates), nil
}

func (s *MemoryStore) SaveBudgetTemplates(userID string, templates domain.BudgetTemplates) (domain.BudgetTemplates, error) {
	s.mu.Lock()
	defer s.mu.Unlock()

	if _, ok := s.userByIDLocked(userID); !ok {
		return domain.BudgetTemplates{}, ErrForbidden
	}

	now := s.now().Format(time.RFC3339)
	stored := cloneBudgetTemplates(templates)
	for index := range stored.FixedItems {
		item := &stored.FixedItems[index]
		if strings.TrimSpace(item.Name) == "" {
			return domain.BudgetTemplates{}, fmt.Errorf("template name is required: %w", ErrInvalidInput)
		}
		if item.Kind == "" {
			item.Kind = "fixed"
		}
		if item.Kind != "fixed" {
			return domain.BudgetTemplates{}, fmt.Errorf("template kind must be fixed: %w", ErrInvalidInput)
		}
		if item.ID == "" {
			item.ID = s.nextBudgetIDLocked("tmpl")
		}
		item.SortOrder = index
		item.UpdatedAt = now
	}

	s.budgetTemplates[userID] = stored
	return cloneBudgetTemplates(stored), nil
}

func (s *MemoryStore) defaultBudgetBoardLocked(userID, monthKey string) domain.BudgetBoard {
	now := s.now().Format(time.RFC3339)
	templates, ok := s.budgetTemplates[userID]
	if !ok {
		templates = s.defaultBudgetTemplatesLocked()
		s.budgetTemplates[userID] = templates
	}
	fixed := make([]domain.BudgetItem, 0, len(templates.FixedItems))
	for _, template := range templates.FixedItems {
		fixed = append(fixed, domain.BudgetItem{
			ID:              s.nextBudgetIDLocked("bitm"),
			Name:            template.Name,
			Kind:            template.Kind,
			Amount:          template.DefaultAmount,
			Enabled:         template.DefaultEnabled,
			Note:            template.DefaultNote,
			BillingDayLabel: template.DefaultBillingDay,
			UpdatedAt:       now,
		})
	}
	buckets := []domain.BudgetBucket{
		{ID: "bkt_001", Name: "점심 및 주말 식대", PlannedAmount: 12, ActualAmount: 0, FormulaHint: "평일 1 + 주말 3", UpdatedAt: now},
		{ID: "bkt_002", Name: "유동 금액", PlannedAmount: 0, ActualAmount: 0, UpdatedAt: now},
	}
	board := domain.BudgetBoard{
		Month: domain.BudgetMonth{
			ID:                "bmon_001",
			MonthKey:          monthKey,
			BaseBudgetAmount:  510,
			CurrentCashAmount: 118,
			SavingAmount:      200,
			CarryOverAmount:   0,
			UpdatedAt:         now,
		},
		FixedItems:      fixed,
		VariableBuckets: buckets,
		BillingReminders: []domain.BudgetItem{
			{ID: "rem_001", Name: "인터넷", Kind: "reminder", BillingDayLabel: "25일", UpdatedAt: now},
			{ID: "rem_002", Name: "전기 정산", Kind: "reminder", BillingDayLabel: "월말일", UpdatedAt: now},
		},
	}
	board.Summary, board.Month.RemainingBudgetAmount = deriveBudgetSummary(board.Month, board.FixedItems, board.VariableBuckets)
	return board
}

func (s *MemoryStore) defaultBudgetTemplatesLocked() domain.BudgetTemplates {
	now := s.now().Format(time.RFC3339)
	return domain.BudgetTemplates{
		FixedItems: []domain.BudgetTemplate{
			{ID: "tmpl_001", Name: "월세 및 관리비", Kind: "fixed", DefaultAmount: 21, DefaultEnabled: true, DefaultBillingDay: "20일", SortOrder: 0, UpdatedAt: now},
			{ID: "tmpl_002", Name: "대출이자", Kind: "fixed", DefaultAmount: 36, DefaultEnabled: true, DefaultBillingDay: "5일", SortOrder: 1, UpdatedAt: now},
			{ID: "tmpl_003", Name: "핸드폰요금", Kind: "fixed", DefaultAmount: 8, DefaultEnabled: true, DefaultBillingDay: "15일", SortOrder: 2, UpdatedAt: now},
			{ID: "tmpl_004", Name: "신용카드", Kind: "fixed", DefaultAmount: 88, DefaultEnabled: true, DefaultBillingDay: "26일", SortOrder: 3, UpdatedAt: now},
		},
	}
}

func (s *MemoryStore) meForUserIDLocked(userID string) (domain.Me, bool) {
	stored, ok := s.userByIDLocked(userID)
	if !ok {
		return domain.Me{}, false
	}
	personal, shared := s.splitCalendarsForUserLocked(userID)
	return domain.Me{
		User:                  stored.User,
		PersonalCalendar:      personal,
		SharedCalendars:       shared,
		CurrentBudgetMonthKey: stored.CurrentBudgetMonthKey,
	}, true
}

func (s *MemoryStore) acceptInviteLocked(userID, email, inviteCode string) (domain.CalendarInvite, error) {
	inviteRecord, _, err := s.sharedCalendarInviteLocked(inviteCode)
	if err != nil {
		return domain.CalendarInvite{}, err
	}
	if normalizeEmail(inviteRecord.Invite.Email) != normalizeEmail(email) {
		return domain.CalendarInvite{}, ErrInviteEmailMismatch
	}
	if inviteRecord.Invite.AcceptedByUserID != "" {
		if inviteRecord.Invite.AcceptedByUserID != userID {
			return domain.CalendarInvite{}, ErrInvalidInvite
		}
		return inviteRecord.Invite, nil
	}
	role := inviteRecord.Invite.Role
	if role == "" {
		role = RoleViewer
	}
	if _, ok := s.calendarMembers[inviteRecord.Invite.CalendarID]; !ok {
		s.calendarMembers[inviteRecord.Invite.CalendarID] = make(map[string]string)
	}
	if currentRole, ok := s.calendarMembers[inviteRecord.Invite.CalendarID][userID]; ok && currentRole == RoleOwner {
		return domain.CalendarInvite{}, fmt.Errorf("calendar owner cannot accept invite: %w", ErrInvalidInput)
	}
	s.calendarMembers[inviteRecord.Invite.CalendarID][userID] = role
	now := s.now().Format(time.RFC3339)
	inviteRecord.Invite.Role = role
	inviteRecord.Invite.AcceptedByUserID = userID
	inviteRecord.Invite.AcceptedAt = now
	inviteRecord.Invite.UpdatedAt = now
	s.invites[inviteCode] = inviteRecord
	return inviteRecord.Invite, nil
}

func (s *MemoryStore) sharedCalendarInviteLocked(inviteCode string) (invite, calendarRecord, error) {
	inviteRecord, ok := s.invites[inviteCode]
	if !ok {
		return invite{}, calendarRecord{}, ErrInvalidInvite
	}
	record, ok := s.calendars[inviteRecord.Invite.CalendarID]
	if !ok || record.Calendar.Kind != CalendarKindShared {
		return invite{}, calendarRecord{}, ErrInvalidInvite
	}
	inviteRecord.Invite.CalendarName = record.Calendar.Name
	s.invites[inviteCode] = inviteRecord
	return inviteRecord, record, nil
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
		calendar.MembershipRole = role
		items = append(items, calendar)
	}
	sort.Slice(items, func(i, j int) bool {
		return items[i].ID < items[j].ID
	})
	return items
}

func (s *MemoryStore) listSharedCalendarsLocked(userID string) []domain.Calendar {
	shared := make([]domain.Calendar, 0)
	for _, calendar := range s.listCalendarsLocked(userID) {
		if calendar.Kind == CalendarKindPersonal {
			continue
		}
		shared = append(shared, calendar)
	}
	return shared
}

func (s *MemoryStore) splitCalendarsForUserLocked(userID string) (domain.Calendar, []domain.Calendar) {
	var personal domain.Calendar
	shared := make([]domain.Calendar, 0)
	for _, calendar := range s.listCalendarsLocked(userID) {
		if calendar.Kind == CalendarKindPersonal {
			calendar.MembershipRole = ""
			personal = calendar
			continue
		}
		calendar.MembershipRole = ""
		shared = append(shared, calendar)
	}
	return personal, shared
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

func validateInviteInput(input InviteInput) error {
	if normalizeEmail(input.Email) == "" {
		return fmt.Errorf("invite email is required: %w", ErrInvalidInput)
	}
	if input.DeliveryChannel != "email" && input.DeliveryChannel != "sms" {
		return fmt.Errorf("delivery_channel must be email or sms: %w", ErrInvalidInput)
	}
	if input.Role != RoleEditor && input.Role != RoleViewer {
		return fmt.Errorf("invite role must be editor or viewer: %w", ErrInvalidInput)
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

func (s *MemoryStore) nextInviteCodeLocked() string {
	return fmt.Sprintf("invite_%03d", s.nextInviteSeq)
}

func cloneBudgetBoard(board domain.BudgetBoard) domain.BudgetBoard {
	cloned := board
	cloned.FixedItems = append([]domain.BudgetItem(nil), board.FixedItems...)
	if cloned.FixedItems == nil {
		cloned.FixedItems = []domain.BudgetItem{}
	}
	cloned.VariableBuckets = append([]domain.BudgetBucket(nil), board.VariableBuckets...)
	if cloned.VariableBuckets == nil {
		cloned.VariableBuckets = []domain.BudgetBucket{}
	}
	cloned.BillingReminders = append([]domain.BudgetItem(nil), board.BillingReminders...)
	if cloned.BillingReminders == nil {
		cloned.BillingReminders = []domain.BudgetItem{}
	}
	return cloned
}

func cloneBudgetTemplates(templates domain.BudgetTemplates) domain.BudgetTemplates {
	cloned := templates
	cloned.FixedItems = append([]domain.BudgetTemplate(nil), templates.FixedItems...)
	if cloned.FixedItems == nil {
		cloned.FixedItems = []domain.BudgetTemplate{}
	}
	return cloned
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

func (s *MemoryStore) nextBudgetIDLocked(prefix string) string {
	id := fmt.Sprintf("%s_%03d", prefix, s.nextBudgetSeq)
	s.nextBudgetSeq++
	return id
}
