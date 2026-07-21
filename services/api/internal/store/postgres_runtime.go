package store

import (
	"context"
	"crypto/sha256"
	"database/sql"
	"encoding/hex"
	"errors"
	"fmt"
	"sort"
	"strings"
	"time"

	"golang.org/x/crypto/bcrypt"

	"github.com/kakao-ent/dayflow/services/api/internal/domain"
)

const demoInviteCode = "invite_abc"

type PostgresStore struct {
	db     *sql.DB
	budget *PostgresBudgetStore
	now    func() time.Time
	newID  func(prefix string) string
}

func NewPostgresStore(db *sql.DB) *PostgresStore {
	return &PostgresStore{
		db:     db,
		budget: NewPostgresBudgetStore(db),
		now:    func() time.Time { return time.Now().UTC() },
		newID:  newStoreID,
	}
}

func (s *PostgresStore) EnsureDemoSeed(ctx context.Context) error {
	now := s.now()
	users := []struct {
		id, email, displayName string
	}{
		{"usr_001", "owner@dayflow.local", "DayFlow Owner"},
		{"usr_002", "editor@dayflow.local", "Calendar Editor"},
		{"usr_003", "viewer@dayflow.local", "Calendar Viewer"},
		{"usr_004", "outside@dayflow.local", "Outside User"},
	}

	passwordHash := string(mustHashPassword("secret1234"))
	for _, user := range users {
		if _, err := s.db.ExecContext(ctx, `
INSERT INTO users (id, email, display_name, password_hash, created_at, updated_at)
VALUES ($1, $2, $3, $4, $5, $5)
ON CONFLICT (id) DO UPDATE
SET email = EXCLUDED.email,
    display_name = EXCLUDED.display_name,
    password_hash = EXCLUDED.password_hash,
    updated_at = EXCLUDED.updated_at`,
			user.id, user.email, user.displayName, passwordHash, now); err != nil {
			return fmt.Errorf("seed user %s: %w", user.id, err)
		}
	}

	calendars := []struct {
		id, ownerUserID, kind, name, color string
	}{
		{"cal_001", "usr_001", CalendarKindPersonal, "Personal", "#1F6B5C"},
		{"cal_002", "usr_001", CalendarKindShared, "Shared Home", "#D8A21D"},
		{"cal_003", "usr_002", CalendarKindPersonal, "Personal", "#5B7FFF"},
		{"cal_004", "usr_003", CalendarKindPersonal, "Personal", "#A657D6"},
		{"cal_005", "usr_004", CalendarKindPersonal, "Personal", "#FF7A59"},
	}
	for _, calendar := range calendars {
		if _, err := s.db.ExecContext(ctx, `
INSERT INTO calendars (id, owner_user_id, kind, name, color, created_at, updated_at)
VALUES ($1, $2, $3, $4, $5, $6, $6)
ON CONFLICT (id) DO UPDATE
SET owner_user_id = EXCLUDED.owner_user_id,
    kind = EXCLUDED.kind,
    name = EXCLUDED.name,
    color = EXCLUDED.color,
    updated_at = EXCLUDED.updated_at`,
			calendar.id, calendar.ownerUserID, calendar.kind, calendar.name, calendar.color, now); err != nil {
			return fmt.Errorf("seed calendar %s: %w", calendar.id, err)
		}
	}

	memberships := []struct {
		calendarID, userID, role string
	}{
		{"cal_001", "usr_001", RoleOwner},
		{"cal_002", "usr_001", RoleOwner},
		{"cal_002", "usr_002", RoleEditor},
		{"cal_002", "usr_003", RoleViewer},
		{"cal_003", "usr_002", RoleOwner},
		{"cal_004", "usr_003", RoleOwner},
		{"cal_005", "usr_004", RoleOwner},
	}
	for _, membership := range memberships {
		if _, err := s.db.ExecContext(ctx, `
INSERT INTO calendar_members (calendar_id, user_id, role, created_at)
VALUES ($1, $2, $3, $4)
ON CONFLICT (calendar_id, user_id) DO UPDATE
SET role = EXCLUDED.role`,
			membership.calendarID, membership.userID, membership.role, now); err != nil {
			return fmt.Errorf("seed membership %s/%s: %w", membership.calendarID, membership.userID, err)
		}
	}

	events := []struct {
		id, calendarID, title, notes, createdBy string
		startsAt, endsAt                        time.Time
		allDay                                  bool
	}{
		{
			id:         "evt_001",
			calendarID: "cal_001",
			title:      "월간 예산 점검",
			notes:      "budget is private and stays personal",
			createdBy:  "usr_001",
			startsAt:   now,
			endsAt:     now.Add(30 * time.Minute),
		},
		{
			id:         "evt_002",
			calendarID: "cal_002",
			title:      "보험비 정산",
			notes:      "25일 기준 확인",
			createdBy:  "usr_001",
			startsAt:   now.Add(24 * time.Hour),
			endsAt:     now.Add(25 * time.Hour),
		},
	}
	for _, event := range events {
		if _, err := s.db.ExecContext(ctx, `
INSERT INTO events (id, calendar_id, title, notes, starts_at, ends_at, all_day, created_by_user_id, updated_at)
VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9)
ON CONFLICT (id) DO UPDATE
SET calendar_id = EXCLUDED.calendar_id,
    title = EXCLUDED.title,
    notes = EXCLUDED.notes,
    starts_at = EXCLUDED.starts_at,
    ends_at = EXCLUDED.ends_at,
    all_day = EXCLUDED.all_day,
    created_by_user_id = EXCLUDED.created_by_user_id,
    updated_at = EXCLUDED.updated_at`,
			event.id, event.calendarID, event.title, event.notes, event.startsAt, event.endsAt, event.allDay, event.createdBy, now); err != nil {
			return fmt.Errorf("seed event %s: %w", event.id, err)
		}
	}

	if _, err := s.db.ExecContext(ctx, `
INSERT INTO calendar_invites (
    id, calendar_id, email, delivery_channel, role, invite_code,
    invited_by_user_id, expires_at, created_at, updated_at
)
VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $9)
ON CONFLICT (invite_code) DO UPDATE
SET calendar_id = EXCLUDED.calendar_id,
    email = EXCLUDED.email,
    delivery_channel = EXCLUDED.delivery_channel,
    role = EXCLUDED.role,
    invited_by_user_id = EXCLUDED.invited_by_user_id,
    expires_at = EXCLUDED.expires_at,
    updated_at = EXCLUDED.updated_at`,
		"cinv_001", "cal_002", "user@example.com", "sms", RoleViewer, demoInviteCode, "usr_001", now.Add(7*24*time.Hour), now); err != nil {
		return fmt.Errorf("seed demo invite: %w", err)
	}

	for _, user := range users {
		domainUser := domain.User{ID: user.id, Email: user.email, DisplayName: user.displayName}
		if err := s.budget.EnsureUser(ctx, domainUser); err != nil {
			return fmt.Errorf("seed budget user %s: %w", user.id, err)
		}
		if err := s.ensureDefaultBudgetTemplates(ctx, domainUser.ID); err != nil {
			return fmt.Errorf("seed default budget templates for %s: %w", user.id, err)
		}
	}

	return nil
}

