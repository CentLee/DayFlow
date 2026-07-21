package main

import (
	"errors"
	"log"
	"net/http"

	"github.com/kakao-ent/dayflow/services/api/internal/app"
)

func main() {
	server, err := app.NewServerFromEnv()
	if err != nil {
		log.Fatal(err)
	}
	log.Printf("dayflow api listening on %s", server.Addr)
	if err := server.ListenAndServe(); err != nil && !errors.Is(err, http.ErrServerClosed) {
		log.Fatal(err)
	}
}
