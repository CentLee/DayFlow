package app

import (
	"context"
	"regexp"
	"testing"

	"github.com/DATA-DOG/go-sqlmock"
)

func TestApplyTwoPersonTopologyRejectsInvalidConfigurationBeforeTransaction(t *testing.T) {
	db, mock, err := sqlmock.New()
	if err != nil {
		t.Fatalf("sqlmock: %v", err)
	}
	defer db.Close()

	err = applyTwoPersonTopology(context.Background(), db, IdentityTopology{
		OwnerSubject: "same-subject", OwnerEmail: "owner@example.com",
		PartnerSubject: "same-subject", PartnerEmail: "partner@example.com",
	})
	if err == nil {
		t.Fatal("expected invalid topology to block deployment readiness")
	}
	if err := mock.ExpectationsWereMet(); err != nil {
		t.Fatalf("invalid configuration must not change data: %v", err)
	}
}

func TestApplyTwoPersonTopologyRollsBackIncompleteMappedUsers(t *testing.T) {
	db, mock, err := sqlmock.New()
	if err != nil {
		t.Fatalf("sqlmock: %v", err)
	}
	defer db.Close()

	mock.ExpectBegin()
	mock.ExpectQuery(regexp.QuoteMeta(`
SELECT id, email FROM users
WHERE LOWER(TRIM(email)) IN ($1, $2)
FOR UPDATE`)).
		WithArgs("owner@example.com", "partner@example.com").
		WillReturnRows(sqlmock.NewRows([]string{"id", "email"}).AddRow("usr_owner", "owner@example.com"))
	mock.ExpectRollback()

	err = applyTwoPersonTopology(context.Background(), db, validTopology())
	if err == nil {
		t.Fatal("expected incomplete user mapping to block deployment readiness")
	}
	if err := mock.ExpectationsWereMet(); err != nil {
		t.Fatalf("incomplete mapping must leave existing data unchanged: %v", err)
	}
}

