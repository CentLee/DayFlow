package httpapi

import (
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"

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
	router := NewRouter(store.NewMemoryStore())
	loginReq := httptest.NewRequest(http.MethodPost, "/v1/auth/login", strings.NewReader(`{"email":"owner@dayflow.local","password":"secret1234"}`))
	loginReq.Header.Set("Content-Type", "application/json")
	loginRec := httptest.NewRecorder()
	router.ServeHTTP(loginRec, loginReq)
	if loginRec.Code != http.StatusOK {
		t.Fatalf("expected login 200, got %d", loginRec.Code)
	}

	var loginPayload struct {
		Token string `json:"token"`
	}
	decodeResponse(t, loginRec, &loginPayload)

	meReq := httptest.NewRequest(http.MethodGet, "/v1/me", nil)
	meReq.Header.Set("Authorization", "Bearer "+loginPayload.Token)
	meRec := httptest.NewRecorder()
	router.ServeHTTP(meRec, meReq)

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

func decodeResponse(t *testing.T, rec *httptest.ResponseRecorder, target any) {
	t.Helper()
	if err := json.Unmarshal(rec.Body.Bytes(), target); err != nil {
		t.Fatalf("failed to decode response: %v", err)
	}
}
