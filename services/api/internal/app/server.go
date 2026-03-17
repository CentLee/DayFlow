package app

import (
	"net/http"
	"time"

	"github.com/kakao-ent/dayflow/services/api/internal/httpapi"
	"github.com/kakao-ent/dayflow/services/api/internal/store"
)

func NewServer() *http.Server {
	repo := store.NewMemoryStore()
	handler := httpapi.NewRouter(repo)

	return &http.Server{
		Addr:              ":8080",
		Handler:           handler,
		ReadHeaderTimeout: 5 * time.Second,
	}
}
