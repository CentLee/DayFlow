package systemtest

import (
	"bytes"
	"encoding/json"
	"fmt"
	"net/http"
	"os"
	"strings"
	"testing"
	"time"
)

func TestSystemHealth(t *testing.T) {
	client, baseURL := systemClient(t)

	resp, err := client.Get(baseURL + "/healthz")
	if err != nil {
		t.Fatalf("health request: %v", err)
	}
	defer resp.Body.Close()

	if resp.StatusCode != http.StatusOK {
		t.Fatalf("expected 200, got %d", resp.StatusCode)
	}
}

func TestSystemInviteFlow(t *testing.T) {
	client, baseURL := systemClient(t)

	ownerToken := loginToken(t, client, baseURL, "owner@dayflow.local", "secret1234")
	outsiderToken := loginToken(t, client, baseURL, "outside@dayflow.local", "secret1234")

	createInviteResp := authedJSONRequest(t, client, ownerToken, http.MethodPost, baseURL+"/v1/calendars/cal_002/invites", map[string]any{
		"email":            "guest-system@dayflow.local",
		"delivery_channel": "sms",
		"role":             "editor",
	})
	if createInviteResp.StatusCode != http.StatusCreated {
		t.Fatalf("expected 201, got %d", createInviteResp.StatusCode)
	}

	var invite struct {
		InviteCode string `json:"invite_code"`
	}
	decodeResponse(t, createInviteResp, &invite)
	if invite.InviteCode == "" {
		t.Fatal("expected invite code")
	}

	previewResp := mustRequest(t, client, http.MethodGet, baseURL+"/v1/invites/"+invite.InviteCode, "", nil)
	defer previewResp.Body.Close()
	if previewResp.StatusCode != http.StatusOK {
		t.Fatalf("expected 200, got %d", previewResp.StatusCode)
	}

	acceptResp := authedJSONRequest(t, client, outsiderToken, http.MethodPost, baseURL+"/v1/invites/"+invite.InviteCode+"/accept", nil)
	defer acceptResp.Body.Close()
	if acceptResp.StatusCode != http.StatusForbidden {
		t.Fatalf("expected 403 for mismatched invite target, got %d", acceptResp.StatusCode)
	}
}

func TestSystemBudgetTemplatesAndBoard(t *testing.T) {
	client, baseURL := systemClient(t)
	ownerToken := loginToken(t, client, baseURL, "owner@dayflow.local", "secret1234")

	templatesResp := authedJSONRequest(t, client, ownerToken, http.MethodGet, baseURL+"/v1/budget/templates", nil)
	if templatesResp.StatusCode != http.StatusOK {
		t.Fatalf("expected 200, got %d", templatesResp.StatusCode)
	}

	var templates struct {
		FixedItems []map[string]any `json:"fixed_items"`
	}
	decodeResponse(t, templatesResp, &templates)
	if len(templates.FixedItems) == 0 {
		t.Fatal("expected seeded budget templates")
	}

	saveTemplatesResp := authedJSONRequest(t, client, ownerToken, http.MethodPut, baseURL+"/v1/budget/templates", map[string]any{
		"fixed_items": []map[string]any{
			{
				"name":                "Mortgage",
				"default_amount":      123,
				"default_enabled":     true,
				"default_billing_day": "10일",
			},
			{
				"name":                "Phone",
				"default_amount":      9,
				"default_enabled":     true,
				"default_billing_day": "15일",
			},
		},
	})
	defer saveTemplatesResp.Body.Close()
	if saveTemplatesResp.StatusCode != http.StatusOK {
		t.Fatalf("expected 200, got %d", saveTemplatesResp.StatusCode)
	}

	monthKey := "2030-12"
	saveBoardResp := authedJSONRequest(t, client, ownerToken, http.MethodPut, baseURL+"/v1/budget/months/"+monthKey, map[string]any{
		"month": map[string]any{
			"base_budget_amount":  700,
			"current_cash_amount": 350,
			"saving_amount":       120,
			"carry_over_amount":   15,
		},
		"fixed_items": []map[string]any{
			{
				"name":              "Mortgage",
				"kind":              "fixed",
				"amount":            123,
				"enabled":           true,
				"billing_day_label": "10일",
			},
		},
		"variable_buckets": []map[string]any{
			{
				"name":           "Groceries",
				"planned_amount": 80,
				"actual_amount":  40,
			},
		},
		"billing_reminders": []map[string]any{
			{
				"name":              "Insurance",
				"billing_day_label": "28일",
				"note":              "system test reminder",
			},
		},
	})
	defer saveBoardResp.Body.Close()
	if saveBoardResp.StatusCode != http.StatusOK {
		t.Fatalf("expected 200, got %d", saveBoardResp.StatusCode)
	}

	loadBoardResp := authedJSONRequest(t, client, ownerToken, http.MethodGet, baseURL+"/v1/budget/months/"+monthKey, nil)
	if loadBoardResp.StatusCode != http.StatusOK {
		t.Fatalf("expected 200, got %d", loadBoardResp.StatusCode)
	}

	var board struct {
		Month struct {
			MonthKey              string `json:"month_key"`
			BaseBudgetAmount      int    `json:"base_budget_amount"`
			RemainingBudgetAmount int    `json:"remaining_budget_amount"`
		} `json:"month"`
		Summary struct {
			FixedCostTotal      int `json:"fixed_cost_total"`
			VariableBucketTotal int `json:"variable_bucket_total"`
		} `json:"summary"`
		FixedItems       []map[string]any `json:"fixed_items"`
		VariableBuckets  []map[string]any `json:"variable_buckets"`
		BillingReminders []map[string]any `json:"billing_reminders"`
	}
	decodeResponse(t, loadBoardResp, &board)

	if board.Month.MonthKey != monthKey || board.Month.BaseBudgetAmount != 700 {
		t.Fatalf("unexpected month payload %#v", board.Month)
	}
	if board.Summary.FixedCostTotal != 123 || board.Summary.VariableBucketTotal != 80 {
		t.Fatalf("unexpected summary %#v", board.Summary)
	}
	if len(board.FixedItems) != 1 || len(board.VariableBuckets) != 1 || len(board.BillingReminders) != 1 {
		t.Fatalf("unexpected board collections %#v", board)
	}
}

