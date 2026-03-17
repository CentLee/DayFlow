package httpapi

import (
	"bytes"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"testing"
	"time"

	"github.com/kakao-ent/dayflow/services/api/internal/store"
)

func TestHealthz(t *testing.T) {
	req := httptest.NewRequest(http.MethodGet, "/healthz", nil)
	rec := httptest.NewRecorder()

	NewRouter(store.NewMemoryStore()).ServeHTTP(rec, req)

	if rec.Code != http.StatusOK {
		t.Fatalf("expected 200, got %d", rec.Code)
	}
}

func TestBudgetMonth(t *testing.T) {
	req := httptest.NewRequest(http.MethodGet, "/v1/budget/months/2026-03", nil)
	rec := httptest.NewRecorder()

	NewRouter(store.NewMemoryStore()).ServeHTTP(rec, req)

	if rec.Code != http.StatusOK {
		t.Fatalf("expected 200, got %d", rec.Code)
	}
}

func TestCalendarCRUDFlow(t *testing.T) {
	handler := NewRouter(store.NewMemoryStore())

	createRec := performJSONRequest(t, handler, http.MethodPost, "/v1/calendars", map[string]any{
		"name":  "Project Planning",
		"color": "#123ABC",
	}, "usr_001")
	if createRec.Code != http.StatusCreated {
		t.Fatalf("expected 201, got %d body=%s", createRec.Code, createRec.Body.String())
	}

	var createBody struct {
		Calendar map[string]any `json:"calendar"`
	}
	if err := json.Unmarshal(createRec.Body.Bytes(), &createBody); err != nil {
		t.Fatalf("unmarshal create response: %v", err)
	}
	calendarID, _ := createBody.Calendar["id"].(string)
	if calendarID == "" {
		t.Fatal("expected calendar id in create response")
	}

	listRec := performJSONRequest(t, handler, http.MethodGet, "/v1/calendars", nil, "usr_001")
	if listRec.Code != http.StatusOK {
		t.Fatalf("expected 200, got %d", listRec.Code)
	}

	patchRec := performJSONRequest(t, handler, http.MethodPatch, "/v1/calendars/"+calendarID, map[string]any{
		"name":  "Updated Planning",
		"color": "#654321",
	}, "usr_001")
	if patchRec.Code != http.StatusOK {
		t.Fatalf("expected 200, got %d body=%s", patchRec.Code, patchRec.Body.String())
	}

	deleteReq := httptest.NewRequest(http.MethodDelete, "/v1/calendars/"+calendarID, nil)
	deleteReq.Header.Set("X-DayFlow-User-ID", "usr_001")
	deleteRec := httptest.NewRecorder()
	handler.ServeHTTP(deleteRec, deleteReq)
	if deleteRec.Code != http.StatusNoContent {
		t.Fatalf("expected 204, got %d body=%s", deleteRec.Code, deleteRec.Body.String())
	}

	listAfterDelete := performJSONRequest(t, handler, http.MethodGet, "/v1/calendars", nil, "usr_001")
	if bytes.Contains(listAfterDelete.Body.Bytes(), []byte(calendarID)) {
		t.Fatalf("expected calendar %s to be removed", calendarID)
	}
}

func TestCalendarAccessBoundaries(t *testing.T) {
	handler := NewRouter(store.NewMemoryStore())

	editorList := performJSONRequest(t, handler, http.MethodGet, "/v1/calendars", nil, "usr_002")
	if editorList.Code != http.StatusOK {
		t.Fatalf("expected 200, got %d", editorList.Code)
	}
	if !bytes.Contains(editorList.Body.Bytes(), []byte("cal_002")) {
		t.Fatalf("expected shared calendar in response: %s", editorList.Body.String())
	}
	if bytes.Contains(editorList.Body.Bytes(), []byte("cal_001")) {
		t.Fatalf("did not expect personal calendar in response: %s", editorList.Body.String())
	}

	forbiddenPatch := performJSONRequest(t, handler, http.MethodPatch, "/v1/calendars/cal_002", map[string]any{"name": "Nope"}, "usr_002")
	if forbiddenPatch.Code != http.StatusForbidden {
		t.Fatalf("expected 403, got %d body=%s", forbiddenPatch.Code, forbiddenPatch.Body.String())
	}

	outsiderList := performJSONRequest(t, handler, http.MethodGet, "/v1/calendars", nil, "usr_004")
	if outsiderList.Code != http.StatusOK {
		t.Fatalf("expected 200, got %d", outsiderList.Code)
	}
	if bytes.Contains(outsiderList.Body.Bytes(), []byte("cal_002")) {
		t.Fatalf("outsider should not see shared calendar: %s", outsiderList.Body.String())
	}
}

