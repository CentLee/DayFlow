# DayFlow Iteration Queue

This is the CEN-33 replacement queue. Create the listed Linear issues in order;
an issue is eligible only when every declared dependency is Done. Dispatch is
sequential unless an item explicitly says `Parallel Safe: yes`; none below does.

The Excel workbook is a read-only product-design reference for the monthly
board interaction and KPI formulas. It is not an application input or delivery
artifact for any issue in this queue.

## Legacy CEN-24--CEN-27 Disposition

| Legacy issue | Disposition | Replacement mapping |
| --- | --- | --- |
| CEN-24 | Supersede | CEN-34 establishes the runner-model policy needed to execute the replacement cutover safely. |
| CEN-25 | Supersede | CEN-35 through CEN-37 replace the topology, private deployment, and authentication cutover work with the fixed two-person scope. |
| CEN-26 | Supersede | CEN-38 replaces its calendar and budget work with explicit fixed-boundary enforcement. |
| CEN-27 | Cancel | Invite, arbitrary shared-calendar, and public onboarding work conflict with the target scope. |

## Dependency-Ordered Queue

### CEN-34 — [Integration] Terra runner model policy

- Primary Agent: `integration-agent`
- Inputs:
  - `docs/product-spec.md`
  - `docs/local-runner.md`
  - `docs/automation-model.md`
  - `docs/iteration-queue.md`
- Done When:
  - the local Terra runner policy assigns the smallest valid agent scope and sequential dependency admission for CEN-35 through CEN-43
  - the policy records the required proof-of-work, test, privacy, and deployment-evidence handoffs for backend, iOS, integration, and review work
  - runner configuration does not create a resident service, public control plane, public ingress, or hosted-only dependency
  - the policy identifies Tailscale/iMac verification, backup/runbook evidence, and two-role privacy checks as required cutover gates
- Out of Scope:
  - application feature implementation
  - deployment changes or external service provisioning
- Execution Mode: Sequential
- Parallel Safe: no
- Write Scope:
  - `.codex/agents/**`
  - `.codex/skills/**`
  - `docs/local-runner.md`
  - `docs/automation-model.md`
- Dependencies: none

### CEN-35 — [Backend] fixed two-person data topology

- Primary Agent: `backend-agent`
- Inputs:
  - `docs/product-spec.md`
  - `docs/domain-model.md`
  - existing PostgreSQL schema and migrations
  - completed CEN-34 runner policy
- Done When:
  - deployment configuration requires exactly one owner and one partner Google subject with normalized-email guard
  - migration preserves the two mapped user IDs and their personal calendars
  - one household calendar is provisioned and both mapped users are editors
  - owner expense-book data is retained and non-owner budget data is exported or quarantined for operator review
  - migration tests prove invalid or incomplete owner/partner topology leaves existing data unchanged and blocks deployment readiness
- Out of Scope:
  - Google token exchange endpoint
  - iOS UI, offline behavior, or Tailscale host setup
- Execution Mode: Sequential
- Parallel Safe: no
- Write Scope:
  - `services/api/migrations/**`
  - `services/api/internal/**`
  - `services/api/**/*_test.go`
- Dependencies: CEN-34

### CEN-36 — [Integration] private Tailscale/iMac deployment

- Primary Agent: `integration-agent`
- Inputs:
  - `docs/product-spec.md`
  - `docs/api-contract.md`
  - `docs/local-runner.md`
  - completed CEN-35 topology migration
- Done When:
  - iMac Docker Compose service lifecycle, including durable restart policy, is configured and verified
  - the API is configured on the iMac's Tailscale MagicDNS name and is not publicly exposed
  - deployment verification confirms no router port forwarding, public DNS, reverse proxy, tunnel, or other public ingress is required or enabled
  - an iPhone connected to the tailnet verifies the private API path to the iMac
  - backup, restore, and health checks are exercised, and an operator runbook records deployment, recovery, and verification steps
- Out of Scope:
  - Google identity exchange implementation
  - iOS authentication UI or offline client behavior
- Execution Mode: Sequential
- Parallel Safe: no
- Write Scope:
  - `deploy/**`
  - `docs/operator-runbook.md`
  - deployment verification evidence only
- Dependencies: CEN-35

### CEN-37 — [Backend] Google ID-token exchange and legacy auth retirement

- Primary Agent: `backend-agent`
- Inputs:
  - `docs/api-contract.md`
  - `docs/domain-model.md`
  - completed CEN-35 topology migration and CEN-36 private deployment
- Done When:
  - `POST /v1/auth/google/exchange` validates issuer, audience, signature, expiry, verified email, subject, and email guard
  - only the two configured subjects receive revocable opaque DayFlow sessions
  - no Google access or refresh token is persisted and no Google Calendar scope is requested
  - password/register/login and invite-acceptance routes are removed or disabled as migration targets
  - endpoint tests cover allowlisted, mismatched, malformed, expired, and unready deployments
- Out of Scope:
  - iOS Google Sign-In UI
  - calendar or budget synchronization
- Execution Mode: Sequential
- Parallel Safe: no
- Write Scope:
  - `services/api/**`
- Dependencies: CEN-35, CEN-36

### CEN-38 — [Backend] fixed calendar and owner-budget boundary

- Primary Agent: `backend-agent`
- Inputs:
  - `docs/domain-model.md`
  - `docs/api-contract.md`
  - completed CEN-37 authentication behavior
