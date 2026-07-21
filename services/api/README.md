# DayFlow API

Go API for DayFlow.

## Run

```bash
go run ./cmd/dayflow-api
```

## Modes

- default: in-memory runtime for fast local iteration
- hybrid: memory auth/calendar/event flows plus PostgreSQL-backed budget routes

Hybrid mode environment:

```bash
DAYFLOW_STORE_MODE=hybrid
DAYFLOW_DATABASE_URL=postgres://dayflow:dayflow@127.0.0.1:5432/dayflow?sslmode=disable
DAYFLOW_AUTO_MIGRATE=true
DAYFLOW_MIGRATIONS_DIR=./migrations
```

## System Test

From the repo root:

```bash
scripts/run_api_system_tests.sh
```

That script starts the API and PostgreSQL through `infra/docker/docker-compose.system.yml` and then runs black-box API tests against the running service.

## Current Shape

- standard library HTTP server
- stateful in-memory repository for auth, calendar, event, and invite permission checks
- optional hybrid runtime for PostgreSQL-backed budget storage
- PostgreSQL migrations staged under `migrations/`
- health, auth, calendar, event, and budget routes available for MVP foundation

## Local Auth Stub

- requests default to `usr_001`
- set `X-DayFlow-User-ID` to `usr_002`, `usr_003`, or `usr_004` to exercise member access paths
