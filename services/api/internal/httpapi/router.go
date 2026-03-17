package httpapi

import (
	"encoding/json"
	"net/http"
	"strings"

	"github.com/kakao-ent/dayflow/services/api/internal/store"
)

type Router struct {
	store *store.MemoryStore
}

func NewRouter(store *store.MemoryStore) http.Handler {
	r := &Router{store: store}
	mux := http.NewServeMux()
	mux.HandleFunc("/healthz", r.handleHealth)
	mux.HandleFunc("/v1/me", r.handleMe)
	mux.HandleFunc("/v1/calendars", r.handleCalendars)
	mux.HandleFunc("/v1/calendars/", r.handleCalendarSubroutes)
	mux.HandleFunc("/v1/budget/months/", r.handleBudgetMonth)
	return mux
}

func (r *Router) handleHealth(w http.ResponseWriter, _ *http.Request) {
	writeJSON(w, http.StatusOK, map[string]string{"status": "ok"})
}

func (r *Router) handleMe(w http.ResponseWriter, _ *http.Request) {
	writeJSON(w, http.StatusOK, map[string]any{"user": r.store.Me()})
}

func (r *Router) handleCalendars(w http.ResponseWriter, req *http.Request) {
	switch req.Method {
	case http.MethodGet:
		writeJSON(w, http.StatusOK, map[string]any{"items": r.store.Calendars()})
	case http.MethodPost:
		writeJSON(w, http.StatusCreated, map[string]string{"status": "not_implemented"})
	default:
		writeMethodNotAllowed(w)
	}
}

func (r *Router) handleCalendarSubroutes(w http.ResponseWriter, req *http.Request) {
	path := strings.TrimPrefix(req.URL.Path, "/v1/calendars/")
	parts := strings.Split(path, "/")
	if len(parts) == 2 && parts[1] == "events" && req.Method == http.MethodGet {
		writeJSON(w, http.StatusOK, map[string]any{"items": r.store.Events(parts[0])})
		return
	}
	if len(parts) == 2 && parts[1] == "invites" && req.Method == http.MethodPost {
		writeJSON(w, http.StatusCreated, map[string]string{"status": "not_implemented"})
		return
	}
	http.NotFound(w, req)
}

func (r *Router) handleBudgetMonth(w http.ResponseWriter, req *http.Request) {
	monthKey := strings.TrimPrefix(req.URL.Path, "/v1/budget/months/")
	switch req.Method {
	case http.MethodGet:
		writeJSON(w, http.StatusOK, r.store.BudgetBoard(monthKey))
	case http.MethodPut:
		writeJSON(w, http.StatusOK, map[string]string{"status": "not_implemented", "month_key": monthKey})
	default:
		writeMethodNotAllowed(w)
	}
}

func writeMethodNotAllowed(w http.ResponseWriter) {
	writeJSON(w, http.StatusMethodNotAllowed, map[string]any{
		"error": map[string]string{
			"code":    "method_not_allowed",
			"message": "method not allowed",
		},
	})
}

func writeJSON(w http.ResponseWriter, status int, payload any) {
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(status)
	_ = json.NewEncoder(w).Encode(payload)
}
