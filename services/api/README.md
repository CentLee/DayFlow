# DayFlow API

Go API for DayFlow.

## Run

```bash
go run ./cmd/dayflow-api
```

## Current Shape

- standard library HTTP server
- in-memory repository for bootstrap
- PostgreSQL migrations staged under `migrations/`
- health, auth, calendar, and budget routes scaffolded

