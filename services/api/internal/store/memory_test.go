package store

import (
	"errors"
	"testing"
	"time"
)

func TestMemoryStoreCalendarPermissions(t *testing.T) {
	repo := NewMemoryStore()

	calendars := repo.ListCalendars("usr_002")
	if len(calendars) != 1 || calendars[0].ID != "cal_002" {
		t.Fatalf("expected editor to see only shared calendar, got %#v", calendars)
	}

	_, err := repo.UpdateCalendar("usr_002", "cal_002", CalendarPatch{Name: stringPtr("Blocked")})
	if !errors.Is(err, ErrForbidden) {
		t.Fatalf("expected forbidden updating calendar as editor, got %v", err)
	}

	created, err := repo.CreateCalendar("usr_001", CalendarInput{Name: "Work", Color: "#112233"})
	if err != nil {
		t.Fatalf("create calendar: %v", err)
	}
	if created.Role != RoleOwner {
		t.Fatalf("expected owner role, got %s", created.Role)
	}

	if err := repo.DeleteCalendar("usr_001", created.ID); err != nil {
		t.Fatalf("delete calendar: %v", err)
	}
	if _, err := repo.UpdateCalendar("usr_001", created.ID, CalendarPatch{Name: stringPtr("Gone")}); !errors.Is(err, ErrNotFound) {
		t.Fatalf("expected not found after delete, got %v", err)
	}
}

func TestMemoryStoreEventCRUDAndFiltering(t *testing.T) {
	repo := NewMemoryStore()
	start := time.Date(2026, 3, 17, 9, 0, 0, 0, time.UTC)
	end := start.Add(2 * time.Hour)

	event, err := repo.CreateEvent("usr_002", "cal_002", EventInput{
		Title:    "Editor Event",
		Notes:    "shared calendar",
		StartsAt: start,
		EndsAt:   end,
		AllDay:   false,
	})
	if err != nil {
		t.Fatalf("create event: %v", err)
	}

	if _, err := repo.CreateEvent("usr_003", "cal_002", EventInput{
		Title:    "Viewer Event",
		StartsAt: start,
		EndsAt:   end,
	}); !errors.Is(err, ErrForbidden) {
		t.Fatalf("expected forbidden creating as viewer, got %v", err)
	}

	from := start.Add(-1 * time.Minute)
	to := start.Add(1 * time.Minute)
	filtered, err := repo.ListEvents("usr_003", "cal_002", &from, &to)
	if err != nil {
		t.Fatalf("list filtered events: %v", err)
	}
	found := false
	for _, item := range filtered {
		if item.ID == event.ID {
			found = true
		}
	}
	if !found {
		t.Fatalf("expected filtered result to contain created event %#v", filtered)
	}

	longEvent, err := repo.CreateEvent("usr_002", "cal_002", EventInput{
		Title:    "Two Day Event",
		Notes:    "overlap should count",
		StartsAt: start,
		EndsAt:   start.Add(48 * time.Hour),
		AllDay:   false,
	})
	if err != nil {
		t.Fatalf("create overlapping event: %v", err)
	}

	overlapFrom := start.Add(24 * time.Hour)
	overlapTo := overlapFrom.Add(30 * time.Minute)
	overlapping, err := repo.ListEvents("usr_003", "cal_002", &overlapFrom, &overlapTo)
	if err != nil {
		t.Fatalf("list overlapping events: %v", err)
	}
	overlapFound := false
	for _, item := range overlapping {
		if item.ID == longEvent.ID {
			overlapFound = true
		}
	}
	if !overlapFound {
		t.Fatalf("expected overlap window to include long-running event %#v", overlapping)
	}

	allDay := true
	updated, err := repo.UpdateEvent("usr_001", event.ID, EventPatch{AllDay: &allDay, Title: stringPtr("Updated Event")})
	if err != nil {
		t.Fatalf("update event: %v", err)
	}
	if !updated.AllDay || updated.Title != "Updated Event" {
		t.Fatalf("expected updated event, got %#v", updated)
	}

	if err := repo.DeleteEvent("usr_002", event.ID); err != nil {
		t.Fatalf("delete event: %v", err)
	}
	if err := repo.DeleteEvent("usr_002", event.ID); !errors.Is(err, ErrNotFound) {
		t.Fatalf("expected not found deleting twice, got %v", err)
	}
	if _, err := repo.ListEvents("usr_004", "cal_002", nil, nil); !errors.Is(err, ErrForbidden) {
		t.Fatalf("expected outsider access to be forbidden, got %v", err)
	}
}

func stringPtr(value string) *string {
	return &value
}
