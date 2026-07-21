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
	handler := NewRouter(store.NewMemoryStore())
	body := `{"email":"user@example.com","display_name":"Kakao","password":"secret1234","invite_code":"invite_abc"}`
	req := httptest.NewRequest(http.MethodPost, "/v1/auth/register", strings.NewReader(body))
	req.Header.Set("Content-Type", "application/json")
	rec := httptest.NewRecorder()

	handler.ServeHTTP(rec, req)

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

	meRec := performAuthedJSONRequest(t, handler, payload.Token, http.MethodGet, "/v1/me", nil)
	if meRec.Code != http.StatusOK {
		t.Fatalf("expected 200 from /me, got %d body=%s", meRec.Code, meRec.Body.String())
	}
	if !bytes.Contains(meRec.Body.Bytes(), []byte(`"shared_calendars"`)) || !bytes.Contains(meRec.Body.Bytes(), []byte(`"cal_002"`)) {
		t.Fatalf("expected invite registration to create shared membership: %s", meRec.Body.String())
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
		PersonalCalendar      map[string]any   `json:"personal_calendar"`
		SharedCalendars       []map[string]any `json:"shared_calendars"`
		CurrentBudgetMonthKey string           `json:"current_budget_month_key"`
	}
	decodeResponse(t, meRec, &payload)
	if payload.User.Email != "owner@dayflow.local" {
		t.Fatalf("expected authenticated owner, got %q", payload.User.Email)
	}
	if payload.PersonalCalendar["id"] != "cal_001" {
		t.Fatalf("expected personal calendar in me response, got %#v", payload.PersonalCalendar)
	}
	if len(payload.SharedCalendars) != 1 || payload.SharedCalendars[0]["id"] != "cal_002" {
		t.Fatalf("expected one shared calendar in me response, got %#v", payload.SharedCalendars)
	}
	if payload.CurrentBudgetMonthKey == "" {
		t.Fatal("expected current budget month key")
	}
}

func TestBudgetMonthRequiresAuthentication(t *testing.T) {
	req := httptest.NewRequest(http.MethodGet, "/v1/budget/months/2026-03", nil)
	rec := httptest.NewRecorder()

	NewRouter(store.NewMemoryStore()).ServeHTTP(rec, req)

	if rec.Code != http.StatusUnauthorized {
		t.Fatalf("expected 401, got %d body=%s", rec.Code, rec.Body.String())
	}
}

func TestBudgetTemplatesRequiresAuthentication(t *testing.T) {
	req := httptest.NewRequest(http.MethodGet, "/v1/budget/templates", nil)
	rec := httptest.NewRecorder()

	NewRouter(store.NewMemoryStore()).ServeHTTP(rec, req)

	if rec.Code != http.StatusUnauthorized {
		t.Fatalf("expected 401, got %d body=%s", rec.Code, rec.Body.String())
	}
}