func (s *PostgresStore) Register(email, displayName, password, inviteCode string) (domain.User, string, error) {
	ctx := context.Background()
	tx, err := s.db.BeginTx(ctx, nil)
	if err != nil {
		return domain.User{}, "", fmt.Errorf("begin register: %w", err)
	}
	defer func() {
		if err != nil {
			_ = tx.Rollback()
		}
	}()

	now := s.now()
	inviteRecord, err := s.loadInviteForUse(ctx, tx, inviteCode)
	if err != nil {
		return domain.User{}, "", err
	}

	normalizedEmail := normalizeEmail(email)
	if normalizeEmail(inviteRecord.Email) != normalizedEmail {
		return domain.User{}, "", ErrInviteEmailMismatch
	}
	if exists, existsErr := s.userExists(ctx, tx, normalizedEmail); existsErr != nil {
		return domain.User{}, "", existsErr
	} else if exists {
		return domain.User{}, "", ErrEmailTaken
	}

	user := domain.User{
		ID:          s.newID("usr"),
		Email:       normalizedEmail,
		DisplayName: strings.TrimSpace(displayName),
	}
	if _, err = tx.ExecContext(ctx, `
INSERT INTO users (id, email, display_name, password_hash, registered_by_invite_id, created_at, updated_at)
VALUES ($1, $2, $3, $4, $5, $6, $6)`,
		user.ID, user.Email, user.DisplayName, string(mustHashPassword(password)), inviteRecord.ID, now); err != nil {
		return domain.User{}, "", fmt.Errorf("create user: %w", err)
	}

	if err = s.insertCalendar(ctx, tx, domain.Calendar{
		ID:        s.newID("cal"),
		Kind:      CalendarKindPersonal,
		Name:      "Personal",
		Color:     "#5B7FFF",
		UpdatedAt: now.Format(time.RFC3339),
	}, user.ID, RoleOwner, now); err != nil {
		return domain.User{}, "", err
	}

	if _, err = s.acceptInviteTx(ctx, tx, user.ID, user.Email, inviteCode, now); err != nil {
		return domain.User{}, "", err
	}

	sessionToken, sessionHash := newSessionToken()
	if err = s.insertSession(ctx, tx, user.ID, sessionHash, now); err != nil {
		return domain.User{}, "", err
	}
	if err = s.budget.EnsureUser(ctx, user); err != nil {
		return domain.User{}, "", err
	}
	if err = tx.Commit(); err != nil {
		return domain.User{}, "", fmt.Errorf("commit register: %w", err)
	}
	return user, sessionToken, nil
}

func (s *PostgresStore) Login(email, password string) (domain.User, string, error) {
	ctx := context.Background()
	row := s.db.QueryRowContext(ctx, `
SELECT id, email, display_name, password_hash
FROM users
WHERE LOWER(email) = LOWER($1)`, strings.TrimSpace(email))

	var user domain.User
	var passwordHash string
	if err := row.Scan(&user.ID, &user.Email, &user.DisplayName, &passwordHash); err != nil {
		if errors.Is(err, sql.ErrNoRows) {
			return domain.User{}, "", ErrInvalidCredentials
		}
		return domain.User{}, "", fmt.Errorf("load login user: %w", err)
	}
	if err := bcrypt.CompareHashAndPassword([]byte(passwordHash), []byte(password)); err != nil {
		return domain.User{}, "", ErrInvalidCredentials
	}

	token, tokenHash := newSessionToken()
	if err := s.insertSession(ctx, nil, user.ID, tokenHash, s.now()); err != nil {
		return domain.User{}, "", err
	}
	return user, token, nil
}

