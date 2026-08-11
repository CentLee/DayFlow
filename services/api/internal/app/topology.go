package app

import (
	"context"
	"database/sql"
	"fmt"
	"os"
	"strings"
)

// IdentityTopology is the fixed, deployment-owned DayFlow household mapping.
// Subjects authorize identity; normalized emails are only a deployment guard.
type IdentityTopology struct {
	OwnerSubject   string
	OwnerEmail     string
	PartnerSubject string
	PartnerEmail   string
}

func topologyFromEnv() (IdentityTopology, error) {
	topology := IdentityTopology{
		OwnerSubject:   strings.TrimSpace(os.Getenv("DAYFLOW_OWNER_GOOGLE_SUBJECT")),
		OwnerEmail:     normalizeTopologyEmail(os.Getenv("DAYFLOW_OWNER_EMAIL")),
		PartnerSubject: strings.TrimSpace(os.Getenv("DAYFLOW_PARTNER_GOOGLE_SUBJECT")),
		PartnerEmail:   normalizeTopologyEmail(os.Getenv("DAYFLOW_PARTNER_EMAIL")),
	}
	return topology, topology.Validate()
}

func (t IdentityTopology) Validate() error {
	if t.OwnerSubject == "" || t.PartnerSubject == "" || t.OwnerEmail == "" || t.PartnerEmail == "" {
		return fmt.Errorf("DAYFLOW_OWNER_GOOGLE_SUBJECT, DAYFLOW_OWNER_EMAIL, DAYFLOW_PARTNER_GOOGLE_SUBJECT, and DAYFLOW_PARTNER_EMAIL are required")
	}
	if t.OwnerSubject == t.PartnerSubject {
		return fmt.Errorf("owner and partner Google subjects must differ")
	}
	if t.OwnerEmail == t.PartnerEmail {
		return fmt.Errorf("owner and partner normalized emails must differ")
	}
	for _, email := range []string{t.OwnerEmail, t.PartnerEmail} {
		if !strings.Contains(email, "@") || strings.HasPrefix(email, "@") || strings.HasSuffix(email, "@") {
			return fmt.Errorf("invalid normalized deployment email %q", email)
		}
	}
	return nil
}

func normalizeTopologyEmail(email string) string {
	return strings.ToLower(strings.TrimSpace(email))
}

type topologyUser struct {
	id    string
	email string
}

