package httpapi

import (
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"net/http"
	"strings"
	"time"

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
	mux.HandleFunc("/v1/events/", r.handleEvents)
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
	userID, ok := r.currentUserID(w, req)
	if !ok {
		return
	}
	user, _ := r.store.Me(userID)
	writeJSON(w, http.StatusOK, map[string]any{"user": user})
}

func (r *Router) handleCalendars(w http.ResponseWriter, req *http.Request) {
	userID, ok := r.currentUserID(w, req)
	if !ok {
		return
	}

	switch req.Method {
	case http.MethodGet:
		writeJSON(w, http.StatusOK, map[string]any{"items": r.store.ListCalendars(userID)})
	case http.MethodPost:
		var payload struct {
			Name  string `json:"name"`
			Color string `json:"color"`
		}
		if err := decodeJSON(req, &payload); err != nil {
			writeStoreError(w, err)
			return
		}
		calendar, err := r.store.CreateCalendar(userID, store.CalendarInput{Name: payload.Name, Color: payload.Color})
		if err != nil {
			writeStoreError(w, err)
			return
		}
		writeJSON(w, http.StatusCreated, map[string]any{"calendar": calendar})
	default:
		writeMethodNotAllowed(w)
	}
}

func (r *Router) handleCalendarSubroutes(w http.ResponseWriter, req *http.Request) {
	path := strings.TrimPrefix(req.URL.Path, "/v1/calendars/")
	parts := strings.Split(path, "/")
	userID, ok := r.currentUserID(w, req)
	if !ok {
		return
	}

	if len(parts) == 1 && parts[0] != "" {
		switch req.Method {
		case http.MethodPatch:
			var payload struct {
				Name  *string `json:"name"`
				Color *string `json:"color"`
			}
			if err := decodeJSON(req, &payload); err != nil {
				writeStoreError(w, err)
				return
			}
			calendar, err := r.store.UpdateCalendar(userID, parts[0], store.CalendarPatch{Name: payload.Name, Color: payload.Color})
			if err != nil {
				writeStoreError(w, err)
				return
			}
			writeJSON(w, http.StatusOK, map[string]any{"calendar": calendar})
			return
		case http.MethodDelete:
			if err := r.store.DeleteCalendar(userID, parts[0]); err != nil {
				writeStoreError(w, err)
				return
			}
			w.WriteHeader(http.StatusNoContent)
			return
		default:
			writeMethodNotAllowed(w)
			return
		}
	}
	if len(parts) == 2 && parts[1] == "events" {
		switch req.Method {
		case http.MethodGet:
			from, to, err := parseEventRange(req)
			if err != nil {
				writeStoreError(w, err)
				return
			}
			items, err := r.store.ListEvents(userID, parts[0], from, to)
			if err != nil {
				writeStoreError(w, err)
				return
			}
			writeJSON(w, http.StatusOK, map[string]any{"items": items})
			return
		case http.MethodPost:
			input, err := decodeEventInput(req)
			if err != nil {
				writeStoreError(w, err)
				return
			}
			event, err := r.store.CreateEvent(userID, parts[0], input)
			if err != nil {
				writeStoreError(w, err)
				return
			}
			writeJSON(w, http.StatusCreated, map[string]any{"event": event})
			return
		default:
			writeMethodNotAllowed(w)
			return
		}
	}
	if len(parts) == 2 && parts[1] == "invites" && req.Method == http.MethodPost {
		writeJSON(w, http.StatusCreated, map[string]string{"status": "not_implemented"})
		return
	}
	http.NotFound(w, req)
}

