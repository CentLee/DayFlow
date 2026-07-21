package store

import (
	"context"
	"errors"
	"fmt"
	"time"

	"github.com/kakao-ent/dayflow/services/api/internal/domain"
)

type HybridStore struct {
	memory *MemoryStore
	budget *PostgresBudgetStore
}

func NewHybridStore(memory *MemoryStore, budget *PostgresBudgetStore) *HybridStore {
	return &HybridStore{
		memory: memory,
		budget: budget,
	}
}

func (s *HybridStore) Register(email, displayName, password, inviteCode string) (domain.User, string, error) {
	return s.memory.Register(email, displayName, password, inviteCode)
}

func (s *HybridStore) Login(email, password string) (domain.User, string, error) {
	return s.memory.Login(email, password)
}

func (s *HybridStore) AuthenticatedMe(token string) (domain.Me, bool) {
	return s.memory.AuthenticatedMe(token)
}

func (s *HybridStore) Me(userID string) (domain.User, bool) {
	return s.memory.Me(userID)
}

func (s *HybridStore) ListCalendars(userID string) []domain.Calendar {
	return s.memory.ListCalendars(userID)
}

func (s *HybridStore) CreateInvite(userID, calendarID string, input InviteInput) (domain.CalendarInvite, error) {
	return s.memory.CreateInvite(userID, calendarID, input)
}

func (s *HybridStore) PreviewInvite(inviteCode string) (domain.CalendarInvite, error) {
	return s.memory.PreviewInvite(inviteCode)
}

func (s *HybridStore) AcceptInvite(userID, inviteCode string) (domain.CalendarInvite, error) {
	return s.memory.AcceptInvite(userID, inviteCode)
}

func (s *HybridStore) AcceptInviteCalendar(userID, inviteCode string) (domain.Calendar, error) {
	return s.memory.AcceptInviteCalendar(userID, inviteCode)
}

func (s *HybridStore) CreateCalendar(userID string, input CalendarInput) (domain.Calendar, error) {
	return s.memory.CreateCalendar(userID, input)
}

func (s *HybridStore) UpdateCalendar(userID, calendarID string, patch CalendarPatch) (domain.Calendar, error) {
	return s.memory.UpdateCalendar(userID, calendarID, patch)
}

func (s *HybridStore) DeleteCalendar(userID, calendarID string) error {
	return s.memory.DeleteCalendar(userID, calendarID)
}

func (s *HybridStore) ListEvents(userID, calendarID string, from, to *time.Time) ([]domain.Event, error) {
	return s.memory.ListEvents(userID, calendarID, from, to)
}

func (s *HybridStore) CreateEvent(userID, calendarID string, input EventInput) (domain.Event, error) {
	return s.memory.CreateEvent(userID, calendarID, input)
}

func (s *HybridStore) UpdateEvent(userID, eventID string, patch EventPatch) (domain.Event, error) {
	return s.memory.UpdateEvent(userID, eventID, patch)
}

func (s *HybridStore) DeleteEvent(userID, eventID string) error {
	return s.memory.DeleteEvent(userID, eventID)
}

func (s *HybridStore) LoadBudgetBoard(userID, monthKey string) (domain.BudgetBoard, error) {
	if err := s.ensureBudgetUser(userID); err != nil {
		return domain.BudgetBoard{}, err
	}

	board, err := s.budget.LoadBudgetBoard(context.Background(), userID, monthKey)
	if err == nil {
		return board, nil
	}
	if !errors.Is(err, ErrNotFound) {
		return domain.BudgetBoard{}, err
	}

	defaultBoard, fallbackErr := s.memory.LoadBudgetBoard(userID, monthKey)
	if fallbackErr != nil {
		return domain.BudgetBoard{}, fallbackErr
	}
	return s.budget.SaveBudgetBoard(context.Background(), userID, defaultBoard)
}

func (s *HybridStore) SaveBudgetBoard(userID string, board domain.BudgetBoard) (domain.BudgetBoard, error) {
	if err := s.ensureBudgetUser(userID); err != nil {
		return domain.BudgetBoard{}, err
	}
	return s.budget.SaveBudgetBoard(context.Background(), userID, board)
}

func (s *HybridStore) LoadBudgetTemplates(userID string) (domain.BudgetTemplates, error) {
	if err := s.ensureBudgetUser(userID); err != nil {
		return domain.BudgetTemplates{}, err
	}

	templates, err := s.budget.LoadBudgetTemplates(context.Background(), userID)
	if err != nil {
		return domain.BudgetTemplates{}, err
	}
	if len(templates.FixedItems) > 0 {
		return templates, nil
	}

	defaultTemplates, fallbackErr := s.memory.LoadBudgetTemplates(userID)
	if fallbackErr != nil {
		return domain.BudgetTemplates{}, fallbackErr
	}
	return s.budget.SaveBudgetTemplates(context.Background(), userID, defaultTemplates)
}

func (s *HybridStore) SaveBudgetTemplates(userID string, templates domain.BudgetTemplates) (domain.BudgetTemplates, error) {
	if err := s.ensureBudgetUser(userID); err != nil {
		return domain.BudgetTemplates{}, err
	}
	return s.budget.SaveBudgetTemplates(context.Background(), userID, templates)
}

func (s *HybridStore) EnsureBudgetUsers(ctx context.Context) error {
	for _, user := range s.memory.SeedUsers() {
		if err := s.budget.EnsureUser(ctx, user); err != nil {
			return err
		}
	}
	return nil
}

func (s *HybridStore) ensureBudgetUser(userID string) error {
	user, ok := s.memory.Me(userID)
	if !ok {
		return ErrForbidden
	}
	if err := s.budget.EnsureUser(context.Background(), user); err != nil {
		return fmt.Errorf("ensure budget user: %w", err)
	}
	return nil
}