- Done When:
  - calendar list returns only the caller's personal calendar plus the pre-provisioned household calendar
  - event CRUD and explicit personal-to-household copy/move enforce the fixed topology
  - owner budget endpoints authorize before resolving or serializing budget data
  - calendar, invite, membership-creation, and role-management endpoints are absent
  - integration tests prove the partner cannot address owner budget or either person's other personal calendar
- Out of Scope:
  - iOS screens
  - offline cursor and outbox protocol
- Execution Mode: Sequential
- Parallel Safe: no
- Write Scope:
  - `services/api/**`
- Dependencies: CEN-37

### CEN-39 — [Integration] offline contract

- Primary Agent: `integration-agent`
- Inputs:
  - `docs/api-contract.md`
  - `docs/sync-model.md`
  - completed CEN-38 API behavior
- Done When:
  - event and owner-budget writes accept stable client mutation IDs and required base versions
  - repeated mutations are idempotent and stale writes return current resources with `409 conflict`
  - authorized `/v1/sync/changes` cursors include event tombstones and owner-only budget changes
  - partner feeds and caches contain no budget data, identifiers, or placeholders
  - contract tests cover offline replay, move atomicity, deletion tombstones, and budget conflict handling
- Out of Scope:
  - SwiftUI cache implementation
  - push or real-time collaboration
- Execution Mode: Sequential
- Parallel Safe: no
- Write Scope:
  - `services/api/**`
  - `docs/api-contract.md`
  - `docs/sync-model.md`
- Dependencies: CEN-38

### CEN-40 — [iOS] Google auth/bootstrap

- Primary Agent: `ios-agent`
- Inputs:
  - `docs/ios-architecture.md`
  - `docs/api-contract.md`
  - completed CEN-36 private deployment and CEN-37 authentication behavior
- Done When:
  - app exchanges Google ID tokens only with the configured Tailscale MagicDNS API endpoint
  - owner and partner bootstrap render their correct tab sets and calendar scopes
  - legacy password/register/invite/public-endpoint UI and configuration are removed
  - unauthorized, expired-session, and unreachable-iMac states are visible
  - iOS tests cover owner/partner routing and no partner budget request
- Out of Scope:
  - offline mutation replay
  - calendar editor polish
- Execution Mode: Sequential
- Parallel Safe: no
- Write Scope:
  - `apps/ios/DayFlow/**`
  - `apps/ios/DayFlowTests/**`
- Dependencies: CEN-36, CEN-37

### CEN-41 — [iOS] offline cache/explicit transfer

- Primary Agent: `ios-agent`
- Inputs:
  - `docs/ios-architecture.md`
  - `docs/sync-model.md`
  - completed CEN-39 offline contract and CEN-40 bootstrap
- Done When:
  - cache, cursor, and outbox are partitioned by DayFlow identity and cleared on sign-out or account change
  - calendar events render from confirmed cache with visibly pending overlays while the iMac is unavailable
  - client replays idempotent mutations and exposes explicit event/budget conflict resolution
  - personal events can only be copied or moved explicitly to the household calendar
  - partner build has no budget cache, outbox, request path, or UI
- Out of Scope:
  - additional calendar types or membership UI
  - Google Calendar synchronization
- Execution Mode: Sequential
- Parallel Safe: no
- Write Scope:
  - `apps/ios/DayFlow/**`
  - `apps/ios/DayFlowTests/**`
- Dependencies: CEN-39, CEN-40

### CEN-42 — [Integration] private two-role system E2E

- Primary Agent: `integration-agent`
- Inputs:
  - completed CEN-35 through CEN-41 work
  - `docs/product-spec.md`
  - `docs/review-checklist.md`
  - `docs/operator-runbook.md`
- Done When:
  - owner and partner flows pass end-to-end on an iPhone, iOS Simulator, and the iMac-hosted service over Tailscale
  - evidence shows the iPhone and Simulator use the iMac's MagicDNS API path with no public ingress
  - evidence verifies private and household calendar boundaries, explicit copy/move, owner-only budget isolation, and no partner budget cache or request
  - evidence verifies offline pending edits, reconnection replay, conflict handling, and identity-cache clearing for both roles
  - backup/restore, health-check, and operator-runbook recovery evidence is current for the private deployment
- Out of Scope:
  - public beta, external users, or public network testing
  - new product scope
- Execution Mode: Sequential
- Parallel Safe: no
- Write Scope:
  - integration test harnesses and fixtures
  - deployment verification evidence
  - `docs/operator-runbook.md`
- Dependencies: CEN-35, CEN-36, CEN-37, CEN-38, CEN-39, CEN-40, CEN-41

### CEN-43 — [Review] cutover

- Primary Agent: `review-agent`
- Inputs:
  - completed CEN-34 through CEN-42 PRs
  - `docs/review-checklist.md`
  - CEN-42 private-system evidence
- Done When:
  - review verifies exactly two Google identities, private MagicDNS-only transport, and no Google Calendar synchronization
  - review verifies no public ingress and includes tested backup, restore, health-check, and operator-runbook evidence
  - review verifies personal/household calendar boundaries, explicit copy/move, and owner-only budget data online and offline
  - review verifies iPhone, Simulator, and iMac Tailscale evidence for both roles
  - legacy password/register/login/invite/public-ingress code paths are removed or explicitly tracked as merge blockers
- Out of Scope:
  - feature implementation
  - new product scope
- Execution Mode: Sequential
- Parallel Safe: no
- Write Scope:
  - review comments and PR evidence only
- Dependencies: CEN-42