func (s *PostgresStore) AuthenticatedMe(token string) (domain.Me, bool) {
	ctx := context.Background()
	tx, err := s.db.BeginTx(ctx, nil)
	if err != nil {
		return domain.Me{}, false
	}
	defer func() { _ = tx.Rollback() }()

	user, ok, err := s.authenticateSession(ctx, tx, token)
	if err != nil || !ok {
		return domain.Me{}, false
	}
	me, err := s.meByUserID(ctx, tx, user.ID)
	if err != nil {
		return domain.Me{}, false
	}
	if err := tx.Commit(); err != nil {
		return domain.Me{}, false
	}
	return me, true
}

func (s *PostgresStore) Me(userID string) (domain.User, bool) {
	row := s.db.QueryRowContext(context.Background(), `
SELECT id, email, display_name
FROM users
WHERE id = $1`, userID)

	var user domain.User
	if err := row.Scan(&user.ID, &user.Email, &user.DisplayName); err != nil {
		return domain.User{}, false
	}
	return user, true
}

func (s *PostgresStore) ListCalendars(userID string) []domain.Calendar {
	rows, err := s.db.QueryContext(context.Background(), `
SELECT c.id, c.kind, c.name, c.color, c.updated_at, cm.role
FROM calendar_members cm
JOIN calendars c ON c.id = cm.calendar_id
WHERE cm.user_id = $1 AND c.kind = 'shared'
ORDER BY c.id ASC`, userID)
	if err != nil {
		return []domain.Calendar{}
	}
	defer rows.Close()

	items := make([]domain.Calendar, 0)
	for rows.Next() {
		var calendar domain.Calendar
		var updatedAt time.Time
		if err := rows.Scan(&calendar.ID, &calendar.Kind, &calendar.Name, &calendar.Color, &updatedAt, &calendar.MembershipRole); err != nil {
			return []domain.Calendar{}
		}
		calendar.UpdatedAt = updatedAt.UTC().Format(time.RFC3339)
		items = append(items, calendar)
	}
	return items
}

func (s *PostgresStore) CreateInvite(userID, calendarID string, input InviteInput) (domain.CalendarInvite, error) {
	if err := validateInviteInput(input); err != nil {
		return domain.CalendarInvite{}, err
	}
	ctx := context.Background()
	tx, err := s.db.BeginTx(ctx, nil)
	if err != nil {
		return domain.CalendarInvite{}, fmt.Errorf("begin create invite: %w", err)
	}
	defer func() {
		if err != nil {
			_ = tx.Rollback()
		}
	}()

	calendar, role, err := s.calendarForAccessTx(ctx, tx, userID, calendarID)
	if err != nil {
		return domain.CalendarInvite{}, err
	}
	if role != RoleOwner || calendar.ownerUserID != userID {
		return domain.CalendarInvite{}, ErrForbidden
	}
	if calendar.calendar.Kind != CalendarKindShared {
		return domain.CalendarInvite{}, fmt.Errorf("invites are allowed only for shared calendars: %w", ErrInvalidInput)
	}

	normalizedEmail := normalizeEmail(input.Email)
	if owner, ok := s.Me(calendar.ownerUserID); ok && normalizeEmail(owner.Email) == normalizedEmail {
		return domain.CalendarInvite{}, fmt.Errorf("calendar owner cannot be invited: %w", ErrInvalidInput)
	}
	memberExists, err := s.calendarMemberByEmail(ctx, tx, calendarID, normalizedEmail)
	if err != nil {
		return domain.CalendarInvite{}, err
	}
	if memberExists {
		return domain.CalendarInvite{}, fmt.Errorf("user is already a calendar member: %w", ErrInvalidInput)
	}

	now := s.now()
	var invite domain.CalendarInvite
	var invitedByDisplayName string
	row := tx.QueryRowContext(ctx, `
SELECT ci.id, ci.calendar_id, c.name, ci.email, ci.delivery_channel, ci.role, ci.invite_code,
       ci.invited_by_user_id, u.display_name, ci.accepted_by_user_id, ci.accepted_at, ci.expires_at, ci.updated_at
FROM calendar_invites ci
JOIN calendars c ON c.id = ci.calendar_id
JOIN users u ON u.id = ci.invited_by_user_id
WHERE ci.calendar_id = $1 AND LOWER(ci.email) = LOWER($2)`, calendarID, normalizedEmail)
	var acceptedBy sql.NullString
	var acceptedAt sql.NullTime
	var expiresAt sql.NullTime
	var updatedAt time.Time
	switch scanErr := row.Scan(&invite.ID, &invite.CalendarID, &invite.CalendarName, &invite.Email, &invite.DeliveryChannel, &invite.Role, &invite.InviteCode, &invite.InvitedByUserID, &invitedByDisplayName, &acceptedBy, &acceptedAt, &expiresAt, &updatedAt); {
	case scanErr == nil:
		if acceptedBy.Valid {
			return domain.CalendarInvite{}, fmt.Errorf("user is already a calendar member: %w", ErrInvalidInput)
		}
		if _, err = tx.ExecContext(ctx, `
UPDATE calendar_invites
SET delivery_channel = $2, role = $3, updated_at = $4
WHERE id = $1`, invite.ID, input.DeliveryChannel, input.Role, now); err != nil {
			return domain.CalendarInvite{}, fmt.Errorf("update existing invite: %w", err)
		}
		invite.DeliveryChannel = input.DeliveryChannel
		invite.Role = input.Role
		invite.UpdatedAt = now.Format(time.RFC3339)
	case errors.Is(scanErr, sql.ErrNoRows):
		invite = domain.CalendarInvite{
			ID:                   s.newID("cinv"),
			CalendarID:           calendarID,
			CalendarName:         calendar.calendar.Name,
			Email:                normalizedEmail,
			DeliveryChannel:      input.DeliveryChannel,
			Role:                 input.Role,
			InviteCode:           "invite_" + strings.TrimPrefix(s.newID("code"), "code_"),
			InvitedByUserID:      userID,
			InvitedByDisplayName: ownerDisplayName(ctx, tx, userID),
			ExpiresAt:            now.Add(7 * 24 * time.Hour).Format(time.RFC3339),
			UpdatedAt:            now.Format(time.RFC3339),
		}
		if _, err = tx.ExecContext(ctx, `
INSERT INTO calendar_invites (
    id, calendar_id, email, delivery_channel, role, invite_code,
    invited_by_user_id, expires_at, created_at, updated_at
)
VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $9)`,
			invite.ID, invite.CalendarID, invite.Email, invite.DeliveryChannel, invite.Role, invite.InviteCode, invite.InvitedByUserID, now.Add(7*24*time.Hour), now); err != nil {
			return domain.CalendarInvite{}, fmt.Errorf("insert invite: %w", err)
		}
	default:
		return domain.CalendarInvite{}, fmt.Errorf("load invite: %w", scanErr)
	}

	invite.InviteURL = fmt.Sprintf("https://dayflow.local/invites/%s", invite.InviteCode)
	if invite.InvitedByDisplayName == "" {
		invite.InvitedByDisplayName = ownerDisplayName(ctx, tx, userID)
	}
	if err := tx.Commit(); err != nil {
		return domain.CalendarInvite{}, fmt.Errorf("commit create invite: %w", err)
	}
	return invite, nil
}

