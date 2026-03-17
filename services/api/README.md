# DayFlow API

Go API for DayFlow.

## Run

```bash
go run ./cmd/dayflow-api
```

## Current Shape

- standard library HTTP server
- stateful in-memory repository for local CRUD and permission checks
- PostgreSQL migrations staged under `migrations/`
- health, auth, calendar, event, and budget routes available for MVP foundation

## Local Auth Stub

- requests default to `usr_001`
- set `X-DayFlow-User-ID` to `usr_002`, `usr_003`, or `usr_004` to exercise member access paths