// applyTwoPersonTopology binds the two existing users without changing their
// IDs or personal calendars. Every precondition is checked before a write.
func applyTwoPersonTopology(ctx context.Context, db *sql.DB, topology IdentityTopology) error {
	topology.OwnerEmail = normalizeTopologyEmail(topology.OwnerEmail)
	topology.PartnerEmail = normalizeTopologyEmail(topology.PartnerEmail)
	if err := topology.Validate(); err != nil {
		return fmt.Errorf("deployment topology is not ready: %w", err)
	}

	tx, err := db.BeginTx(ctx, nil)
	if err != nil {
		return fmt.Errorf("begin topology migration: %w", err)
	}
	defer func() { _ = tx.Rollback() }()

	users, err := loadTopologyUsers(ctx, tx, topology)
	if err != nil {
		return err
	}
	personalCalendarIDs, err := resolvePersonalCalendars(ctx, tx, users)
	if err != nil {
		return err
	}
	householdID, err := resolveHouseholdCalendar(ctx, tx, personalCalendarIDs)
	if err != nil {
		return err
	}

	if _, err := tx.ExecContext(ctx, `
UPDATE users
SET household_role = CASE id WHEN $1 THEN 'owner' WHEN $2 THEN 'partner' END,
    google_subject = CASE id WHEN $1 THEN $3 WHEN $2 THEN $4 END,
    email_normalized = LOWER(TRIM(email))
WHERE id IN ($1, $2)`, users[0].id, users[1].id, topology.OwnerSubject, topology.PartnerSubject); err != nil {
		return fmt.Errorf("bind topology users: %w", err)
	}
	for _, calendarID := range personalCalendarIDs {
		if _, err := tx.ExecContext(ctx, `DELETE FROM calendar_members WHERE calendar_id = $1`, calendarID); err != nil {
			return fmt.Errorf("remove legacy personal calendar members for %s: %w", calendarID, err)
		}
		if _, err := tx.ExecContext(ctx, `UPDATE calendars SET kind = 'personal' WHERE id = $1`, calendarID); err != nil {
			return fmt.Errorf("preserve personal calendar %s: %w", calendarID, err)
		}
	}

	if householdID == "" {
		householdID = "cal_household"
		if _, err := tx.ExecContext(ctx, `
INSERT INTO calendars (id, owner_user_id, kind, name, color)
VALUES ($1, NULL, 'household', 'Household', '#1F6B5C')`, householdID); err != nil {
			return fmt.Errorf("create household calendar: %w", err)
		}
	} else if _, err := tx.ExecContext(ctx, `
UPDATE calendars SET kind = 'household', owner_user_id = NULL WHERE id = $1`, householdID); err != nil {
		return fmt.Errorf("designate household calendar: %w", err)
	}
	if _, err := tx.ExecContext(ctx, `
DELETE FROM calendar_members WHERE calendar_id = $1 AND user_id NOT IN ($2, $3)`, householdID, users[0].id, users[1].id); err != nil {
		return fmt.Errorf("remove legacy household members: %w", err)
	}

	for _, user := range users {
		if _, err := tx.ExecContext(ctx, `
INSERT INTO calendar_members (calendar_id, user_id, role)
VALUES ($1, $2, 'editor')
ON CONFLICT (calendar_id, user_id) DO UPDATE SET role = EXCLUDED.role`, householdID, user.id); err != nil {
			return fmt.Errorf("attach household editor %s: %w", user.id, err)
		}
	}
	if err := quarantineNonOwnerBudgets(ctx, tx, users[0].id); err != nil {
		return err
	}
	if err := tx.Commit(); err != nil {
		return fmt.Errorf("commit topology migration: %w", err)
	}
	return nil
}

func loadTopologyUsers(ctx context.Context, tx *sql.Tx, topology IdentityTopology) ([2]topologyUser, error) {
	rows, err := tx.QueryContext(ctx, `
SELECT id, email FROM users
WHERE LOWER(TRIM(email)) IN ($1, $2)
FOR UPDATE`, topology.OwnerEmail, topology.PartnerEmail)
	if err != nil {
		return [2]topologyUser{}, fmt.Errorf("load topology users: %w", err)
	}
	defer rows.Close()

	users := make(map[string]topologyUser, 2)
	for rows.Next() {
		var user topologyUser
		if err := rows.Scan(&user.id, &user.email); err != nil {
			return [2]topologyUser{}, fmt.Errorf("scan topology user: %w", err)
		}
		users[normalizeTopologyEmail(user.email)] = user
	}
	if err := rows.Err(); err != nil {
		return [2]topologyUser{}, fmt.Errorf("iterate topology users: %w", err)
	}
	owner, ownerOK := users[topology.OwnerEmail]
	partner, partnerOK := users[topology.PartnerEmail]
	if !ownerOK || !partnerOK || len(users) != 2 {
		return [2]topologyUser{}, fmt.Errorf("deployment topology requires exactly the configured owner and partner users")
	}
	return [2]topologyUser{owner, partner}, nil
}

