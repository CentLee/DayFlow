# DayFlow

DayFlow is a local-first monorepo for a shared calendar and personal-first monthly budget board.

## Stack

- iOS: SwiftUI
- API: Go
- Database: PostgreSQL 16
- Infra: Docker Compose
- Workflow: Symphony + Linear + Codex

## Repository Layout

- `apps/ios`: SwiftUI app skeleton and design notes
- `services/api`: Go API skeleton, domain model, migrations
- `infra/docker`: local Postgres
- `docs`: product, domain, API, iOS, sync, Symphony docs
- `.codex/agents`: DayFlow-specific agent definitions
- `.codex/skills`: DayFlow-specific adapter skills

## Skill Layers

DayFlow assumes two skill layers:

- global harness skills live in the local machine's `~/.codex/skills`
- project-specific rules live in this repository under `.codex/`

The global harness layer owns reusable orchestration and agent design patterns.
This repository only keeps the DayFlow-specific contracts, domain rules, and thin adapters needed
for autonomous project execution.

## Git Flow

DayFlow uses:

- `main` for release-ready history
- `develop` for integrated working state
- `codex/<issue-id>-<short-slug>` for isolated issue work

Implementation PRs target `develop` and are normally squash-merged. `develop` is merged into `main`
only after review and stabilization.

## Product Direction

DayFlow is optimized around two ideas:

1. Calendars are personal by default, but each calendar can be shared with selected users.
2. Budgeting is personal and month-board driven, inspired by the provided Excel workbook.

The budget UX is not a traditional transaction ledger first. The main screen is a monthly board with:

- top KPI summary
- fixed-cost toggle and amount editing
- variable budget buckets
- billing reminders

## Local Development

### 1. Start Postgres

```bash
docker compose -f infra/docker/docker-compose.yml up -d
```

### 2. Run API

```bash
cd services/api
go run ./cmd/dayflow-api
```

### 3. iOS App

The iOS app scaffold lives in `apps/ios`. The repo includes SwiftUI source structure and a project spec placeholder.
Open it in Xcode and create or wire an app target around the provided files.

## MVP Scope

- Auth with invited account + password
- Calendar CRUD with calendar-level sharing
- Monthly budget board
- Fixed item templates, variable buckets, billing reminders
- Simple optimistic sync for budget edits

## Symphony

See `WORKFLOW.md` and `docs/symphony-setup.md`.

Additional operating docs:

- `docs/automation-model.md`
- `docs/iteration-queue.md`
- `docs/review-checklist.md`
- `docs/github-local-auth.md`

### Recommended Run Command

Use the wrapper below instead of launching Symphony directly. It keeps Linear states aligned with PR state.

```bash
LINEAR_API_KEY=... scripts/run_symphony.sh
```

Dashboards:

- implementation lane: `http://127.0.0.1:4100/`
- review lane: `http://127.0.0.1:4101/`