func (s *PostgresStore) PreviewInvite(inviteCode string) (domain.CalendarInvite, error) {
	return s.previewInvite(context.Background(), nil, inviteCode)
}

func (s *PostgresStore) AcceptInvite(userID, inviteCode string) (domain.CalendarInvite, error) {
	user, ok := s.Me(userID)
	if !ok {
		return domain.CalendarInvite{}, ErrForbidden
	}
	ctx := context.Background()
	tx, err := s.db.BeginTx(ctx, nil)
	if err != nil {
		return domain.CalendarInvite{}, fmt.Errorf("begin accept invite: %w", err)
	}
	defer func() {
		if err != nil {
			_ = tx.Rollback()
		}
	}()
	invite, err := s.acceptInviteTx(ctx, tx, user.ID, user.Email, inviteCode, s.now())
	if err != nil {
		return domain.CalendarInvite{}, err
	}
	if err := tx.Commit(); err != nil {
		return domain.CalendarInvite{}, fmt.Errorf("commit accept invite: %w", err)
	}
	return invite, nil
}

func (s *PostgresStore) AcceptInviteCalendar(userID, inviteCode string) (domain.Calendar, error) {
	invite, err := s.AcceptInvite(userID, inviteCode)
	if err != nil {
		return domain.Calendar{}, err
	}
	row := s.db.QueryRowContext(context.Background(), `
SELECT id, kind, name, color, updated_at
FROM calendars
WHERE id = $1`, invite.CalendarID)

	var calendar domain.Calendar
	var updatedAt time.Time
	if err := row.Scan(&calendar.ID, &calendar.Kind, &calendar.Name, &calendar.Color, &updatedAt); err != nil {
		if errors.Is(err, sql.ErrNoRows) {
			return domain.Calendar{}, ErrNotFound
		}
		return domain.Calendar{}, fmt.Errorf("load accepted calendar: %w", err)
	}
	calendar.UpdatedAt = updatedAt.UTC().Format(time.RFC3339)
	calendar.MembershipRole = invite.Role
	return calendar, nil
}

func (s *PostgresStore) CreateCalendar(userID string, input CalendarInput) (domain.Calendar, error) {
	if err := validateCalendarInput(input); err != nil {
		return domain.Calendar{}, err
	}
	if _, ok := s.Me(userID); !ok {
		return domain.Calendar{}, ErrForbidden
	}

	now := s.now()
	calendar := domain.Calendar{
		ID:        s.newID("cal"),
		Kind:      CalendarKindShared,
		Name:      strings.TrimSpace(input.Name),
		Color:     strings.ToUpper(strings.TrimSpace(input.Color)),
		UpdatedAt: now.Format(time.RFC3339),
	}
	tx, err := s.db.BeginTx(context.Background(), nil)
	if err != nil {
		return domain.Calendar{}, fmt.Errorf("begin create calendar: %w", err)
	}
	defer func() {
		if err != nil {
			_ = tx.Rollback()
		}
	}()
	if err = s.insertCalendar(context.Background(), tx, calendar, userID, RoleOwner, now); err != nil {
		return domain.Calendar{}, err
	}
	if err := tx.Commit(); err != nil {
		return domain.Calendar{}, fmt.Errorf("commit create calendar: %w", err)
	}
	return calendar, nil
}

func (s *PostgresStore) UpdateCalendar(userID, calendarID string, patch CalendarPatch) (domain.Calendar, error) {
	ctx := context.Background()
	tx, err := s.db.BeginTx(ctx, nil)
	if err != nil {
		return domain.Calendar{}, fmt.Errorf("begin update calendar: %w", err)
	}
	defer func() {
		if err != nil {
			_ = tx.Rollback()
		}
	}()

	record, role, err := s.calendarForAccessTx(ctx, tx, userID, calendarID)
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
		record.calendar.Name = name
	}
	if patch.Color != nil {
		color := strings.ToUpper(strings.TrimSpace(*patch.Color))
		if !calendarColorPattern.MatchString(color) {
			return domain.Calendar{}, fmt.Errorf("calendar color must be #RRGGBB: %w", ErrInvalidInput)
		}
		record.calendar.Color = color
	}
	now := s.now()
	if _, err = tx.ExecContext(ctx, `
UPDATE calendars
SET name = $2, color = $3, updated_at = $4
WHERE id = $1`, calendarID, record.calendar.Name, record.calendar.Color, now); err != nil {
		return domain.Calendar{}, fmt.Errorf("update calendar: %w", err)
	}
	if err := tx.Commit(); err != nil {
		return domain.Calendar{}, fmt.Errorf("commit update calendar: %w", err)
	}
	record.calendar.UpdatedAt = now.Format(time.RFC3339)
	record.calendar.MembershipRole = role
	return record.calendar, nil
}

