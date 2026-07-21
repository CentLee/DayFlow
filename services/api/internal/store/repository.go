package store

import (
	"time"

	"github.com/kakao-ent/dayflow/services/api/internal/domain"
)

type Repository interface {
	Register(email, displayName, password, inviteCode string) (domain.User, string, error)
	Login(email, password string) (domain.User, string, error)
	AuthenticatedMe(token string) (domain.Me, bool)
	Me(userID string) (domain.User, bool)
	ListCalendars(userID string) []domain.Calendar
	CreateInvite(userID, calendarID string, input InviteInput) (domain.CalendarInvite, error)
	PreviewInvite(inviteCode string) (domain.CalendarInvite, error)
	AcceptInvite(userID, inviteCode string) (domain.CalendarInvite, error)
	AcceptInviteCalendar(userID, inviteCode string) (domain.Calendar, error)
	CreateCalendar(userID string, input CalendarInput) (domain.Calendar, error)
	UpdateCalendar(userID, calendarID string, patch CalendarPatch) (domain.Calendar, error)
	DeleteCalendar(userID, calendarID string) error
	ListEvents(userID, calendarID string, from, to *time.Time) ([]domain.Event, error)
	CreateEvent(userID, calendarID string, input EventInput) (domain.Event, error)
	UpdateEvent(userID, eventID string, patch EventPatch) (domain.Event, error)
	DeleteEvent(userID, eventID string) error
	LoadBudgetBoard(userID, monthKey string) (domain.BudgetBoard, error)
	SaveBudgetBoard(userID string, board domain.BudgetBoard) (domain.BudgetBoard, error)
	LoadBudgetTemplates(userID string) (domain.BudgetTemplates, error)
	SaveBudgetTemplates(userID string, templates domain.BudgetTemplates) (domain.BudgetTemplates, error)
}