func TestBudgetTemplatesPutPersistsAndSeedsFutureMonths(t *testing.T) {
	handler := NewRouter(store.NewMemoryStore())
	token := loginTokenForUser(t, handler, "owner@dayflow.local", "secret1234")

	getRec := performAuthedJSONRequest(t, handler, token, http.MethodGet, "/v1/budget/templates", nil)
	if getRec.Code != http.StatusOK {
		t.Fatalf("expected 200, got %d body=%s", getRec.Code, getRec.Body.String())
	}

	var initial struct {
		FixedItems []struct {
			Name string `json:"name"`
		} `json:"fixed_items"`
	}
	decodeResponse(t, getRec, &initial)
	if len(initial.FixedItems) != 4 {
		t.Fatalf("expected 4 default templates, got %#v", initial.FixedItems)
	}

	putRec := performAuthedJSONRequest(t, handler, token, http.MethodPut, "/v1/budget/templates", map[string]any{
		"fixed_items": []map[string]any{
			{
				"name":                "Rent",
				"default_amount":      120,
				"default_enabled":     true,
				"default_billing_day": "25일",
			},
			{
				"name":                "Phone",
				"kind":                "fixed",
				"default_amount":      10,
				"default_enabled":     false,
				"default_note":        "discount pending",
				"default_billing_day": "15일",
			},
		},
	})
	if putRec.Code != http.StatusOK {
		t.Fatalf("expected 200, got %d body=%s", putRec.Code, putRec.Body.String())
	}

	var saved struct {
		FixedItems []struct {
			ID             string `json:"id"`
			Name           string `json:"name"`
			Kind           string `json:"kind"`
			DefaultAmount  int    `json:"default_amount"`
			DefaultEnabled bool   `json:"default_enabled"`
			SortOrder      int    `json:"sort_order"`
		} `json:"fixed_items"`
	}
	decodeResponse(t, putRec, &saved)
	if len(saved.FixedItems) != 2 {
		t.Fatalf("expected 2 saved templates, got %#v", saved.FixedItems)
	}
	if saved.FixedItems[0].ID == "" || saved.FixedItems[0].Kind != "fixed" || saved.FixedItems[0].SortOrder != 0 {
		t.Fatalf("expected normalized first template, got %#v", saved.FixedItems[0])
	}
	if saved.FixedItems[1].DefaultEnabled {
		t.Fatalf("expected second template to stay disabled, got %#v", saved.FixedItems[1])
	}

	fetchRec := performAuthedJSONRequest(t, handler, token, http.MethodGet, "/v1/budget/templates", nil)
	if fetchRec.Code != http.StatusOK {
		t.Fatalf("expected 200, got %d body=%s", fetchRec.Code, fetchRec.Body.String())
	}

	var fetched struct {
		FixedItems []struct {
			Name          string `json:"name"`
			DefaultAmount int    `json:"default_amount"`
		} `json:"fixed_items"`
	}
	decodeResponse(t, fetchRec, &fetched)
	if len(fetched.FixedItems) != 2 || fetched.FixedItems[0].Name != "Rent" || fetched.FixedItems[1].DefaultAmount != 10 {
		t.Fatalf("expected persisted templates, got %#v", fetched.FixedItems)
	}

	monthRec := performAuthedJSONRequest(t, handler, token, http.MethodGet, "/v1/budget/months/2026-08", nil)
	if monthRec.Code != http.StatusOK {
		t.Fatalf("expected 200, got %d body=%s", monthRec.Code, monthRec.Body.String())
	}

	var month struct {
		FixedItems []struct {
			Name            string `json:"name"`
			Amount          int    `json:"amount"`
			Enabled         bool   `json:"enabled"`
			BillingDayLabel string `json:"billing_day_label"`
		} `json:"fixed_items"`
	}
	decodeResponse(t, monthRec, &month)
	if len(month.FixedItems) != 2 {
		t.Fatalf("expected seeded fixed items, got %#v", month.FixedItems)
	}
	if month.FixedItems[0].Name != "Rent" || month.FixedItems[0].Amount != 120 || month.FixedItems[1].Enabled {
		t.Fatalf("expected future month seeded from templates, got %#v", month.FixedItems)
	}
}

func TestBudgetTemplatesAreScopedPerUser(t *testing.T) {
	handler := NewRouter(store.NewMemoryStore())
	ownerToken := loginTokenForUser(t, handler, "owner@dayflow.local", "secret1234")
	outsiderToken := loginTokenForUser(t, handler, "outside@dayflow.local", "secret1234")

	putRec := performAuthedJSONRequest(t, handler, ownerToken, http.MethodPut, "/v1/budget/templates", map[string]any{
		"fixed_items": []map[string]any{{
			"name":            "Owner Only Rent",
			"default_amount":  777,
			"default_enabled": true,
		}},
	})
	if putRec.Code != http.StatusOK {
		t.Fatalf("expected 200, got %d body=%s", putRec.Code, putRec.Body.String())
	}

	ownerRec := performAuthedJSONRequest(t, handler, ownerToken, http.MethodGet, "/v1/budget/templates", nil)
	outsiderRec := performAuthedJSONRequest(t, handler, outsiderToken, http.MethodGet, "/v1/budget/templates", nil)
	if ownerRec.Code != http.StatusOK || outsiderRec.Code != http.StatusOK {
		t.Fatalf("expected scoped reads to succeed, owner=%d outsider=%d", ownerRec.Code, outsiderRec.Code)
	}

	if !bytes.Contains(ownerRec.Body.Bytes(), []byte("Owner Only Rent")) {
		t.Fatalf("expected owner template in owner payload: %s", ownerRec.Body.String())
	}
	if bytes.Contains(outsiderRec.Body.Bytes(), []byte("Owner Only Rent")) {
		t.Fatalf("expected template isolation, outsider payload leaked: %s", outsiderRec.Body.String())
	}
}

