package httpapi

import (
	"encoding/json"
	"errors"
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
	mux.HandleFunc("/v1/auth/register", r.handleRegister)
	mux.HandleFunc("/v1/auth/login", r.handleLogin)
	mux.HandleFunc("/v1/me", r.handleMe)
	mux.HandleFunc("/v1/calendars", r.handleCalendars)
	mux.HandleFunc("/v1/calendars/", r.handleCalendarSubroutes)
	mux.HandleFunc("/v1/budget/months/", r.handleBudgetMonth)
	return mux
}

func (r *Router) handleHealth(w http.ResponseWriter, _ *http.Request) {
	writeJSON(w, http.StatusOK, map[string]string{"status": "ok"})
}

func (r *Router) handleMe(w http.ResponseWriter, req *http.Request) {
	if req.Method != http.MethodGet {
		writeMethodNotAllowed(w)
		return
	}
	token, ok := bearerToken(req)
	if !ok {
		writeUnauthorized(w, "authentication required")
		return
	}
	me, ok := r.store.AuthenticatedMe(token)
	if !ok {
		writeUnauthorized(w, "invalid session")
		return
	}
	writeJSON(w, http.StatusOK, me)
}

func (r *Router) handleRegister(w http.ResponseWriter, req *http.Request) {
	if req.Method != http.MethodPost {
		writeMethodNotAllowed(w)
		return
	}

	var input struct {
		Email       string `json:"email"`
		DisplayName string `json:"display_name"`
		Password    string `json:"password"`
		InviteCode  string `json:"invite_code"`
	}
	if err := json.NewDecoder(req.Body).Decode(&input); err != nil {
		writeBadRequest(w, "invalid request body")
		return
	}
	if input.Email == "" || input.DisplayName == "" || input.Password == "" || input.InviteCode == "" {
		writeBadRequest(w, "email, display_name, password, and invite_code are required")
		return
	}

	user, token, err := r.store.Register(input.Email, input.DisplayName, input.Password, input.InviteCode)
	if err != nil {
		switch {
		case errors.Is(err, store.ErrInvalidInvite), errors.Is(err, store.ErrInviteEmailMismatch):
			writeJSON(w, http.StatusForbidden, errorPayload("invalid_invite", err.Error()))
		case errors.Is(err, store.ErrEmailTaken):
			writeJSON(w, http.StatusConflict, errorPayload("email_taken", err.Error()))
		default:
			writeBadRequest(w, err.Error())
		}
		return
	}

	writeJSON(w, http.StatusCreated, map[string]any{"user": user, "token": token})
}

func (r *Router) handleLogin(w http.ResponseWriter, req *http.Request) {
	if req.Method != http.MethodPost {
		writeMethodNotAllowed(w)
		return
	}

	var input struct {
		Email    string `json:"email"`
		Password string `json:"password"`
	}
	if err := json.NewDecoder(req.Body).Decode(&input); err != nil {
		writeBadRequest(w, "invalid request body")
		return
	}
	if input.Email == "" || input.Password == "" {
		writeBadRequest(w, "email and password are required")
		return
	}

	user, token, err := r.store.Login(input.Email, input.Password)
	if err != nil {
		if errors.Is(err, store.ErrInvalidCredentials) {
			writeUnauthorized(w, err.Error())
			return
		}
		writeBadRequest(w, err.Error())
		return
	}

	writeJSON(w, http.StatusOK, map[string]any{"user": user, "token": token})
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
	writeJSON(w, http.StatusMethodNotAllowed, errorPayload("method_not_allowed", "method not allowed"))
}

func writeBadRequest(w http.ResponseWriter, message string) {
	writeJSON(w, http.StatusBadRequest, errorPayload("bad_request", message))
}

func writeUnauthorized(w http.ResponseWriter, message string) {
	writeJSON(w, http.StatusUnauthorized, errorPayload("unauthorized", message))
}

func errorPayload(code, message string) map[string]any {
	return map[string]any{
		"error": map[string]string{
			"code":    code,
			"message": message,
		},
	}
}

func bearerToken(req *http.Request) (string, bool) {
	authorization := strings.TrimSpace(req.Header.Get("Authorization"))
	if authorization == "" {
		return "", false
	}
	parts := strings.SplitN(authorization, " ", 2)
	if len(parts) != 2 || !strings.EqualFold(parts[0], "Bearer") || strings.TrimSpace(parts[1]) == "" {
		return "", false
	}
	return strings.TrimSpace(parts[1]), true
}

func writeJSON(w http.ResponseWriter, status int, payload any) {
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(status)
	_ = json.NewEncoder(w).Encode(payload)
}