func TestApplyTwoPersonTopologyRemovesLegacyPersonalMembersAndProvisionsHousehold(t *testing.T) {
	db, mock, err := sqlmock.New()
	if err != nil {
		t.Fatalf("sqlmock: %v", err)
	}
	defer db.Close()

	mock.ExpectBegin()
	mock.ExpectQuery(regexp.QuoteMeta(`
SELECT id, email FROM users
WHERE LOWER(TRIM(email)) IN ($1, $2)
FOR UPDATE`)).
		WithArgs("owner@example.com", "partner@example.com").
		WillReturnRows(sqlmock.NewRows([]string{"id", "email"}).
			AddRow("usr_owner", "Owner@Example.com").
			AddRow("usr_partner", "partner@example.com"))
	mock.ExpectQuery(regexp.QuoteMeta(`
SELECT c.id, c.owner_user_id, c.kind
FROM calendars c
WHERE c.kind IN ('personal', 'shared')
  AND c.owner_user_id IN ($1, $2)
FOR UPDATE`)).
		WithArgs("usr_owner", "usr_partner").
		WillReturnRows(sqlmock.NewRows([]string{"id", "owner_user_id", "kind"}).
			AddRow("cal_owner_personal", "usr_owner", "personal").
			AddRow("cal_partner_personal", "usr_partner", "personal"))
	mock.ExpectQuery(regexp.QuoteMeta(`
	SELECT id FROM calendars
WHERE kind IN ('shared', 'household') AND id NOT IN ($1, $2)
FOR UPDATE`)).
		WithArgs("cal_owner_personal", "cal_partner_personal").
		WillReturnRows(sqlmock.NewRows([]string{"id"}).AddRow("cal_shared"))
	mock.ExpectExec("UPDATE users").
		WithArgs("usr_owner", "usr_partner", "google-owner", "google-partner").
		WillReturnResult(sqlmock.NewResult(0, 2))
	mock.ExpectExec(regexp.QuoteMeta(`DELETE FROM calendar_members WHERE calendar_id = $1`)).
		WithArgs("cal_owner_personal").WillReturnResult(sqlmock.NewResult(0, 1))
	mock.ExpectExec("UPDATE calendars SET kind = 'personal' WHERE id = .1").
		WithArgs("cal_owner_personal").WillReturnResult(sqlmock.NewResult(0, 1))
	mock.ExpectExec(regexp.QuoteMeta(`DELETE FROM calendar_members WHERE calendar_id = $1`)).
		WithArgs("cal_partner_personal").WillReturnResult(sqlmock.NewResult(0, 1))
	mock.ExpectExec("UPDATE calendars SET kind = 'personal' WHERE id = .1").
		WithArgs("cal_partner_personal").WillReturnResult(sqlmock.NewResult(0, 1))
	mock.ExpectExec("UPDATE calendars SET kind = 'household', owner_user_id = NULL WHERE id = .1").
		WithArgs("cal_shared").WillReturnResult(sqlmock.NewResult(0, 1))
	mock.ExpectExec(regexp.QuoteMeta(`DELETE FROM calendar_members WHERE calendar_id = $1 AND user_id NOT IN ($2, $3)`)).
		WithArgs("cal_shared", "usr_owner", "usr_partner").WillReturnResult(sqlmock.NewResult(0, 0))
	mock.ExpectExec("INSERT INTO calendar_members").
		WithArgs("cal_shared", "usr_owner").WillReturnResult(sqlmock.NewResult(0, 1))
	mock.ExpectExec("INSERT INTO calendar_members").
		WithArgs("cal_shared", "usr_partner").WillReturnResult(sqlmock.NewResult(0, 1))
	mock.ExpectExec("INSERT INTO budget_quarantine").
		WithArgs("usr_owner").WillReturnResult(sqlmock.NewResult(0, 0))
	mock.ExpectExec("DELETE FROM expense_books WHERE owner_user_id <> .1").
		WithArgs("usr_owner").WillReturnResult(sqlmock.NewResult(0, 1))
	mock.ExpectCommit()

	if err := applyTwoPersonTopology(context.Background(), db, validTopology()); err != nil {
		t.Fatalf("apply topology: %v", err)
	}
	if err := mock.ExpectationsWereMet(); err != nil {
		t.Fatalf("topology migration expectations: %v", err)
	}
}

func TestResolvePersonalCalendarsSelectsLegacyCalendarsWithStaleMembers(t *testing.T) {
	db, mock, err := sqlmock.New()
	if err != nil {
		t.Fatalf("sqlmock: %v", err)
	}
	defer db.Close()

	mock.ExpectBegin()
	tx, err := db.BeginTx(context.Background(), nil)
	if err != nil {
		t.Fatalf("begin transaction: %v", err)
	}
	mock.ExpectQuery(regexp.QuoteMeta(`
SELECT c.id, c.owner_user_id, c.kind
FROM calendars c
WHERE c.kind IN ('personal', 'shared')
  AND c.owner_user_id IN ($1, $2)
FOR UPDATE`)).
		WithArgs("usr_owner", "usr_partner").
		WillReturnRows(sqlmock.NewRows([]string{"id", "owner_user_id", "kind"}).
			AddRow("cal_owner_legacy", "usr_owner", "shared").
			AddRow("cal_partner_legacy", "usr_partner", "shared"))
	mock.ExpectRollback()

	calendarIDs, err := resolvePersonalCalendars(context.Background(), tx, [2]topologyUser{
		{id: "usr_owner"},
		{id: "usr_partner"},
	})
	if err != nil {
		t.Fatalf("resolve legacy personal calendars: %v", err)
	}
	if calendarIDs != [2]string{"cal_owner_legacy", "cal_partner_legacy"} {
		t.Fatalf("legacy calendar IDs = %v, want owner and partner legacy calendars", calendarIDs)
	}
	if err := tx.Rollback(); err != nil {
		t.Fatalf("rollback transaction: %v", err)
	}
	if err := mock.ExpectationsWereMet(); err != nil {
		t.Fatalf("legacy members must not exclude owned calendars: %v", err)
	}
}