func TestBudgetMonthGetReturnsFullBoard(t *testing.T) {
	handler := NewRouter(store.NewMemoryStore())
	token := loginTokenForUser(t, handler, "owner@dayflow.local", "secret1234")

	rec := performAuthedJSONRequest(t, handler, token, http.MethodGet, "/v1/budget/months/2026-03", nil)
	if rec.Code != http.StatusOK {
		t.Fatalf("expected 200, got %d body=%s", rec.Code, rec.Body.String())
	}

	var payload struct {
		Month struct {
			MonthKey              string `json:"month_key"`
			RemainingBudgetAmount int    `json:"remaining_budget_amount"`
		} `json:"month"`
		Summary struct {
			FixedCostTotal      int `json:"fixed_cost_total"`
			VariableBucketTotal int `json:"variable_bucket_total"`
			FreeCashAmount      int `json:"free_cash_amount"`
		} `json:"summary"`
		FixedItems       []map[string]any `json:"fixed_items"`
		VariableBuckets  []map[string]any `json:"variable_buckets"`
		BillingReminders []map[string]any `json:"billing_reminders"`
	}
	decodeResponse(t, rec, &payload)

	if payload.Month.MonthKey != "2026-03" {
		t.Fatalf("expected month key 2026-03, got %q", payload.Month.MonthKey)
	}
	if payload.Month.RemainingBudgetAmount != 145 {
		t.Fatalf("expected remaining budget 145, got %d", payload.Month.RemainingBudgetAmount)
	}
	if payload.Summary.FixedCostTotal != 153 || payload.Summary.VariableBucketTotal != 12 || payload.Summary.FreeCashAmount != -35 {
		t.Fatalf("unexpected summary: %#v", payload.Summary)
	}
	if len(payload.FixedItems) != 4 || len(payload.VariableBuckets) != 2 || len(payload.BillingReminders) != 2 {
		t.Fatalf("expected full board payload, got %+v", payload)
	}
	if payload.FixedItems[0]["id"] != "bitm_001" || payload.FixedItems[0]["name"] != "월세 및 관리비" || payload.FixedItems[0]["amount"] != float64(21) {
		t.Fatalf("expected first fixed item to match contract example, got %+v", payload.FixedItems[0])
	}
	if payload.VariableBuckets[0]["id"] != "bkt_001" || payload.VariableBuckets[0]["name"] != "점심 및 주말 식대" || payload.VariableBuckets[0]["planned_amount"] != float64(12) {
		t.Fatalf("expected first variable bucket to match contract example, got %+v", payload.VariableBuckets[0])
	}
	if payload.BillingReminders[0]["id"] != "rem_001" || payload.BillingReminders[0]["name"] != "인터넷" || payload.BillingReminders[0]["kind"] != "reminder" {
		t.Fatalf("expected first billing reminder to match contract example, got %+v", payload.BillingReminders[0])
	}
}