func TestEventCRUDAndPermissionBoundaries(t *testing.T) {
	handler := NewRouter(store.NewMemoryStore())
	start := time.Date(2026, 3, 17, 9, 0, 0, 0, time.UTC)
	end := start.Add(1 * time.Hour)

	createRec := performJSONRequest(t, handler, http.MethodPost, "/v1/calendars/cal_002/events", map[string]any{
		"title":     "Shared planning",
		"notes":     "editor can create",
		"starts_at": start.Format(time.RFC3339),
		"ends_at":   end.Format(time.RFC3339),
		"all_day":   false,
	}, "usr_002")
	if createRec.Code != http.StatusCreated {
		t.Fatalf("expected 201, got %d body=%s", createRec.Code, createRec.Body.String())
	}

	var createBody struct {
		Event map[string]any `json:"event"`
	}
	if err := json.Unmarshal(createRec.Body.Bytes(), &createBody); err != nil {
		t.Fatalf("unmarshal event create response: %v", err)
	}
	eventID, _ := createBody.Event["id"].(string)
	if eventID == "" {
		t.Fatal("expected event id in create response")
	}

	viewerList := performJSONRequest(t, handler, http.MethodGet, "/v1/calendars/cal_002/events", nil, "usr_003")
	if viewerList.Code != http.StatusOK {
		t.Fatalf("expected 200, got %d body=%s", viewerList.Code, viewerList.Body.String())
	}
	if !bytes.Contains(viewerList.Body.Bytes(), []byte(eventID)) {
		t.Fatalf("expected created event in viewer response: %s", viewerList.Body.String())
	}

	viewerCreate := performJSONRequest(t, handler, http.MethodPost, "/v1/calendars/cal_002/events", map[string]any{
		"title":     "Should fail",
		"notes":     "viewer cannot create",
		"starts_at": start.Format(time.RFC3339),
		"ends_at":   end.Format(time.RFC3339),
		"all_day":   false,
	}, "usr_003")
	if viewerCreate.Code != http.StatusForbidden {
		t.Fatalf("expected 403, got %d body=%s", viewerCreate.Code, viewerCreate.Body.String())
	}

	outsiderGet := performJSONRequest(t, handler, http.MethodGet, "/v1/calendars/cal_002/events", nil, "usr_004")
	if outsiderGet.Code != http.StatusForbidden {
		t.Fatalf("expected 403, got %d body=%s", outsiderGet.Code, outsiderGet.Body.String())
	}

	patchRec := performJSONRequest(t, handler, http.MethodPatch, "/v1/events/"+eventID, map[string]any{
		"title": "Updated shared planning",
	}, "usr_002")
	if patchRec.Code != http.StatusOK {
		t.Fatalf("expected 200, got %d body=%s", patchRec.Code, patchRec.Body.String())
	}

	deleteReq := httptest.NewRequest(http.MethodDelete, "/v1/events/"+eventID, nil)
	deleteReq.Header.Set("X-DayFlow-User-ID", "usr_002")
	deleteRec := httptest.NewRecorder()
	handler.ServeHTTP(deleteRec, deleteReq)
	if deleteRec.Code != http.StatusNoContent {
		t.Fatalf("expected 204, got %d body=%s", deleteRec.Code, deleteRec.Body.String())
	}
}

func performJSONRequest(t *testing.T, handler http.Handler, method, path string, payload any, userID string) *httptest.ResponseRecorder {
	t.Helper()

	var body *bytes.Reader
	if payload == nil {
		body = bytes.NewReader(nil)
	} else {
		encoded, err := json.Marshal(payload)
		if err != nil {
			t.Fatalf("marshal payload: %v", err)
		}
		body = bytes.NewReader(encoded)
	}
	req := httptest.NewRequest(method, path, body)
	if payload != nil {
		req.Header.Set("Content-Type", "application/json")
	}
	if userID != "" {
		req.Header.Set("X-DayFlow-User-ID", userID)
	}
	rec := httptest.NewRecorder()
	handler.ServeHTTP(rec, req)
	return rec
}
