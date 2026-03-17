package main

import (
	"log"

	"github.com/kakao-ent/dayflow/services/api/internal/app"
)

func main() {
	server := app.NewServer()
	log.Printf("dayflow api listening on %s", server.Addr)
	if err := server.ListenAndServe(); err != nil {
		log.Fatal(err)
	}
}