func TestBudgetMonthPutPersistsBoardAndDerivesSummary(t *testing.T) {
	handler := NewRouter(store.NewMemoryStore())
	token := loginTokenForUser(t, handler, "owner@dayflow.local", "secret1234")

	payload := map[string]any{
		"month": map[string]any{
			"month_key":           "ignored-by-path",
			"base_budget_amount":  600,
			"current_cash_amount": 300,
			"saving_amount":       100,
			"carry_over_amount":   20,
		},
		"summary": map[string]any{
			"fixed_cost_total":      999,
			"variable_bucket_total": 999,
			"free_cash_amount":      999,
		},
		"fixed_items": []map[string]any{
			{
				"id":                "bitm_custom_1",
				"name":              "Rent",
				"kind":              "fixed",
				"amount":            200,
				"enabled":           true,
				"billing_day_label": "25일",
			},
			{
				"id":                "bitm_custom_2",
				"name":              "Paused",
				"kind":              "fixed",
				"amount":            50,
				"enabled":           false,
				"billing_day_label": "5일",
			},
		},
		"variable_buckets": []map[string]any{
			{
				"id":             "bbkt_custom_1",
				"name":           "Food",
				"planned_amount": 40,
				"actual_amount":  25,
			},
		},
		"billing_reminders": []map[string]any{
			{
				"id":                "brem_custom_1",
				"name":              "Internet",
				"billing_day_label": "28일",
			},
		},
	}

	putRec := performAuthedJSONRequest(t, handler, token, http.MethodPut, "/v1/budget/months/2026-04", payload)
	if putRec.Code != http.StatusOK {
		t.Fatalf("expected 200, got %d body=%s", putRec.Code, putRec.Body.String())
	}

	var saved struct {
		Month struct {
			MonthKey              string `json:"month_key"`
			RemainingBudgetAmount int    `json:"remaining_budget_amount"`
		} `json:"month"`
		Summary struct {
			FixedCostTotal      int `json:"fixed_cost_total"`
			VariableBucketTotal int `json:"variable_bucket_total"`
			FreeCashAmount      int `json:"free_cash_amount"`
		} `json:"summary"`
		BillingReminders []struct {
			Kind string `json:"kind"`
		} `json:"billing_reminders"`
	}
	decodeResponse(t, putRec, &saved)

	if saved.Month.MonthKey != "2026-04" {
		t.Fatalf("expected month key from path, got %q", saved.Month.MonthKey)
	}
	if saved.Month.RemainingBudgetAmount != 280 {
		t.Fatalf("expected remaining budget 280, got %d", saved.Month.RemainingBudgetAmount)
	}
	if saved.Summary.FixedCostTotal != 200 || saved.Summary.VariableBucketTotal != 40 || saved.Summary.FreeCashAmount != 75 {
		t.Fatalf("unexpected derived summary: %#v", saved.Summary)
	}
	if len(saved.BillingReminders) != 1 || saved.BillingReminders[0].Kind != "reminder" {
		t.Fatalf("expected reminder kind to be normalized, got %#v", saved.BillingReminders)
	}

	getRec := performAuthedJSONRequest(t, handler, token, http.MethodGet, "/v1/budget/months/2026-04", nil)
	if getRec.Code != http.StatusOK {
		t.Fatalf("expected 200, got %d body=%s", getRec.Code, getRec.Body.String())
	}

	var fetched struct {
		Month struct {
			RemainingBudgetAmount int `json:"remaining_budget_amount"`
		} `json:"month"`
		Summary struct {
			FixedCostTotal      int `json:"fixed_cost_total"`
			VariableBucketTotal int `json:"variable_bucket_total"`
			FreeCashAmount      int `json:"free_cash_amount"`
		} `json:"summary"`
	}
	decodeResponse(t, getRec, &fetched)
	if fetched.Month.RemainingBudgetAmount != 280 || fetched.Summary.FreeCashAmount != 75 {
		t.Fatalf("expected persisted board, got %#v %#v", fetched.Month, fetched.Summary)
	}
}

