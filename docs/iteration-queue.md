# DayFlow Delivery Queue

This queue was rebased by CEN-43 after the fixed two-person topology and local
runner stabilization work. It separates completed Linear history from future
delivery work. A completed `CEN-*` identifier is historical and must never be
reused, reopened, or treated as the identifier for a future task.

The product baseline remains fixed: one owner, one partner, two allowlisted
Google identities, one personal calendar each, one household calendar,
owner-only budget data, and private iMac access through Tailscale MagicDNS.
Google Calendar sync, generic invitations, arbitrary membership, and public
ingress are not delivery-queue options.

The Excel workbook remains a read-only product-design reference for the
monthly board interaction and KPI formulas. It is not an application input or
a delivery artifact.

## Completed Linear History

The following identifiers are closed history, not available queue slots:

| Linear issue | Completed scope |
| --- | --- |
| CEN-34 | Aligned the local runner with the Terra policy and established the cutover execution base. |
| CEN-35 | Implemented the fixed two-person data topology and migration safety. |
| CEN-36 | Corrected cached-context accounting in the runner. |
| CEN-37 | Prevented finalized lifecycle records from being dispatched again. |
| CEN-38 | Excluded auxiliary state artifacts from issue execution. |
| CEN-39 | Hardened runner publication admission. |
| CEN-40 | Bounded runner token budgets. |
| CEN-41 | Preserved stacked completed worktrees. |
| CEN-42 | Made context-budget observations non-blocking. |

CEN-43 is the product queue rebase represented by this document. It is not a
replacement identifier for the old cutover brief.

The prior CEN-24 through CEN-27 plan remains superseded or cancelled. Its
private deployment, authentication, calendar, budget, offline, and cutover
intent is represented only by the future briefs below; its public onboarding,
generic invitation, and arbitrary sharing intent remains cancelled.

## Future Identifier and Admission Rule

`DQ-01` through `DQ-08` are stable document keys, not Linear identifiers. For
each brief:

1. Create the earliest uncreated eligible brief in Linear and let Linear assign
   a new, unique `CEN-*` identifier. Never predict, renumber, or recycle an ID.
2. Copy the brief's goal, inputs, acceptance criteria, exclusions, ownership,
   and write scope into the created task. Translate any `DQ-*` dependency to
   the actual Linear identifier assigned when that predecessor was created.
3. Record the assigned identifier beside the document key during the next
   queue-maintenance change. The document key remains stable even after the
   mapping is recorded.
4. Admit work only when every listed dependency is Done. Execution is
   sequential; every brief below has `Parallel Safe: no`.

This rule gives every future task a unique Linear identity without borrowing a
completed identifier or guessing which identifier Linear will assign.

## Dependency-Ordered Future Delivery

### DQ-01 — [Integration] private iMac/Tailscale deployment

- Linear ID: assigned at creation
- Goal: make the completed CEN-35 two-person topology operable on the owner's
  iMac as a private, recoverable service reached only over the tailnet.
- Primary Agent: `integration-agent`
- Inputs:
  - completed CEN-35 topology and migration behavior
  - completed CEN-43 queue rebase
  - `docs/product-spec.md`
  - `docs/domain-model.md`
  - `docs/api-contract.md`
  - `docs/local-runner.md`
- Done When:
  - the API and PostgreSQL have an iMac deployment configuration with durable
    storage, deterministic start/restart behavior, and secrets kept outside
    version control
  - the API is reachable from an allowlisted iPhone at the configured HTTPS
    Tailscale MagicDNS base URL, while PostgreSQL remains reachable only by the
    API
  - verification shows that no router port forwarding, public DNS, Funnel,
    internet-facing listener, public reverse proxy, or other public ingress is
    configured or required
  - deployment readiness rejects any configuration that does not contain
    exactly one owner and one partner Google subject with their normalized
    email guards
  - backup and restore are exercised against the deployed database, service
    health is verified after restart, and an operator runbook records setup,
    update, recovery, and private-connectivity checks
  - focused deployment tests or repeatable verification scripts cover service
    lifecycle, private reachability, absence of public exposure, and recovery