func TestResolvePersonalCalendarsPrefersPersonalOverOwnedSharedCalendar(t *testing.T) {
	db, mock, err := sqlmock.New()
	if err != nil {
		t.Fatalf("sqlmock: %v", err)
	}
	defer db.Close()

	mock.ExpectBegin()
	tx, err := db.BeginTx(context.Background(), nil)
	if err != nil {
		t.Fatalf("begin transaction: %v", err)
	}
	mock.ExpectQuery(regexp.QuoteMeta(`
SELECT c.id, c.owner_user_id, c.kind
FROM calendars c
WHERE c.kind IN ('personal', 'shared')
  AND c.owner_user_id IN ($1, $2)
FOR UPDATE`)).
		WithArgs("usr_owner", "usr_partner").
		WillReturnRows(sqlmock.NewRows([]string{"id", "owner_user_id", "kind"}).
			AddRow("cal_owner_personal", "usr_owner", "personal").
			AddRow("cal_owner_shared", "usr_owner", "shared").
			AddRow("cal_partner_personal", "usr_partner", "personal"))
	mock.ExpectRollback()

	calendarIDs, err := resolvePersonalCalendars(context.Background(), tx, [2]topologyUser{
		{id: "usr_owner"},
		{id: "usr_partner"},
	})
	if err != nil {
		t.Fatalf("resolve personal calendars: %v", err)
	}
	if calendarIDs != [2]string{"cal_owner_personal", "cal_partner_personal"} {
		t.Fatalf("calendar IDs = %v, want personal calendars", calendarIDs)
	}
	if err := tx.Rollback(); err != nil {
		t.Fatalf("rollback transaction: %v", err)
	}
	if err := mock.ExpectationsWereMet(); err != nil {
		t.Fatalf("personal calendar must win over owned shared calendar: %v", err)
	}
}

func TestResolvePersonalCalendarsRejectsAmbiguousLegacySharedFallback(t *testing.T) {
	db, mock, err := sqlmock.New()
	if err != nil {
		t.Fatalf("sqlmock: %v", err)
	}
	defer db.Close()

	mock.ExpectBegin()
	tx, err := db.BeginTx(context.Background(), nil)
	if err != nil {
		t.Fatalf("begin transaction: %v", err)
	}
	mock.ExpectQuery(regexp.QuoteMeta(`
SELECT c.id, c.owner_user_id, c.kind
FROM calendars c
WHERE c.kind IN ('personal', 'shared')
  AND c.owner_user_id IN ($1, $2)
FOR UPDATE`)).
		WithArgs("usr_owner", "usr_partner").
		WillReturnRows(sqlmock.NewRows([]string{"id", "owner_user_id", "kind"}).
			AddRow("cal_owner_legacy_a", "usr_owner", "shared").
			AddRow("cal_owner_legacy_b", "usr_owner", "shared").
			AddRow("cal_partner_legacy", "usr_partner", "shared"))
	mock.ExpectRollback()

	_, err = resolvePersonalCalendars(context.Background(), tx, [2]topologyUser{
		{id: "usr_owner"},
		{id: "usr_partner"},
	})
	if err == nil {
		t.Fatal("expected ambiguous legacy shared calendars to be rejected")
	}
	if err := tx.Rollback(); err != nil {
		t.Fatalf("rollback transaction: %v", err)
	}
	if err := mock.ExpectationsWereMet(); err != nil {
		t.Fatalf("ambiguous legacy calendars must not be selected: %v", err)
	}
}

func validTopology() IdentityTopology {
	return IdentityTopology{
		OwnerSubject: "google-owner", OwnerEmail: "Owner@Example.com",
		PartnerSubject: "google-partner", PartnerEmail: "partner@example.com",
	}
}