func TestBudgetMonthIsScopedPerUser(t *testing.T) {
	handler := NewRouter(store.NewMemoryStore())
	ownerToken := loginTokenForUser(t, handler, "owner@dayflow.local", "secret1234")
	outsiderToken := loginTokenForUser(t, handler, "outside@dayflow.local", "secret1234")

	putRec := performAuthedJSONRequest(t, handler, ownerToken, http.MethodPut, "/v1/budget/months/2026-05", map[string]any{
		"month": map[string]any{
			"base_budget_amount": 999,
		},
		"fixed_items":       []map[string]any{},
		"variable_buckets":  []map[string]any{},
		"billing_reminders": []map[string]any{},
	})
	if putRec.Code != http.StatusOK {
		t.Fatalf("expected 200, got %d body=%s", putRec.Code, putRec.Body.String())
	}

	ownerGet := performAuthedJSONRequest(t, handler, ownerToken, http.MethodGet, "/v1/budget/months/2026-05", nil)
	outsiderGet := performAuthedJSONRequest(t, handler, outsiderToken, http.MethodGet, "/v1/budget/months/2026-05", nil)
	if ownerGet.Code != http.StatusOK || outsiderGet.Code != http.StatusOK {
		t.Fatalf("expected scoped reads to succeed, owner=%d outsider=%d", ownerGet.Code, outsiderGet.Code)
	}

	var ownerPayload struct {
		Month struct {
			BaseBudgetAmount int `json:"base_budget_amount"`
		} `json:"month"`
	}
	var outsiderPayload struct {
		Month struct {
			BaseBudgetAmount int `json:"base_budget_amount"`
		} `json:"month"`
	}
	decodeResponse(t, ownerGet, &ownerPayload)
	decodeResponse(t, outsiderGet, &outsiderPayload)

	if ownerPayload.Month.BaseBudgetAmount != 999 {
		t.Fatalf("expected owner write to persist, got %d", ownerPayload.Month.BaseBudgetAmount)
	}
	if outsiderPayload.Month.BaseBudgetAmount == 999 {
		t.Fatalf("expected outsider board isolation, got leaked payload %d", outsiderPayload.Month.BaseBudgetAmount)
	}
}