- Out of Scope:
  - Google ID-token exchange or iOS authentication implementation
  - Google Calendar scopes, tokens, data access, or synchronization
  - registration, generic invitations, invite acceptance, arbitrary users,
    membership administration, or role management
  - purchased domains, public ingress, Tailscale Funnel, hosted-only
    infrastructure, or Kubernetes
  - iOS offline cache or mutation replay
- Execution Mode: Sequential
- Parallel Safe: no
- Write Scope:
  - `deploy/**`
  - deployment-focused configuration and verification scripts
  - `docs/operator-runbook.md`
- Dependencies: CEN-35, CEN-43

### DQ-02 — [Backend] Google identity exchange and legacy auth retirement

- Linear ID: assigned at creation
- Primary Agent: `backend-agent`
- Done When:
  - `POST /v1/auth/google/exchange` validates the Google ID token and maps only
    the two configured subjects to revocable DayFlow sessions
  - Google access and refresh tokens are never requested or persisted
  - password registration/login and invite-acceptance endpoints are removed or
    disabled as migration targets
  - tests cover owner, partner, non-allowlisted, mismatched-email, invalid,
    expired, and deployment-not-ready exchanges
- Out of Scope:
  - Google Calendar access or synchronization
  - iOS authentication UI
  - new users, invitations, memberships, or roles
- Primary Inputs: `docs/domain-model.md`, `docs/api-contract.md`
- Execution Mode: Sequential
- Parallel Safe: no
- Write Scope: `services/api/**`
- Dependencies: CEN-35, DQ-01

### DQ-03 — [Backend] fixed calendar and owner-budget boundary

- Linear ID: assigned at creation
- Primary Agent: `backend-agent`
- Done When:
  - calendar and event endpoints expose only the caller's personal calendar and
    the provisioned household calendar
  - explicit personal-to-household copy and move preserve the privacy and
    atomicity rules in the API contract
  - owner budget endpoints authorize before resolving or serializing data
  - calendar creation, invite, membership, and role-management endpoints are
    absent
  - integration tests prove the partner cannot address owner budget data or
    either person's other personal calendar
- Out of Scope: iOS screens, offline cursor/outbox behavior, new product scope
- Primary Inputs: `docs/domain-model.md`, `docs/api-contract.md`
- Execution Mode: Sequential
- Parallel Safe: no
- Write Scope: `services/api/**`
- Dependencies: DQ-02

### DQ-04 — [Backend] idempotent offline and change-feed contract

- Linear ID: assigned at creation
- Primary Agent: `backend-agent`
- Done When:
  - supported event and owner-budget writes accept stable mutation IDs and the
    contract-required base versions
  - retries are idempotent and stale writes return explicit `409 conflict`
    responses with current authorized state
  - `/v1/sync/changes` returns authorized changes and tombstones by cursor
  - partner responses contain no budget data, identifiers, or placeholders
  - contract tests cover replay, conflict, deletion, explicit copy/move, and
    owner-only budget isolation
- Out of Scope: SwiftUI cache implementation, push, real-time collaboration
- Primary Inputs: `docs/api-contract.md`, `docs/sync-model.md`
- Execution Mode: Sequential
- Parallel Safe: no
- Write Scope:
  - `services/api/**`
  - only consistency corrections required by implementation in
    `docs/api-contract.md` or `docs/sync-model.md`
- Dependencies: DQ-03

### DQ-05 — [iOS] private Google auth and role-gated bootstrap

- Linear ID: assigned at creation
- Primary Agent: `ios-agent`
- Done When:
  - the app exchanges a Google ID token only with the configured HTTPS
    Tailscale MagicDNS API endpoint and stores only the DayFlow session
  - owner and partner bootstrap render the correct tabs, calendar scope, and
    budget-access boundary
  - password, registration, invite, and public-endpoint UI/configuration are
    absent
  - unauthorized identity, expired session, and unreachable iMac states are
    visible and tested