func (r *Router) handleEvents(w http.ResponseWriter, req *http.Request) {
	userID, ok := r.currentUserID(w, req)
	if !ok {
		return
	}

	eventID := strings.TrimPrefix(req.URL.Path, "/v1/events/")
	if eventID == "" {
		http.NotFound(w, req)
		return
	}

	switch req.Method {
	case http.MethodPatch:
		patch, err := decodeEventPatch(req)
		if err != nil {
			writeStoreError(w, err)
			return
		}
		event, err := r.store.UpdateEvent(userID, eventID, patch)
		if err != nil {
			writeStoreError(w, err)
			return
		}
		writeJSON(w, http.StatusOK, map[string]any{"event": event})
	case http.MethodDelete:
		if err := r.store.DeleteEvent(userID, eventID); err != nil {
			writeStoreError(w, err)
			return
		}
		w.WriteHeader(http.StatusNoContent)
	default:
		writeMethodNotAllowed(w)
	}
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

func (r *Router) currentUserID(w http.ResponseWriter, req *http.Request) (string, bool) {
	userID := req.Header.Get("X-DayFlow-User-ID")
	if userID == "" {
		userID = "usr_001"
	}
	if _, ok := r.store.Me(userID); !ok {
		writeJSON(w, http.StatusUnauthorized, map[string]any{
			"error": map[string]string{
				"code":    "unauthorized",
				"message": "unknown user",
			},
		})
		return "", false
	}
	return userID, true
}

func decodeJSON(req *http.Request, dest any) error {
	defer req.Body.Close()
	decoder := json.NewDecoder(req.Body)
	decoder.DisallowUnknownFields()
	if err := decoder.Decode(dest); err != nil {
		if errors.Is(err, io.EOF) {
			return fmt.Errorf("request body is required: %w", store.ErrInvalidInput)
		}
		return fmt.Errorf("invalid json payload: %w", store.ErrInvalidInput)
	}
	if decoder.More() {
		return fmt.Errorf("request body must contain a single json object: %w", store.ErrInvalidInput)
	}
	return nil
}

func decodeEventInput(req *http.Request) (store.EventInput, error) {
	var payload struct {
		Title    string `json:"title"`
		Notes    string `json:"notes"`
		StartsAt string `json:"starts_at"`
		EndsAt   string `json:"ends_at"`
		AllDay   bool   `json:"all_day"`
	}
	if err := decodeJSON(req, &payload); err != nil {
		return store.EventInput{}, err
	}
	startsAt, err := time.Parse(time.RFC3339, payload.StartsAt)
	if err != nil {
		return store.EventInput{}, fmt.Errorf("starts_at must be RFC3339: %w", store.ErrInvalidInput)
	}
	endsAt, err := time.Parse(time.RFC3339, payload.EndsAt)
	if err != nil {
		return store.EventInput{}, fmt.Errorf("ends_at must be RFC3339: %w", store.ErrInvalidInput)
	}
	return store.EventInput{Title: payload.Title, Notes: payload.Notes, StartsAt: startsAt, EndsAt: endsAt, AllDay: payload.AllDay}, nil
}

func decodeEventPatch(req *http.Request) (store.EventPatch, error) {
	var payload struct {
		Title    *string `json:"title"`
		Notes    *string `json:"notes"`
		StartsAt *string `json:"starts_at"`
		EndsAt   *string `json:"ends_at"`
		AllDay   *bool   `json:"all_day"`
	}
	if err := decodeJSON(req, &payload); err != nil {
		return store.EventPatch{}, err
	}
	patch := store.EventPatch{Title: payload.Title, Notes: payload.Notes, AllDay: payload.AllDay}
	if payload.StartsAt != nil {
		startsAt, err := time.Parse(time.RFC3339, *payload.StartsAt)
		if err != nil {
			return store.EventPatch{}, fmt.Errorf("starts_at must be RFC3339: %w", store.ErrInvalidInput)
		}
		patch.StartsAt = &startsAt
	}
	if payload.EndsAt != nil {
		endsAt, err := time.Parse(time.RFC3339, *payload.EndsAt)
		if err != nil {
			return store.EventPatch{}, fmt.Errorf("ends_at must be RFC3339: %w", store.ErrInvalidInput)
		}
		patch.EndsAt = &endsAt
	}
	return patch, nil
}

func parseEventRange(req *http.Request) (*time.Time, *time.Time, error) {
	var fromPtr *time.Time
	if rawFrom := req.URL.Query().Get("from"); rawFrom != "" {
		from, err := time.Parse(time.RFC3339, rawFrom)
		if err != nil {
			return nil, nil, fmt.Errorf("from must be RFC3339: %w", store.ErrInvalidInput)
		}
		fromPtr = &from
	}
	var toPtr *time.Time
	if rawTo := req.URL.Query().Get("to"); rawTo != "" {
		to, err := time.Parse(time.RFC3339, rawTo)
		if err != nil {
			return nil, nil, fmt.Errorf("to must be RFC3339: %w", store.ErrInvalidInput)
		}
		toPtr = &to
	}
	return fromPtr, toPtr, nil
}

func writeStoreError(w http.ResponseWriter, err error) {
	switch {
	case errors.Is(err, store.ErrForbidden):
		writeJSON(w, http.StatusForbidden, map[string]any{"error": map[string]string{"code": "forbidden", "message": "calendar access denied"}})
	case errors.Is(err, store.ErrNotFound):
		writeJSON(w, http.StatusNotFound, map[string]any{"error": map[string]string{"code": "not_found", "message": "resource not found"}})
	case errors.Is(err, store.ErrInvalidInput):
		writeJSON(w, http.StatusBadRequest, map[string]any{"error": map[string]string{"code": "invalid_input", "message": err.Error()}})
	default:
		writeJSON(w, http.StatusInternalServerError, map[string]any{"error": map[string]string{"code": "internal", "message": "internal server error"}})
	}
}

func writeJSON(w http.ResponseWriter, status int, payload any) {
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(status)
	_ = json.NewEncoder(w).Encode(payload)
}
