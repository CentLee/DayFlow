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

func TestApplyTwoPersonTopologyPreservesMappedUsersAndProvisionsHousehold(t *testing.T) {
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
SELECT owner_user_id
FROM calendars
WHERE kind = 'personal' AND owner_user_id IN ($1, $2)
FOR UPDATE`)).
		WithArgs("usr_owner", "usr_partner").
		WillReturnRows(sqlmock.NewRows([]string{"owner_user_id"}).AddRow("usr_owner").AddRow("usr_partner"))
	mock.ExpectQuery(regexp.QuoteMeta(`
SELECT id FROM calendars WHERE kind IN ('shared', 'household') FOR UPDATE`)).
		WillReturnRows(sqlmock.NewRows([]string{"id"}).AddRow("cal_shared"))
	mock.ExpectExec("UPDATE users").
		WithArgs("usr_owner", "usr_partner", "google-owner", "google-partner").
		WillReturnResult(sqlmock.NewResult(0, 2))
	mock.ExpectExec("UPDATE calendars SET kind = 'household', owner_user_id = NULL WHERE id = .1").
		WithArgs("cal_shared").WillReturnResult(sqlmock.NewResult(0, 1))
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

func validTopology() IdentityTopology {
	return IdentityTopology{
		OwnerSubject: "google-owner", OwnerEmail: "Owner@Example.com",
		PartnerSubject: "google-partner", PartnerEmail: "partner@example.com",
	}
}