- Out of Scope: offline mutation replay, Google Calendar access, onboarding
- Primary Inputs: `docs/ios-architecture.md`, `docs/api-contract.md`
- Execution Mode: Sequential
- Parallel Safe: no
- Write Scope:
  - `apps/ios/DayFlow/**`
  - `apps/ios/DayFlowTests/**`
- Dependencies: DQ-01, DQ-02, DQ-03

### DQ-06 — [iOS] identity-partitioned offline cache and replay

- Linear ID: assigned at creation
- Primary Agent: `ios-agent`
- Done When:
  - cache, cursor, session, and outbox state are partitioned by identity and
    cleared on sign-out or account change
  - confirmed calendar data remains usable with visible pending overlays while
    the iMac is unavailable
  - mutations replay idempotently and conflicts require explicit user action
  - copy/move is limited to personal-to-household transfer
  - the partner has no budget DTO, request path, cache, outbox, or UI
- Out of Scope: Google Calendar sync, new calendar types, membership UI
- Primary Inputs: `docs/ios-architecture.md`, `docs/sync-model.md`
- Execution Mode: Sequential
- Parallel Safe: no
- Write Scope:
  - `apps/ios/DayFlow/**`
  - `apps/ios/DayFlowTests/**`
- Dependencies: DQ-04, DQ-05

### DQ-07 — [Integration] private two-role system E2E

- Linear ID: assigned at creation
- Primary Agent: `integration-agent`
- Done When:
  - owner and partner flows pass end to end on the two supported iPhones, an
    iOS Simulator where practical, and the iMac-hosted API over Tailscale
  - evidence proves MagicDNS-only remote transport and no public ingress
  - evidence covers personal/household calendar isolation, explicit copy/move,
    owner-only budget data, and absence of partner budget state
  - offline pending edits, reconnection replay, conflicts, identity cleanup,
    restart, backup, restore, and health verification are exercised
- Out of Scope: public beta, external identities, public network testing,
  Google Calendar synchronization, or new features
- Primary Inputs:
  - `docs/product-spec.md`
  - `docs/api-contract.md`
  - `docs/ios-architecture.md`
  - `docs/sync-model.md`
  - `docs/review-checklist.md`
  - `docs/operator-runbook.md`
- Execution Mode: Sequential
- Parallel Safe: no
- Write Scope:
  - integration test harnesses and fixtures
  - deployment verification evidence
  - `docs/operator-runbook.md`
- Dependencies: DQ-01, DQ-03, DQ-06

### DQ-08 — [Review] private cutover readiness

- Linear ID: assigned at creation
- Primary Agent: `review-agent`
- Done When:
  - review verifies exactly two Google identities, private MagicDNS-only
    transport, and no Google Calendar synchronization or public ingress
  - review verifies personal/household calendar boundaries, explicit copy/move,
    and owner-only budget data online and offline
  - iPhone, Simulator, iMac, restart, backup, restore, health, and recovery
    evidence satisfies the review checklist
  - legacy password, registration, login, invite, arbitrary membership, and
    public-ingress paths are removed or recorded as merge blockers
- Out of Scope: implementation, new product scope, or lifecycle automation
- Primary Inputs:
  - DQ-07 system evidence
  - `docs/review-checklist.md`
  - `docs/operator-runbook.md`
- Execution Mode: Sequential
- Parallel Safe: no
- Write Scope: review findings and readiness evidence only
- Dependencies: DQ-07

## Immediate Linear Task-Creation Handoff

Immediately after CEN-43 merges and is Done, create DQ-01, titled
`[Integration] private iMac/Tailscale deployment`. Let Linear assign its new
identifier, set CEN-35 and CEN-43 as completed blockers, use
`integration-agent`, and mark it sequential and not parallel-safe. Copy the
DQ-01 brief without adding public ingress, Google Calendar synchronization,
generic invitation, or application-feature scope.