func resolvePersonalCalendars(ctx context.Context, tx *sql.Tx, users [2]topologyUser) ([2]string, error) {
	rows, err := tx.QueryContext(ctx, `
SELECT c.id, c.owner_user_id, c.kind
FROM calendars c
WHERE c.kind IN ('personal', 'shared')
  AND c.owner_user_id IN ($1, $2)
FOR UPDATE`, users[0].id, users[1].id)
	if err != nil {
		return [2]string{}, fmt.Errorf("load personal calendars: %w", err)
	}
	defer rows.Close()
	candidates := map[string]map[string][]string{}
	for rows.Next() {
		var calendarID string
		var userID string
		var kind string
		if err := rows.Scan(&calendarID, &userID, &kind); err != nil {
			return [2]string{}, fmt.Errorf("scan personal calendar owner: %w", err)
		}
		if candidates[userID] == nil {
			candidates[userID] = map[string][]string{}
		}
		candidates[userID][kind] = append(candidates[userID][kind], calendarID)
	}
	if err := rows.Err(); err != nil {
		return [2]string{}, fmt.Errorf("iterate personal calendars: %w", err)
	}
	calendarIDs := [2]string{}
	for index, user := range users {
		personal := candidates[user.id]["personal"]
		if len(personal) == 1 {
			calendarIDs[index] = personal[0]
			continue
		}
		if len(personal) > 1 {
			return [2]string{}, fmt.Errorf("mapped user %s has ambiguous personal calendars", user.id)
		}
		shared := candidates[user.id]["shared"]
		if len(shared) != 1 {
			return [2]string{}, fmt.Errorf("mapped user %s must have exactly one personal calendar or legacy shared fallback", user.id)
		}
		calendarIDs[index] = shared[0]
	}
	return calendarIDs, nil
}

func resolveHouseholdCalendar(ctx context.Context, tx *sql.Tx, personalCalendarIDs [2]string) (string, error) {
	rows, err := tx.QueryContext(ctx, `
SELECT id FROM calendars
WHERE kind IN ('shared', 'household') AND id NOT IN ($1, $2)
FOR UPDATE`, personalCalendarIDs[0], personalCalendarIDs[1])
	if err != nil {
		return "", fmt.Errorf("load household calendar candidates: %w", err)
	}
	defer rows.Close()
	var ids []string
	for rows.Next() {
		var id string
		if err := rows.Scan(&id); err != nil {
			return "", fmt.Errorf("scan household calendar candidate: %w", err)
		}
		ids = append(ids, id)
	}
	if err := rows.Err(); err != nil {
		return "", fmt.Errorf("iterate household calendar candidates: %w", err)
	}
	if len(ids) > 1 {
		return "", fmt.Errorf("deployment topology has multiple shared calendar candidates")
	}
	if len(ids) == 1 {
		return ids[0], nil
	}
	return "", nil
}

func quarantineNonOwnerBudgets(ctx context.Context, tx *sql.Tx, ownerID string) error {
	if _, err := tx.ExecContext(ctx, `
INSERT INTO budget_quarantine (source_expense_book_id, source_owner_user_id, reason, payload)
SELECT eb.id, eb.owner_user_id, 'non_owner_budget_cutover', jsonb_build_object(
    'expense_book', to_jsonb(eb),
    'budget_months', COALESCE((SELECT jsonb_agg(
        to_jsonb(bm) || jsonb_build_object(
            'budget_item_entries', COALESCE((SELECT jsonb_agg(to_jsonb(bie)) FROM budget_item_entries bie WHERE bie.budget_month_id = bm.id), '[]'::jsonb),
            'budget_buckets', COALESCE((SELECT jsonb_agg(to_jsonb(bb)) FROM budget_buckets bb WHERE bb.budget_month_id = bm.id), '[]'::jsonb),
            'billing_reminders', COALESCE((SELECT jsonb_agg(to_jsonb(br)) FROM billing_reminders br WHERE br.budget_month_id = bm.id), '[]'::jsonb)
        )
    ) FROM budget_months bm WHERE bm.expense_book_id = eb.id), '[]'::jsonb),
    'budget_item_templates', COALESCE((SELECT jsonb_agg(to_jsonb(bit)) FROM budget_item_templates bit WHERE bit.expense_book_id = eb.id), '[]'::jsonb)
)
FROM expense_books eb
WHERE eb.owner_user_id <> $1
ON CONFLICT (source_expense_book_id) DO NOTHING`, ownerID); err != nil {
		return fmt.Errorf("quarantine non-owner budget data: %w", err)
	}
	if _, err := tx.ExecContext(ctx, `DELETE FROM expense_books WHERE owner_user_id <> $1`, ownerID); err != nil {
		return fmt.Errorf("remove quarantined non-owner budget data: %w", err)
	}
	return nil
}