func TestSharedCalendarCollaboratorsDoNotAccessOwnerBudget(t *testing.T) {
	handler := NewRouter(store.NewMemoryStore())
	ownerToken := loginTokenForUser(t, handler, "owner@dayflow.local", "secret1234")
	editorToken := loginTokenForUser(t, handler, "editor@dayflow.local", "secret1234")
	viewerToken := loginTokenForUser(t, handler, "viewer@dayflow.local", "secret1234")

	templatesRec := performAuthedJSONRequest(t, handler, ownerToken, http.MethodPut, "/v1/budget/templates", map[string]any{
		"fixed_items": []map[string]any{{
			"name":            "Private Owner Rent",
			"default_amount":  640,
			"default_enabled": true,
		}},
	})
	if templatesRec.Code != http.StatusOK {
		t.Fatalf("expected 200, got %d body=%s", templatesRec.Code, templatesRec.Body.String())
	}

	monthRec := performAuthedJSONRequest(t, handler, ownerToken, http.MethodPut, "/v1/budget/months/2026-06", map[string]any{
		"month": map[string]any{
			"base_budget_amount": 880,
		},
		"fixed_items": []map[string]any{{
			"name":    "Private Owner Rent",
			"kind":    "fixed",
			"amount":  640,
			"enabled": true,
		}},
		"variable_buckets":  []map[string]any{},
		"billing_reminders": []map[string]any{},
	})
	if monthRec.Code != http.StatusOK {
		t.Fatalf("expected 200, got %d body=%s", monthRec.Code, monthRec.Body.String())
	}

	editorTemplates := performAuthedJSONRequest(t, handler, editorToken, http.MethodGet, "/v1/budget/templates", nil)
	viewerTemplates := performAuthedJSONRequest(t, handler, viewerToken, http.MethodGet, "/v1/budget/templates", nil)
	editorMonth := performAuthedJSONRequest(t, handler, editorToken, http.MethodGet, "/v1/budget/months/2026-06", nil)
	viewerMonth := performAuthedJSONRequest(t, handler, viewerToken, http.MethodGet, "/v1/budget/months/2026-06", nil)

	for _, rec := range []*httptest.ResponseRecorder{editorTemplates, viewerTemplates, editorMonth, viewerMonth} {
		if rec.Code != http.StatusOK {
			t.Fatalf("expected collaborator budget request to resolve against their own scope, got %d body=%s", rec.Code, rec.Body.String())
		}
	}

	for _, rec := range []*httptest.ResponseRecorder{editorTemplates, viewerTemplates, editorMonth, viewerMonth} {
		if bytes.Contains(rec.Body.Bytes(), []byte("Private Owner Rent")) {
			t.Fatalf("expected shared collaborator budget payload to stay private: %s", rec.Body.String())
		}
		if bytes.Contains(rec.Body.Bytes(), []byte("880")) {
			t.Fatalf("expected owner month values to stay private: %s", rec.Body.String())
		}
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
		ID   string `json:"id"`
		Kind string `json:"kind"`
	}
	decodeResponse(t, createRec, &createBody)
	calendarID := createBody.ID
	if calendarID == "" {
		t.Fatal("expected calendar id in create response")
	}
	if createBody.Kind != "shared" {
		t.Fatalf("expected shared calendar response, got %#v", createBody)
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

func TestCalendarInviteCreationAndAcceptanceFlow(t *testing.T) {
	handler := NewRouter(store.NewMemoryStore())
	ownerToken := loginTokenForUser(t, handler, "owner@dayflow.local", "secret1234")
	editorToken := loginTokenForUser(t, handler, "editor@dayflow.local", "secret1234")
	viewerToken := loginTokenForUser(t, handler, "viewer@dayflow.local", "secret1234")
	outsiderToken := loginTokenForUser(t, handler, "outside@dayflow.local", "secret1234")

	editorInvite := performAuthedJSONRequest(t, handler, editorToken, http.MethodPost, "/v1/calendars/cal_002/invites", map[string]any{
		"email":            "outside@dayflow.local",
		"delivery_channel": "sms",
		"role":             "viewer",
	})
	if editorInvite.Code != http.StatusForbidden {
		t.Fatalf("expected editor invite creation to be forbidden, got %d body=%s", editorInvite.Code, editorInvite.Body.String())
	}

	personalInvite := performAuthedJSONRequest(t, handler, ownerToken, http.MethodPost, "/v1/calendars/cal_001/invites", map[string]any{
		"email":            "outside@dayflow.local",
		"delivery_channel": "sms",
		"role":             "editor",
	})
	if personalInvite.Code != http.StatusBadRequest {
		t.Fatalf("expected 400 for personal calendar invite, got %d body=%s", personalInvite.Code, personalInvite.Body.String())
	}

	createRec := performAuthedJSONRequest(t, handler, ownerToken, http.MethodPost, "/v1/calendars/cal_002/invites", map[string]any{
		"email":            "outside@dayflow.local",
		"delivery_channel": "sms",
		"role":             "editor",
	})
	if createRec.Code != http.StatusCreated {
		t.Fatalf("expected 201, got %d body=%s", createRec.Code, createRec.Body.String())
	}

	var createBody struct {
		InviteCode      string `json:"invite_code"`
		Role            string `json:"role"`
		DeliveryChannel string `json:"delivery_channel"`
	}
	decodeResponse(t, createRec, &createBody)
	if createBody.InviteCode == "" || createBody.Role != "editor" || createBody.DeliveryChannel != "sms" {
		t.Fatalf("unexpected invite response %#v", createBody)
	}

	previewRec := performAuthedJSONRequest(t, handler, outsiderToken, http.MethodGet, "/v1/invites/"+createBody.InviteCode, nil)
	if previewRec.Code != http.StatusOK {
		t.Fatalf("expected 200 from invite preview, got %d body=%s", previewRec.Code, previewRec.Body.String())
	}
	if !bytes.Contains(previewRec.Body.Bytes(), []byte(`"calendar_name":"Shared Home"`)) {
		t.Fatalf("expected preview payload to include shared calendar name: %s", previewRec.Body.String())
	}

	beforeAccept := performAuthedJSONRequest(t, handler, outsiderToken, http.MethodGet, "/v1/calendars/cal_002/events", nil)
	if beforeAccept.Code != http.StatusForbidden {
		t.Fatalf("expected 403 before invite accept, got %d body=%s", beforeAccept.Code, beforeAccept.Body.String())
	}

	wrongUserAccept := performAuthedJSONRequest(t, handler, viewerToken, http.MethodPost, "/v1/invites/"+createBody.InviteCode+"/accept", nil)
	if wrongUserAccept.Code != http.StatusForbidden {
		t.Fatalf("expected 403 for wrong user accept, got %d body=%s", wrongUserAccept.Code, wrongUserAccept.Body.String())
	}

	acceptRec := performAuthedJSONRequest(t, handler, outsiderToken, http.MethodPost, "/v1/invites/"+createBody.InviteCode+"/accept", nil)
	if acceptRec.Code != http.StatusOK {
		t.Fatalf("expected 200, got %d body=%s", acceptRec.Code, acceptRec.Body.String())
	}
	if !bytes.Contains(acceptRec.Body.Bytes(), []byte(`"calendar"`)) || !bytes.Contains(acceptRec.Body.Bytes(), []byte(`"membership_role":"editor"`)) {
		t.Fatalf("expected accept response to include shared calendar membership, got %s", acceptRec.Body.String())
	}

	meRec := performAuthedJSONRequest(t, handler, outsiderToken, http.MethodGet, "/v1/me", nil)
	if meRec.Code != http.StatusOK {
		t.Fatalf("expected 200 from /me, got %d body=%s", meRec.Code, meRec.Body.String())
	}
	if !bytes.Contains(meRec.Body.Bytes(), []byte(`"cal_002"`)) || !bytes.Contains(meRec.Body.Bytes(), []byte(`"kind":"personal"`)) {
		t.Fatalf("expected personal + shared split in me response: %s", meRec.Body.String())
	}

	listRec := performAuthedJSONRequest(t, handler, outsiderToken, http.MethodGet, "/v1/calendars", nil)
	if listRec.Code != http.StatusOK {
		t.Fatalf("expected 200 from /calendars, got %d body=%s", listRec.Code, listRec.Body.String())
	}
	if !bytes.Contains(listRec.Body.Bytes(), []byte(`"membership_role":"editor"`)) {
		t.Fatalf("expected accepted invite to create editor membership: %s", listRec.Body.String())
	}

	start := time.Date(2026, 3, 19, 9, 0, 0, 0, time.UTC)
	createEvent := performAuthedJSONRequest(t, handler, outsiderToken, http.MethodPost, "/v1/calendars/cal_002/events", map[string]any{
		"title":     "Accepted editor event",
		"notes":     "created after invite accept",
		"starts_at": start.Format(time.RFC3339),
		"ends_at":   start.Add(time.Hour).Format(time.RFC3339),
		"all_day":   false,
	})
	if createEvent.Code != http.StatusCreated {
		t.Fatalf("expected 201 after invite accept, got %d body=%s", createEvent.Code, createEvent.Body.String())
	}
}

func TestAcceptedViewerInviteCreatesViewerMembership(t *testing.T) {
	handler := NewRouter(store.NewMemoryStore())
	ownerToken := loginTokenForUser(t, handler, "owner@dayflow.local", "secret1234")
	outsiderToken := loginTokenForUser(t, handler, "outside@dayflow.local", "secret1234")

	createRec := performAuthedJSONRequest(t, handler, ownerToken, http.MethodPost, "/v1/calendars/cal_002/invites", map[string]any{
		"email":            "outside@dayflow.local",
		"delivery_channel": "email",
		"role":             "viewer",
	})
	if createRec.Code != http.StatusCreated {
		t.Fatalf("expected 201, got %d body=%s", createRec.Code, createRec.Body.String())
	}

	var createBody struct {
		InviteCode string `json:"invite_code"`
	}
	decodeResponse(t, createRec, &createBody)
	if createBody.InviteCode == "" {
		t.Fatal("expected invite code")
	}

	acceptRec := performAuthedJSONRequest(t, handler, outsiderToken, http.MethodPost, "/v1/invites/"+createBody.InviteCode+"/accept", nil)
	if acceptRec.Code != http.StatusOK {
		t.Fatalf("expected 200, got %d body=%s", acceptRec.Code, acceptRec.Body.String())
	}

	meRec := performAuthedJSONRequest(t, handler, outsiderToken, http.MethodGet, "/v1/me", nil)
	if meRec.Code != http.StatusOK {
		t.Fatalf("expected 200 from /me, got %d body=%s", meRec.Code, meRec.Body.String())
	}
	if !bytes.Contains(meRec.Body.Bytes(), []byte(`"cal_002"`)) || !bytes.Contains(meRec.Body.Bytes(), []byte(`"kind":"personal"`)) {
		t.Fatalf("expected accepted invite to create viewer membership: %s", meRec.Body.String())
	}

	calendarListRec := performAuthedJSONRequest(t, handler, outsiderToken, http.MethodGet, "/v1/calendars", nil)
	if calendarListRec.Code != http.StatusOK {
		t.Fatalf("expected 200 from /calendars, got %d body=%s", calendarListRec.Code, calendarListRec.Body.String())
	}
	if !bytes.Contains(calendarListRec.Body.Bytes(), []byte(`"membership_role":"viewer"`)) {
		t.Fatalf("expected accepted viewer membership in shared list: %s", calendarListRec.Body.String())
	}

	listRec := performAuthedJSONRequest(t, handler, outsiderToken, http.MethodGet, "/v1/calendars/cal_002/events", nil)
	if listRec.Code != http.StatusOK {
		t.Fatalf("expected 200 for viewer event read, got %d body=%s", listRec.Code, listRec.Body.String())
	}

	start := time.Date(2026, 3, 20, 9, 0, 0, 0, time.UTC)
	createEvent := performAuthedJSONRequest(t, handler, outsiderToken, http.MethodPost, "/v1/calendars/cal_002/events", map[string]any{
		"title":     "Viewer should not create",
		"notes":     "accepted viewer invite",
		"starts_at": start.Format(time.RFC3339),
		"ends_at":   start.Add(time.Hour).Format(time.RFC3339),
		"all_day":   false,
	})
	if createEvent.Code != http.StatusForbidden {
		t.Fatalf("expected 403 for accepted viewer event create, got %d body=%s", createEvent.Code, createEvent.Body.String())
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

	viewerPatch := performAuthedJSONRequest(t, handler, viewerToken, http.MethodPatch, "/v1/events/"+eventID, map[string]any{
		"title": "Viewer cannot patch",
	})
	if viewerPatch.Code != http.StatusForbidden {
		t.Fatalf("expected viewer patch 403, got %d body=%s", viewerPatch.Code, viewerPatch.Body.String())
	}

	viewerDeleteReq := httptest.NewRequest(http.MethodDelete, "/v1/events/"+eventID, nil)
	viewerDeleteReq.Header.Set("Authorization", "Bearer "+viewerToken)
	viewerDeleteRec := httptest.NewRecorder()
	handler.ServeHTTP(viewerDeleteRec, viewerDeleteReq)
	if viewerDeleteRec.Code != http.StatusForbidden {
		t.Fatalf("expected viewer delete 403, got %d body=%s", viewerDeleteRec.Code, viewerDeleteRec.Body.String())
	}

	outsiderGet := performAuthedJSONRequest(t, handler, outsiderToken, http.MethodGet, "/v1/calendars/cal_002/events", nil)
	if outsiderGet.Code != http.StatusForbidden {
		t.Fatalf("expected 403, got %d body=%s", outsiderGet.Code, outsiderGet.Body.String())
	}

	outsiderPatch := performAuthedJSONRequest(t, handler, outsiderToken, http.MethodPatch, "/v1/events/"+eventID, map[string]any{
		"title": "Outside cannot patch",
	})
	if outsiderPatch.Code != http.StatusForbidden {
		t.Fatalf("expected outsider patch 403, got %d body=%s", outsiderPatch.Code, outsiderPatch.Body.String())
	}

	outsiderDeleteReq := httptest.NewRequest(http.MethodDelete, "/v1/events/"+eventID, nil)
	outsiderDeleteReq.Header.Set("Authorization", "Bearer "+outsiderToken)
	outsiderDeleteRec := httptest.NewRecorder()
	handler.ServeHTTP(outsiderDeleteRec, outsiderDeleteReq)
	if outsiderDeleteRec.Code != http.StatusForbidden {
		t.Fatalf("expected outsider delete 403, got %d body=%s", outsiderDeleteRec.Code, outsiderDeleteRec.Body.String())
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