func (s *PostgresStore) DeleteCalendar(userID, calendarID string) error {
	ctx := context.Background()
	tx, err := s.db.BeginTx(ctx, nil)
	if err != nil {
		return fmt.Errorf("begin delete calendar: %w", err)
	}
	defer func() {
		if err != nil {
			_ = tx.Rollback()
		}
	}()

	record, role, err := s.calendarForAccessTx(ctx, tx, userID, calendarID)
	if err != nil {
		return err
	}
	if role != RoleOwner {
		return ErrForbidden
	}
	if record.calendar.Kind == CalendarKindPersonal {
		return fmt.Errorf("personal calendars cannot be deleted: %w", ErrInvalidInput)
	}
	if _, err = tx.ExecContext(ctx, `DELETE FROM calendars WHERE id = $1`, calendarID); err != nil {
		return fmt.Errorf("delete calendar: %w", err)
	}
	return tx.Commit()
}

func (s *PostgresStore) ListEvents(userID, calendarID string, from, to *time.Time) ([]domain.Event, error) {
	_, role, err := s.calendarForAccess(userID, calendarID)
	if err != nil {
		return nil, err
	}
	_ = role

	query := `
SELECT id, calendar_id, title, notes, starts_at, ends_at, all_day, updated_at
FROM events
WHERE calendar_id = $1`
	args := []any{calendarID}
	if from != nil {
		query += " AND ends_at >= $2"
		args = append(args, *from)
	}
	if to != nil {
		query += fmt.Sprintf(" AND starts_at <= $%d", len(args)+1)
		args = append(args, *to)
	}
	query += " ORDER BY starts_at ASC, id ASC"

	rows, err := s.db.QueryContext(context.Background(), query, args...)
	if err != nil {
		return nil, fmt.Errorf("list events: %w", err)
	}
	defer rows.Close()

	items := make([]domain.Event, 0)
	for rows.Next() {
		var event domain.Event
		var startsAt, endsAt, updatedAt time.Time
		if err := rows.Scan(&event.ID, &event.CalendarID, &event.Title, &event.Notes, &startsAt, &endsAt, &event.AllDay, &updatedAt); err != nil {
			return nil, fmt.Errorf("scan event: %w", err)
		}
		event.StartsAt = startsAt.UTC().Format(time.RFC3339)
		event.EndsAt = endsAt.UTC().Format(time.RFC3339)
		event.UpdatedAt = updatedAt.UTC().Format(time.RFC3339)
		items = append(items, event)
	}
	return items, rows.Err()
}

func (s *PostgresStore) CreateEvent(userID, calendarID string, input EventInput) (domain.Event, error) {
	if err := validateEventInput(input); err != nil {
		return domain.Event{}, err
	}
	_, role, err := s.calendarForAccess(userID, calendarID)
	if err != nil {
		return domain.Event{}, err
	}
	if !canEditEvents(role) {
		return domain.Event{}, ErrForbidden
	}

	now := s.now()
	event := domain.Event{
		ID:         s.newID("evt"),
		CalendarID: calendarID,
		Title:      strings.TrimSpace(input.Title),
		Notes:      strings.TrimSpace(input.Notes),
		StartsAt:   input.StartsAt.UTC().Format(time.RFC3339),
		EndsAt:     input.EndsAt.UTC().Format(time.RFC3339),
		AllDay:     input.AllDay,
		UpdatedAt:  now.Format(time.RFC3339),
	}
	if _, err := s.db.ExecContext(context.Background(), `
INSERT INTO events (id, calendar_id, title, notes, starts_at, ends_at, all_day, created_by_user_id, updated_at)
VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9)`,
		event.ID, event.CalendarID, event.Title, event.Notes, input.StartsAt.UTC(), input.EndsAt.UTC(), event.AllDay, userID, now); err != nil {
		return domain.Event{}, fmt.Errorf("create event: %w", err)
	}
	return event, nil
}

