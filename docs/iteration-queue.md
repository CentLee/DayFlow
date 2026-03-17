# DayFlow Iteration Queue

This document defines the post-bootstrap issue queue that Symphony should consume.

## Operating Rule

- do not create one issue per iteration
- create one issue per agent-sized outcome
- use vertical slices only when the change is small, stable, and user-visible

## Operations Queue

### OPS-1

- Title: `[Integration] define Linear issue template and ready criteria`
- Primary Agent: `integration-agent`
- Inputs:
  - `WORKFLOW.md`
  - `docs/automation-model.md`
- Done When:
  - Linear issue body template is documented
  - ready criteria are documented
  - blocked criteria are documented
- Out of Scope:
  - Symphony server installation

### OPS-2

- Title: `[Integration] define Symphony state machine and pickup filter`
- Primary Agent: `integration-agent`
- Inputs:
  - `WORKFLOW.md`
  - `docs/automation-model.md`
- Done When:
  - state transitions are documented
  - `Ready` pickup policy is documented
  - branch and workspace naming rules are documented
- Out of Scope:
  - CI changes

### OPS-3

- Title: `[Review] define PR review checklist and proof-of-work template`
- Primary Agent: `review-agent`
- Inputs:
  - `WORKFLOW.md`
  - `docs/review-checklist.md`
- Done When:
  - review checklist is documented
  - PR template fields are finalized
  - proof-of-work fields are finalized
- Out of Scope:
  - code implementation

## Iteration 2 Queue

### I2-1

- Title: `[Product] finalize invite auth and calendar sharing constraints`
- Primary Agent: `product-agent`
- Inputs:
  - `docs/product-spec.md`
  - `docs/domain-model.md`
  - `docs/api-contract.md`
- Done When:
  - invite-based signup is described clearly
  - calendar roles are finalized
  - docs no longer conflict
- Out of Scope:
  - backend implementation

### I2-2

- Title: `[Backend] add invite and session schema`
- Primary Agent: `backend-agent`
- Inputs:
  - `docs/domain-model.md`
  - `docs/api-contract.md`
- Done When:
  - users, invites, and sessions schema are defined
  - migration is added
  - backend tests cover schema-backed behavior
- Out of Scope:
  - iOS login UI

### I2-3

- Title: `[Backend] implement register, login, and me endpoints`
- Primary Agent: `backend-agent`
- Inputs:
  - `docs/api-contract.md`
  - `services/api/migrations/`
- Done When:
  - `POST /v1/auth/register` exists
  - `POST /v1/auth/login` exists
  - `GET /v1/me` returns session user data
  - endpoint tests exist
- Out of Scope:
  - calendar CRUD

### I2-4

- Title: `[Backend] implement calendar, membership, and event CRUD`
- Primary Agent: `backend-agent`
- Inputs:
  - `docs/domain-model.md`
  - `docs/api-contract.md`
- Done When:
  - calendar list and creation endpoints work
  - event list and create/update/delete work
  - membership authorization is enforced
  - tests exist
- Out of Scope:
  - iOS data binding

### I2-5

- Title: `[Integration] align auth and calendar payloads`
- Primary Agent: `integration-agent`
- Inputs:
  - `docs/api-contract.md`
  - `docs/sync-model.md`
  - backend auth/calendar changes
- Done When:
  - mock payloads match real API fields
  - bootstrap sequence is documented
  - mismatch list is empty or explicit
- Out of Scope:
  - SwiftUI layout changes

### I2-6

- Title: `[iOS] connect login and session bootstrap`
- Primary Agent: `ios-agent`
- Inputs:
  - `docs/ios-architecture.md`
  - `docs/api-contract.md`
- Done When:
  - login/register views are wired to auth endpoints
  - session bootstrap loads `me`, calendars, and current budget
  - failure state is visible
- Out of Scope:
  - budget board editing

### I2-7

- Title: `[iOS] connect calendar list and month view`
- Primary Agent: `ios-agent`
- Inputs:
  - `docs/ios-architecture.md`
  - calendar endpoints
- Done When:
  - calendar list renders server data
  - month view loads events
  - empty and loading states exist
- Out of Scope:
  - calendar sharing UI

### I2-8

- Title: `[iOS] implement event editor flow`
- Primary Agent: `ios-agent`
- Inputs:
  - `docs/ios-architecture.md`
  - event endpoints
- Done When:
  - create and edit flow exists
  - delete flow exists
  - save error state exists
- Out of Scope:
  - design system expansion

### I2-9

- Title: `[Review] review Iteration 2 PRs`
- Primary Agent: `review-agent`
- Inputs:
  - Iteration 2 PRs
  - `docs/review-checklist.md`
- Done When:
  - all Iteration 2 PRs are reviewed
  - blocking findings are documented
  - residual risks are summarized
- Out of Scope:
  - new feature implementation

## Iteration 3 Queue

### I3-1

- Title: `[Product] finalize monthly budget board edit rules`
- Primary Agent: `product-agent`

### I3-2

- Title: `[Backend] connect budget storage to PostgreSQL`
- Primary Agent: `backend-agent`

### I3-3

- Title: `[Backend] implement budget month read and write endpoints`
- Primary Agent: `backend-agent`

### I3-4

- Title: `[Backend] implement budget template endpoints`
- Primary Agent: `backend-agent`

### I3-5

- Title: `[Integration] validate KPI formulas and budget payloads`
- Primary Agent: `integration-agent`

### I3-6

- Title: `[iOS] connect budget board to live API`
- Primary Agent: `ios-agent`

### I3-7

- Title: `[iOS] add fixed item toggle and amount editing`
- Primary Agent: `ios-agent`

### I3-8

- Title: `[iOS] add variable bucket editing and save status`
- Primary Agent: `ios-agent`

### I3-9

- Title: `[Review] verify Excel-derived budget behavior`
- Primary Agent: `review-agent`

## Iteration 4 Queue

### I4-1

- Title: `[Backend] implement calendar invites and permission enforcement`
- Primary Agent: `backend-agent`

### I4-2

- Title: `[iOS] implement calendar sharing management UI`
- Primary Agent: `ios-agent`

### I4-3

- Title: `[Integration] validate retry, rollback, and sync failure behavior`
- Primary Agent: `integration-agent`

### I4-4

- Title: `[Review] remove over-engineering and check regressions`
- Primary Agent: `review-agent`

### I4-5

- Title: `[Integration] finalize CI and proof-of-work operations`
- Primary Agent: `integration-agent`