func systemClient(t *testing.T) (*http.Client, string) {
	t.Helper()

	baseURL := strings.TrimRight(os.Getenv("DAYFLOW_SYSTEM_BASE_URL"), "/")
	if baseURL == "" {
		t.Skip("DAYFLOW_SYSTEM_BASE_URL is not set")
	}

	return &http.Client{Timeout: 10 * time.Second}, baseURL
}

func loginToken(t *testing.T, client *http.Client, baseURL, email, password string) string {
	t.Helper()

	resp := mustRequest(t, client, http.MethodPost, baseURL+"/v1/auth/login", "", map[string]any{
		"email":    email,
		"password": password,
	})
	if resp.StatusCode != http.StatusOK {
		t.Fatalf("expected 200, got %d", resp.StatusCode)
	}

	var payload struct {
		Token string `json:"token"`
	}
	decodeResponse(t, resp, &payload)
	if payload.Token == "" {
		t.Fatal("expected token")
	}
	return payload.Token
}

func authedJSONRequest(t *testing.T, client *http.Client, token, method, url string, payload any) *http.Response {
	t.Helper()
	return mustRequest(t, client, method, url, token, payload)
}

func mustRequest(t *testing.T, client *http.Client, method, url, token string, payload any) *http.Response {
	t.Helper()

	var body bytes.Buffer
	if payload != nil {
		if err := json.NewEncoder(&body).Encode(payload); err != nil {
			t.Fatalf("encode request: %v", err)
		}
	}

	req, err := http.NewRequest(method, url, &body)
	if err != nil {
		t.Fatalf("new request: %v", err)
	}
	if payload != nil {
		req.Header.Set("Content-Type", "application/json")
	}
	if token != "" {
		req.Header.Set("Authorization", "Bearer "+token)
	}

	resp, err := client.Do(req)
	if err != nil {
		t.Fatalf("%s %s: %v", method, url, err)
	}
	return resp
}

func decodeResponse(t *testing.T, resp *http.Response, target any) {
	t.Helper()
	defer resp.Body.Close()
	if err := json.NewDecoder(resp.Body).Decode(target); err != nil {
		t.Fatalf("decode response (%s): %v", fmt.Sprintf("%s %s", resp.Request.Method, resp.Request.URL.String()), err)
	}
}