func (s *PostgresStore) UpdateEvent(userID, eventID string, patch EventPatch) (domain.Event, error) {
	ctx := context.Background()
	tx, err := s.db.BeginTx(ctx, nil)
	if err != nil {
		return domain.Event{}, fmt.Errorf("begin update event: %w", err)
	}
	defer func() {
		if err != nil {
			_ = tx.Rollback()
		}
	}()

	var event domain.Event
	var startsAt, endsAt time.Time
	row := tx.QueryRowContext(ctx, `
SELECT id, calendar_id, title, notes, starts_at, ends_at, all_day, updated_at
FROM events
WHERE id = $1`, eventID)
	var updatedAt time.Time
	if err := row.Scan(&event.ID, &event.CalendarID, &event.Title, &event.Notes, &startsAt, &endsAt, &event.AllDay, &updatedAt); err != nil {
		if errors.Is(err, sql.ErrNoRows) {
			return domain.Event{}, ErrNotFound
		}
		return domain.Event{}, fmt.Errorf("load event: %w", err)
	}

	_, role, err := s.calendarForAccessTx(ctx, tx, userID, event.CalendarID)
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
		event.Title = title
	}
	if patch.Notes != nil {
		event.Notes = strings.TrimSpace(*patch.Notes)
	}
	if patch.StartsAt != nil {
		startsAt = patch.StartsAt.UTC()
	}
	if patch.EndsAt != nil {
		endsAt = patch.EndsAt.UTC()
	}
	if patch.AllDay != nil {
		event.AllDay = *patch.AllDay
	}
	event.StartsAt = startsAt.Format(time.RFC3339)
	event.EndsAt = endsAt.Format(time.RFC3339)
	if err := validateEventRecord(event); err != nil {
		return domain.Event{}, err
	}
	now := s.now()
	if _, err = tx.ExecContext(ctx, `
UPDATE events
SET title = $2, notes = $3, starts_at = $4, ends_at = $5, all_day = $6, updated_at = $7
WHERE id = $1`, event.ID, event.Title, event.Notes, startsAt, endsAt, event.AllDay, now); err != nil {
		return domain.Event{}, fmt.Errorf("update event: %w", err)
	}
	if err := tx.Commit(); err != nil {
		return domain.Event{}, fmt.Errorf("commit update event: %w", err)
	}
	event.UpdatedAt = now.Format(time.RFC3339)
	return event, nil
}

func (s *PostgresStore) DeleteEvent(userID, eventID string) error {
	ctx := context.Background()
	tx, err := s.db.BeginTx(ctx, nil)
	if err != nil {
		return fmt.Errorf("begin delete event: %w", err)
	}
	defer func() {
		if err != nil {
			_ = tx.Rollback()
		}
	}()

	var calendarID string
	row := tx.QueryRowContext(ctx, `SELECT calendar_id FROM events WHERE id = $1`, eventID)
	if err := row.Scan(&calendarID); err != nil {
		if errors.Is(err, sql.ErrNoRows) {
			return ErrNotFound
		}
		return fmt.Errorf("load event calendar: %w", err)
	}
	_, role, err := s.calendarForAccessTx(ctx, tx, userID, calendarID)
	if err != nil {
		return err
	}
	if !canEditEvents(role) {
		return ErrForbidden
	}
	if _, err := tx.ExecContext(ctx, `DELETE FROM events WHERE id = $1`, eventID); err != nil {
		return fmt.Errorf("delete event: %w", err)
	}
	return tx.Commit()
}

func (s *PostgresStore) LoadBudgetBoard(userID, monthKey string) (domain.BudgetBoard, error) {
	return s.budget.LoadBudgetBoard(context.Background(), userID, monthKey)
}

func (s *PostgresStore) SaveBudgetBoard(userID string, board domain.BudgetBoard) (domain.BudgetBoard, error) {
	return s.budget.SaveBudgetBoard(context.Background(), userID, board)
}

func (s *PostgresStore) LoadBudgetTemplates(userID string) (domain.BudgetTemplates, error) {
	return s.budget.LoadBudgetTemplates(context.Background(), userID)
}

func (s *PostgresStore) SaveBudgetTemplates(userID string, templates domain.BudgetTemplates) (domain.BudgetTemplates, error) {
	return s.budget.SaveBudgetTemplates(context.Background(), userID, templates)
}

type postgresCalendarRecord struct {
	calendar    domain.Calendar
	ownerUserID string
}

func (s *PostgresStore) authenticateSession(ctx context.Context, tx *sql.Tx, token string) (domain.User, bool, error) {
	tokenHash := hashToken(token)
	row := tx.QueryRowContext(ctx, `
SELECT u.id, u.email, u.display_name, us.id
FROM user_sessions us
JOIN users u ON u.id = us.user_id
WHERE us.token_hash = $1 AND us.revoked_at IS NULL AND us.expires_at > $2`, tokenHash, s.now())

	var user domain.User
	var sessionID string
	if err := row.Scan(&user.ID, &user.Email, &user.DisplayName, &sessionID); err != nil {
		if errors.Is(err, sql.ErrNoRows) {
			return domain.User{}, false, nil
		}
		return domain.User{}, false, err
	}
	if _, err := tx.ExecContext(ctx, `UPDATE user_sessions SET last_used_at = $2 WHERE id = $1`, sessionID, s.now()); err != nil {
		return domain.User{}, false, err
	}
	return user, true, nil
}

func (s *PostgresStore) insertSession(ctx context.Context, tx *sql.Tx, userID, tokenHash string, now time.Time) error {
	queryer := execer(tx, s.db)
	if _, err := queryer.ExecContext(ctx, `
INSERT INTO user_sessions (id, user_id, token_hash, last_used_at, expires_at, created_at)
VALUES ($1, $2, $3, $4, $5, $4)`,
		s.newID("sess"), userID, tokenHash, now, now.Add(30*24*time.Hour)); err != nil {
		return fmt.Errorf("create session: %w", err)
	}
	return nil
}

func (s *PostgresStore) userExists(ctx context.Context, tx *sql.Tx, email string) (bool, error) {
	var exists bool
	if err := tx.QueryRowContext(ctx, `SELECT EXISTS(SELECT 1 FROM users WHERE LOWER(email) = LOWER($1))`, email).Scan(&exists); err != nil {
		return false, fmt.Errorf("check user exists: %w", err)
	}
	return exists, nil
}

