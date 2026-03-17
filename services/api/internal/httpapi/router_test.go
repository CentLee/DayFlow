package httpapi

import (
	"bytes"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"strings"
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

func TestRegisterSuccess(t *testing.T) {
	body := `{"email":"user@example.com","display_name":"Kakao","password":"secret1234","invite_code":"invite_abc"}`
	req := httptest.NewRequest(http.MethodPost, "/v1/auth/register", strings.NewReader(body))
	req.Header.Set("Content-Type", "application/json")
	rec := httptest.NewRecorder()

	NewRouter(store.NewMemoryStore()).ServeHTTP(rec, req)

	if rec.Code != http.StatusCreated {
		t.Fatalf("expected 201, got %d", rec.Code)
	}

	var payload struct {
		User struct {
			Email       string `json:"email"`
			DisplayName string `json:"display_name"`
		} `json:"user"`
		Token string `json:"token"`
	}
	decodeResponse(t, rec, &payload)
	if payload.User.Email != "user@example.com" {
		t.Fatalf("expected registered email, got %q", payload.User.Email)
	}
	if payload.User.DisplayName != "Kakao" {
		t.Fatalf("expected display name Kakao, got %q", payload.User.DisplayName)
	}
	if payload.Token == "" {
		t.Fatal("expected token in register response")
	}
}

func TestRegisterRejectsInvalidInvite(t *testing.T) {
	body := `{"email":"user@example.com","display_name":"Kakao","password":"secret1234","invite_code":"wrong"}`
	req := httptest.NewRequest(http.MethodPost, "/v1/auth/register", strings.NewReader(body))
	req.Header.Set("Content-Type", "application/json")
	rec := httptest.NewRecorder()

	NewRouter(store.NewMemoryStore()).ServeHTTP(rec, req)

	if rec.Code != http.StatusForbidden {
		t.Fatalf("expected 403, got %d", rec.Code)
	}
}

func TestLoginSuccess(t *testing.T) {
	body := `{"email":"owner@dayflow.local","password":"secret1234"}`
	req := httptest.NewRequest(http.MethodPost, "/v1/auth/login", strings.NewReader(body))
	req.Header.Set("Content-Type", "application/json")
	rec := httptest.NewRecorder()

	NewRouter(store.NewMemoryStore()).ServeHTTP(rec, req)

	if rec.Code != http.StatusOK {
		t.Fatalf("expected 200, got %d", rec.Code)
	}

	var payload struct {
		User struct {
			Email string `json:"email"`
		} `json:"user"`
		Token string `json:"token"`
	}
	decodeResponse(t, rec, &payload)
	if payload.User.Email != "owner@dayflow.local" {
		t.Fatalf("expected owner email, got %q", payload.User.Email)
	}
	if payload.Token == "" {
		t.Fatal("expected token in login response")
	}
}

func TestLoginRejectsWrongPassword(t *testing.T) {
	body := `{"email":"owner@dayflow.local","password":"bad-password"}`
	req := httptest.NewRequest(http.MethodPost, "/v1/auth/login", strings.NewReader(body))
	req.Header.Set("Content-Type", "application/json")
	rec := httptest.NewRecorder()

	NewRouter(store.NewMemoryStore()).ServeHTTP(rec, req)

	if rec.Code != http.StatusUnauthorized {
		t.Fatalf("expected 401, got %d", rec.Code)
	}
}

func TestMeRequiresAuthentication(t *testing.T) {
	req := httptest.NewRequest(http.MethodGet, "/v1/me", nil)
	rec := httptest.NewRecorder()

	NewRouter(store.NewMemoryStore()).ServeHTTP(rec, req)

	if rec.Code != http.StatusUnauthorized {
		t.Fatalf("expected 401, got %d", rec.Code)
	}
}

func TestMeReturnsAuthenticatedUser(t *testing.T) {
	handler := NewRouter(store.NewMemoryStore())
	token := loginTokenForUser(t, handler, "owner@dayflow.local", "secret1234")

	meReq := httptest.NewRequest(http.MethodGet, "/v1/me", nil)
	meReq.Header.Set("Authorization", "Bearer "+token)
	meRec := httptest.NewRecorder()
	handler.ServeHTTP(meRec, meReq)

	if meRec.Code != http.StatusOK {
		t.Fatalf("expected me 200, got %d", meRec.Code)
	}

	var payload struct {
		User struct {
			Email string `json:"email"`
		} `json:"user"`
		OwnedCalendars        []map[string]any `json:"owned_calendars"`
		SharedCalendars       []map[string]any `json:"shared_calendars"`
		CurrentBudgetMonthKey string           `json:"current_budget_month_key"`
	}
	decodeResponse(t, meRec, &payload)
	if payload.User.Email != "owner@dayflow.local" {
		t.Fatalf("expected authenticated owner, got %q", payload.User.Email)
	}
	if len(payload.OwnedCalendars) == 0 {
		t.Fatal("expected owned calendars in me response")
	}
	if payload.CurrentBudgetMonthKey == "" {
		t.Fatal("expected current budget month key")
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
	ownerToken := loginTokenForUser(t, handler, "owner@dayflow.local", "secret1234")

	createRec := performAuthedJSONRequest(t, handler, ownerToken, http.MethodPost, "/v1/calendars", map[string]any{
		"name":  "Project Planning",
		"color": "#123ABC",
	})
	if createRec.Code != http.StatusCreated {
		t.Fatalf("expected 201, got %d body=%s", createRec.Code, createRec.Body.String())
	}

	var createBody struct {
		Calendar map[string]any `json:"calendar"`
	}
	decodeResponse(t, createRec, &createBody)
	calendarID, _ := createBody.Calendar["id"].(string)
	if calendarID == "" {
		t.Fatal("expected calendar id in create response")
	}

	listRec := performAuthedJSONRequest(t, handler, ownerToken, http.MethodGet, "/v1/calendars", nil)
	if listRec.Code != http.StatusOK {
		t.Fatalf("expected 200, got %d", listRec.Code)
	}

	patchRec := performAuthedJSONRequest(t, handler, ownerToken, http.MethodPatch, "/v1/calendars/"+calendarID, map[string]any{
		"name":  "Updated Planning",
		"color": "#654321",
	})
	if patchRec.Code != http.StatusOK {
		t.Fatalf("expected 200, got %d body=%s", patchRec.Code, patchRec.Body.String())
	}

	deleteReq := httptest.NewRequest(http.MethodDelete, "/v1/calendars/"+calendarID, nil)
	deleteReq.Header.Set("Authorization", "Bearer "+ownerToken)
	deleteRec := httptest.NewRecorder()
	handler.ServeHTTP(deleteRec, deleteReq)
	if deleteRec.Code != http.StatusNoContent {
		t.Fatalf("expected 204, got %d body=%s", deleteRec.Code, deleteRec.Body.String())
	}

	listAfterDelete := performAuthedJSONRequest(t, handler, ownerToken, http.MethodGet, "/v1/calendars", nil)
	if bytes.Contains(listAfterDelete.Body.Bytes(), []byte(calendarID)) {
		t.Fatalf("expected calendar %s to be removed", calendarID)
	}
}

func TestCalendarAccessBoundaries(t *testing.T) {
	handler := NewRouter(store.NewMemoryStore())
	editorToken := loginTokenForUser(t, handler, "editor@dayflow.local", "secret1234")
	outsiderToken := loginTokenForUser(t, handler, "outside@dayflow.local", "secret1234")

	editorList := performAuthedJSONRequest(t, handler, editorToken, http.MethodGet, "/v1/calendars", nil)
	if editorList.Code != http.StatusOK {
		t.Fatalf("expected 200, got %d", editorList.Code)
	}
	if !bytes.Contains(editorList.Body.Bytes(), []byte("cal_002")) {
		t.Fatalf("expected shared calendar in response: %s", editorList.Body.String())
	}
	if bytes.Contains(editorList.Body.Bytes(), []byte("cal_001")) {
		t.Fatalf("did not expect personal calendar in response: %s", editorList.Body.String())
	}

	forbiddenPatch := performAuthedJSONRequest(t, handler, editorToken, http.MethodPatch, "/v1/calendars/cal_002", map[string]any{"name": "Nope"})
	if forbiddenPatch.Code != http.StatusForbidden {
		t.Fatalf("expected 403, got %d body=%s", forbiddenPatch.Code, forbiddenPatch.Body.String())
	}

	outsiderList := performAuthedJSONRequest(t, handler, outsiderToken, http.MethodGet, "/v1/calendars", nil)
	if outsiderList.Code != http.StatusOK {
		t.Fatalf("expected 200, got %d", outsiderList.Code)
	}
	if bytes.Contains(outsiderList.Body.Bytes(), []byte("cal_002")) {
		t.Fatalf("outsider should not see shared calendar: %s", outsiderList.Body.String())
	}
}

func TestEventCRUDAndPermissionBoundaries(t *testing.T) {
	handler := NewRouter(store.NewMemoryStore())
	editorToken := loginTokenForUser(t, handler, "editor@dayflow.local", "secret1234")
	viewerToken := loginTokenForUser(t, handler, "viewer@dayflow.local", "secret1234")
	outsiderToken := loginTokenForUser(t, handler, "outside@dayflow.local", "secret1234")
	start := time.Date(2026, 3, 17, 9, 0, 0, 0, time.UTC)
	end := start.Add(1 * time.Hour)

	createRec := performAuthedJSONRequest(t, handler, editorToken, http.MethodPost, "/v1/calendars/cal_002/events", map[string]any{
		"title":     "Shared planning",
		"notes":     "editor can create",
		"starts_at": start.Format(time.RFC3339),
		"ends_at":   end.Format(time.RFC3339),
		"all_day":   false,
	})
	if createRec.Code != http.StatusCreated {
		t.Fatalf("expected 201, got %d body=%s", createRec.Code, createRec.Body.String())
	}

	var createBody struct {
		Event map[string]any `json:"event"`
	}
	decodeResponse(t, createRec, &createBody)
	eventID, _ := createBody.Event["id"].(string)
	if eventID == "" {
		t.Fatal("expected event id in create response")
	}

	viewerList := performAuthedJSONRequest(t, handler, viewerToken, http.MethodGet, "/v1/calendars/cal_002/events", nil)
	if viewerList.Code != http.StatusOK {
		t.Fatalf("expected 200, got %d body=%s", viewerList.Code, viewerList.Body.String())
	}
	if !bytes.Contains(viewerList.Body.Bytes(), []byte(eventID)) {
		t.Fatalf("expected created event in viewer response: %s", viewerList.Body.String())
	}

	viewerCreate := performAuthedJSONRequest(t, handler, viewerToken, http.MethodPost, "/v1/calendars/cal_002/events", map[string]any{
		"title":     "Should fail",
		"notes":     "viewer cannot create",
		"starts_at": start.Format(time.RFC3339),
		"ends_at":   end.Format(time.RFC3339),
		"all_day":   false,
	})
	if viewerCreate.Code != http.StatusForbidden {
		t.Fatalf("expected 403, got %d body=%s", viewerCreate.Code, viewerCreate.Body.String())
	}

	outsiderGet := performAuthedJSONRequest(t, handler, outsiderToken, http.MethodGet, "/v1/calendars/cal_002/events", nil)
	if outsiderGet.Code != http.StatusForbidden {
		t.Fatalf("expected 403, got %d body=%s", outsiderGet.Code, outsiderGet.Body.String())
	}

	patchRec := performAuthedJSONRequest(t, handler, editorToken, http.MethodPatch, "/v1/events/"+eventID, map[string]any{
		"title": "Updated shared planning",
	})
	if patchRec.Code != http.StatusOK {
		t.Fatalf("expected 200, got %d body=%s", patchRec.Code, patchRec.Body.String())
	}

	deleteReq := httptest.NewRequest(http.MethodDelete, "/v1/events/"+eventID, nil)
	deleteReq.Header.Set("Authorization", "Bearer "+editorToken)
	deleteRec := httptest.NewRecorder()
	handler.ServeHTTP(deleteRec, deleteReq)
	if deleteRec.Code != http.StatusNoContent {
		t.Fatalf("expected 204, got %d body=%s", deleteRec.Code, deleteRec.Body.String())
	}
}

func performAuthedJSONRequest(t *testing.T, handler http.Handler, token, method, path string, payload any) *httptest.ResponseRecorder {
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
	req.Header.Set("Authorization", "Bearer "+token)
	rec := httptest.NewRecorder()
	handler.ServeHTTP(rec, req)
	return rec
}

func loginTokenForUser(t *testing.T, handler http.Handler, email, password string) string {
	t.Helper()

	body := `{"email":"` + email + `","password":"` + password + `"}`
	req := httptest.NewRequest(http.MethodPost, "/v1/auth/login", strings.NewReader(body))
	req.Header.Set("Content-Type", "application/json")
	rec := httptest.NewRecorder()
	handler.ServeHTTP(rec, req)
	if rec.Code != http.StatusOK {
		t.Fatalf("expected login 200, got %d body=%s", rec.Code, rec.Body.String())
	}

	var payload struct {
		Token string `json:"token"`
	}
	decodeResponse(t, rec, &payload)
	if payload.Token == "" {
		t.Fatal("expected login token")
	}
	return payload.Token
}

func decodeResponse(t *testing.T, rec *httptest.ResponseRecorder, target any) {
	t.Helper()
	if err := json.Unmarshal(rec.Body.Bytes(), target); err != nil {
		t.Fatalf("failed to decode response: %v", err)
	}
}
