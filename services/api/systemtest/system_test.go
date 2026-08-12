package systemtest

import (
	"bytes"
	"context"
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

func TestSystemHouseholdTopology(t *testing.T) {
	client, baseURL := systemClient(t)

	ownerToken := loginToken(t, client, baseURL, "owner@dayflow.local", "secret1234")
	partnerToken := loginToken(t, client, baseURL, "editor@dayflow.local", "secret1234")
	outsiderToken := loginToken(t, client, baseURL, "outside@dayflow.local", "secret1234")

	for _, token := range []string{ownerToken, partnerToken} {
		calendarsResp := authedJSONRequest(t, client, token, http.MethodGet, baseURL+"/v1/calendars", nil)
		if calendarsResp.StatusCode != http.StatusOK {
			calendarsResp.Body.Close()
			t.Fatalf("list household calendars: expected 200, got %d", calendarsResp.StatusCode)
		}
		var payload struct {
			Items []struct {
				ID   string `json:"id"`
				Kind string `json:"kind"`
			} `json:"items"`
		}
		decodeResponse(t, calendarsResp, &payload)
		if len(payload.Items) != 1 || payload.Items[0].ID != "cal_002" || payload.Items[0].Kind != "household" {
			t.Fatalf("expected one household calendar, got %#v", payload.Items)
		}
	}

	partnerEventsResp := authedJSONRequest(t, client, partnerToken, http.MethodGet, baseURL+"/v1/calendars/cal_002/events", nil)
	defer partnerEventsResp.Body.Close()
	if partnerEventsResp.StatusCode != http.StatusOK {
		t.Fatalf("partner household events: expected 200, got %d", partnerEventsResp.StatusCode)
	}

	outsiderEventsResp := authedJSONRequest(t, client, outsiderToken, http.MethodGet, baseURL+"/v1/calendars/cal_002/events", nil)
	defer outsiderEventsResp.Body.Close()
	if outsiderEventsResp.StatusCode != http.StatusForbidden {
		t.Fatalf("outsider household events: expected 403, got %d", outsiderEventsResp.StatusCode)
	}

	inviteResp := authedJSONRequest(t, client, ownerToken, http.MethodPost, baseURL+"/v1/calendars/cal_002/invites", map[string]any{
		"email":            "guest-system@dayflow.local",
		"delivery_channel": "sms",
		"role":             "editor",
	})
	defer inviteResp.Body.Close()
	if inviteResp.StatusCode != http.StatusForbidden {
		t.Fatalf("household invite: expected 403, got %d", inviteResp.StatusCode)
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
	return requestWithContext(t, client, context.Background(), method, url, token, payload)
}

func requestWithContext(t *testing.T, client *http.Client, ctx context.Context, method, url, token string, payload any) *http.Response {
	t.Helper()

	var body bytes.Buffer
	if payload != nil {
		if err := json.NewEncoder(&body).Encode(payload); err != nil {
			t.Fatalf("encode request: %v", err)
		}
	}

	req, err := http.NewRequestWithContext(ctx, method, url, &body)
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

func containsCalendar(calendars []struct {
	ID string `json:"id"`
}, id string) bool {
	for _, calendar := range calendars {
		if calendar.ID == id {
			return true
		}
	}
	return false
}

func decodeResponse(t *testing.T, resp *http.Response, target any) {
	t.Helper()
	defer resp.Body.Close()
	if err := json.NewDecoder(resp.Body).Decode(target); err != nil {
		t.Fatalf("decode response (%s): %v", fmt.Sprintf("%s %s", resp.Request.Method, resp.Request.URL.String()), err)
	}
}