func (s *PostgresStore) meByUserID(ctx context.Context, tx *sql.Tx, userID string) (domain.Me, error) {
	row := tx.QueryRowContext(ctx, `SELECT id, email, display_name FROM users WHERE id = $1`, userID)
	var user domain.User
	if err := row.Scan(&user.ID, &user.Email, &user.DisplayName); err != nil {
		return domain.Me{}, err
	}
	rows, err := tx.QueryContext(ctx, `
SELECT c.id, c.kind, c.name, c.color, c.updated_at
FROM calendar_members cm
JOIN calendars c ON c.id = cm.calendar_id
WHERE cm.user_id = $1
ORDER BY c.id ASC`, userID)
	if err != nil {
		return domain.Me{}, err
	}
	defer rows.Close()

	var personal domain.Calendar
	shared := make([]domain.Calendar, 0)
	for rows.Next() {
		var calendar domain.Calendar
		var updatedAt time.Time
		if err := rows.Scan(&calendar.ID, &calendar.Kind, &calendar.Name, &calendar.Color, &updatedAt); err != nil {
			return domain.Me{}, err
		}
		calendar.UpdatedAt = updatedAt.UTC().Format(time.RFC3339)
		if calendar.Kind == CalendarKindPersonal {
			personal = calendar
			continue
		}
		shared = append(shared, calendar)
	}
	sort.Slice(shared, func(i, j int) bool { return shared[i].ID < shared[j].ID })
	return domain.Me{
		User:                  user,
		PersonalCalendar:      personal,
		SharedCalendars:       shared,
		CurrentBudgetMonthKey: s.now().Format("2006-01"),
	}, nil
}

func (s *PostgresStore) calendarForAccess(userID, calendarID string) (postgresCalendarRecord, string, error) {
	ctx := context.Background()
	tx, err := s.db.BeginTx(ctx, nil)
	if err != nil {
		return postgresCalendarRecord{}, "", err
	}
	defer func() { _ = tx.Rollback() }()
	record, role, err := s.calendarForAccessTx(ctx, tx, userID, calendarID)
	return record, role, err
}

func (s *PostgresStore) calendarForAccessTx(ctx context.Context, tx *sql.Tx, userID, calendarID string) (postgresCalendarRecord, string, error) {
	row := tx.QueryRowContext(ctx, `
SELECT c.id, c.kind, c.name, c.color, c.owner_user_id, c.updated_at, cm.role
FROM calendars c
LEFT JOIN calendar_members cm ON cm.calendar_id = c.id AND cm.user_id = $2
WHERE c.id = $1`, calendarID, userID)

	var record postgresCalendarRecord
	var role sql.NullString
	var updatedAt time.Time
	if err := row.Scan(&record.calendar.ID, &record.calendar.Kind, &record.calendar.Name, &record.calendar.Color, &record.ownerUserID, &updatedAt, &role); err != nil {
		if errors.Is(err, sql.ErrNoRows) {
			return postgresCalendarRecord{}, "", ErrNotFound
		}
		return postgresCalendarRecord{}, "", fmt.Errorf("load calendar access: %w", err)
	}
	if !role.Valid {
		return postgresCalendarRecord{}, "", ErrForbidden
	}
	record.calendar.UpdatedAt = updatedAt.UTC().Format(time.RFC3339)
	return record, role.String, nil
}

func (s *PostgresStore) previewInvite(ctx context.Context, tx *sql.Tx, inviteCode string) (domain.CalendarInvite, error) {
	queryer := queryer(tx, s.db)
	row := queryer.QueryRowContext(ctx, `
SELECT ci.id, ci.calendar_id, c.name, ci.email, ci.delivery_channel, ci.role, ci.invite_code,
       ci.invited_by_user_id, u.display_name, ci.accepted_by_user_id, ci.accepted_at, ci.expires_at, ci.updated_at
FROM calendar_invites ci
JOIN calendars c ON c.id = ci.calendar_id
JOIN users u ON u.id = ci.invited_by_user_id
WHERE ci.invite_code = $1 AND c.kind = 'shared'`, inviteCode)

	var invite domain.CalendarInvite
	var invitedByDisplayName string
	var acceptedBy sql.NullString
	var acceptedAt, expiresAt sql.NullTime
	var updatedAt time.Time
	if err := row.Scan(&invite.ID, &invite.CalendarID, &invite.CalendarName, &invite.Email, &invite.DeliveryChannel, &invite.Role, &invite.InviteCode, &invite.InvitedByUserID, &invitedByDisplayName, &acceptedBy, &acceptedAt, &expiresAt, &updatedAt); err != nil {
		if errors.Is(err, sql.ErrNoRows) {
			return domain.CalendarInvite{}, ErrInvalidInvite
		}
		return domain.CalendarInvite{}, fmt.Errorf("load invite preview: %w", err)
	}
	invite.InviteURL = fmt.Sprintf("https://dayflow.local/invites/%s", invite.InviteCode)
	invite.InvitedByDisplayName = invitedByDisplayName
	if acceptedBy.Valid {
		invite.AcceptedByUserID = acceptedBy.String
	}
	if acceptedAt.Valid {
		invite.AcceptedAt = acceptedAt.Time.UTC().Format(time.RFC3339)
	}
	if expiresAt.Valid {
		invite.ExpiresAt = expiresAt.Time.UTC().Format(time.RFC3339)
	}
	invite.UpdatedAt = updatedAt.UTC().Format(time.RFC3339)
	return invite, nil
}

func (s *PostgresStore) loadInviteForUse(ctx context.Context, tx *sql.Tx, inviteCode string) (domain.CalendarInvite, error) {
	invite, err := s.previewInvite(ctx, tx, inviteCode)
	if err != nil {
		return domain.CalendarInvite{}, err
	}
	return invite, nil
}

func (s *PostgresStore) acceptInviteTx(ctx context.Context, tx *sql.Tx, userID, email, inviteCode string, now time.Time) (domain.CalendarInvite, error) {
	invite, err := s.loadInviteForUse(ctx, tx, inviteCode)
	if err != nil {
		return domain.CalendarInvite{}, err
	}
	if normalizeEmail(invite.Email) != normalizeEmail(email) {
		return domain.CalendarInvite{}, ErrInviteEmailMismatch
	}
	if invite.AcceptedByUserID != "" {
		if invite.AcceptedByUserID != userID {
			return domain.CalendarInvite{}, ErrInvalidInvite
		}
		return invite, nil
	}

	role := invite.Role
	if role == "" {
		role = RoleViewer
	}

	record, existingRole, err := s.calendarForAccessTx(ctx, tx, userID, invite.CalendarID)
	switch {
	case err == nil && existingRole == RoleOwner:
		return domain.CalendarInvite{}, fmt.Errorf("calendar owner cannot accept invite: %w", ErrInvalidInput)
	case err == nil:
		_ = record
	case errors.Is(err, ErrForbidden):
		// new membership path
	default:
		if !errors.Is(err, ErrNotFound) {
			return domain.CalendarInvite{}, err
		}
		return domain.CalendarInvite{}, ErrInvalidInvite
	}

	if _, err := tx.ExecContext(ctx, `
INSERT INTO calendar_members (calendar_id, user_id, role, created_at)
VALUES ($1, $2, $3, $4)
ON CONFLICT (calendar_id, user_id) DO UPDATE
SET role = EXCLUDED.role`, invite.CalendarID, userID, role, now); err != nil {
		return domain.CalendarInvite{}, fmt.Errorf("create membership from invite: %w", err)
	}

	if _, err := tx.ExecContext(ctx, `
UPDATE calendar_invites
SET accepted_by_user_id = $2, accepted_at = $3, updated_at = $3
WHERE id = $1`, invite.ID, userID, now); err != nil {
		return domain.CalendarInvite{}, fmt.Errorf("mark invite accepted: %w", err)
	}
	invite.AcceptedByUserID = userID
	invite.AcceptedAt = now.Format(time.RFC3339)
	invite.UpdatedAt = invite.AcceptedAt
	invite.Role = role
	return invite, nil
}

func (s *PostgresStore) insertCalendar(ctx context.Context, tx *sql.Tx, calendar domain.Calendar, ownerUserID, ownerRole string, now time.Time) error {
	if _, err := tx.ExecContext(ctx, `
INSERT INTO calendars (id, owner_user_id, kind, name, color, created_at, updated_at)
VALUES ($1, $2, $3, $4, $5, $6, $6)`,
		calendar.ID, ownerUserID, calendar.Kind, calendar.Name, calendar.Color, now); err != nil {
		return fmt.Errorf("insert calendar: %w", err)
	}
	if _, err := tx.ExecContext(ctx, `
INSERT INTO calendar_members (calendar_id, user_id, role, created_at)
VALUES ($1, $2, $3, $4)`,
		calendar.ID, ownerUserID, ownerRole, now); err != nil {
		return fmt.Errorf("insert calendar owner membership: %w", err)
	}
	return nil
}

func (s *PostgresStore) calendarMemberByEmail(ctx context.Context, tx *sql.Tx, calendarID, email string) (bool, error) {
	var exists bool
	if err := tx.QueryRowContext(ctx, `
SELECT EXISTS(
    SELECT 1
    FROM calendar_members cm
    JOIN users u ON u.id = cm.user_id
    WHERE cm.calendar_id = $1 AND LOWER(u.email) = LOWER($2)
)`, calendarID, email).Scan(&exists); err != nil {
		return false, fmt.Errorf("check calendar member by email: %w", err)
	}
	return exists, nil
}

func ownerDisplayName(ctx context.Context, tx *sql.Tx, userID string) string {
	var displayName string
	if err := tx.QueryRowContext(ctx, `SELECT display_name FROM users WHERE id = $1`, userID).Scan(&displayName); err != nil {
		return ""
	}
	return displayName
}

type contextExecQuerier interface {
	ExecContext(context.Context, string, ...any) (sql.Result, error)
	QueryRowContext(context.Context, string, ...any) *sql.Row
}

func execer(tx *sql.Tx, db *sql.DB) interface {
	ExecContext(context.Context, string, ...any) (sql.Result, error)
} {
	if tx != nil {
		return tx
	}
	return db
}

func queryer(tx *sql.Tx, db *sql.DB) contextExecQuerier {
	if tx != nil {
		return tx
	}
	return db
}

func newSessionToken() (string, string) {
	token := newToken()
	return token, hashToken(token)
}

func hashToken(token string) string {
	sum := sha256.Sum256([]byte(token))
	return hex.EncodeToString(sum[:])
}

func (s *PostgresStore) ensureDefaultBudgetTemplates(ctx context.Context, userID string) error {
	templates, err := s.budget.LoadBudgetTemplates(ctx, userID)
	if err != nil && !errors.Is(err, ErrNotFound) {
		return err
	}
	if len(templates.FixedItems) > 0 {
		return nil
	}

	defaultsStore := NewMemoryStore()
	defaultTemplates, err := defaultsStore.LoadBudgetTemplates(userID)
	if err != nil {
		return err
	}
	for index := range defaultTemplates.FixedItems {
		defaultTemplates.FixedItems[index].ID = ""
	}
	_, err = s.budget.SaveBudgetTemplates(ctx, userID, defaultTemplates)
	return err
}
