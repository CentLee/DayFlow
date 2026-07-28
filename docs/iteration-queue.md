# DayFlow Iteration Queue

This is the CEN-33 replacement queue. Create the listed Linear issues in order;
an issue is eligible only when every declared dependency is Done. Dispatch is
sequential unless an item explicitly says `Parallel Safe: yes`; none below does.

## Legacy CEN-24--CEN-27 Disposition

| Legacy issue | Disposition | CEN-33 mapping |
| --- | --- | --- |
| CEN-24 | Replace | CEN-34 defines and migrates the fixed two-person data topology. |
| CEN-25 | Replace | CEN-36 implements Google ID-token exchange and retires legacy password/public auth paths after the private deployment is available. |
| CEN-26 | Retain | Re-scope as CEN-37: preserve PostgreSQL work, but enforce fixed calendars and owner-budget privacy. |
| CEN-27 | Cancel | Invite, arbitrary shared-calendar, and public onboarding work conflicts with the target scope. |

## Dependency-Ordered Queue

### CEN-34 — [Backend] migrate fixed two-person data topology

- Primary Agent: `backend-agent`
- Inputs:
  - `docs/product-spec.md`
  - `docs/domain-model.md`
  - existing PostgreSQL schema and migrations
- Done When:
  - deployment configuration requires exactly one owner and one partner Google subject/email guard
  - migration preserves the two mapped user IDs and their personal calendars
  - one household calendar is provisioned and both mapped users are editors
  - owner expense-book data is retained and non-owner budget data is exported or quarantined
  - migration tests prove invalid or incomplete owner/partner topology leaves existing data unchanged and blocks deployment readiness
- Out of Scope:
  - Google token exchange endpoint
  - iOS UI or Tailscale host setup
- Execution Mode: Sequential
- Write Scope:
  - `services/api/migrations/**`
  - `services/api/internal/**`
  - `services/api/**/*_test.go`
- Dependencies: none

### CEN-35 — [Integration] deploy private Tailscale/iMac service

- Primary Agent: `integration-agent`
- Inputs:
  - `docs/product-spec.md`
  - `docs/api-contract.md`
  - `docs/local-runner.md`
  - completed CEN-34 topology migration
- Done When:
  - iMac Docker Compose service lifecycle, including a durable restart policy, is configured and verified
  - the API endpoint is configured on the iMac's Tailscale MagicDNS name and its binding is not publicly exposed
  - deployment verification confirms no router port forwarding or other public ingress is required or enabled
  - an iPhone connected to the tailnet verifies the operator path to the private API on the iMac
  - backup/restore and health checks are exercised, and an operator runbook records deployment, recovery, and verification steps
- Out of Scope:
  - Google identity exchange implementation
  - iOS authentication UI or offline client behavior
- Execution Mode: Sequential
- Write Scope:
  - `deploy/**`
  - `docs/operator-runbook.md`
  - deployment verification evidence only
- Dependencies: CEN-34

### CEN-36 — [Backend] implement Google identity exchange and retire legacy auth

- Primary Agent: `backend-agent`
- Inputs:
  - `docs/api-contract.md`
  - `docs/domain-model.md`
  - completed CEN-34 topology migration and CEN-35 private deployment
- Done When:
  - `POST /v1/auth/google/exchange` validates issuer, audience, signature, expiry, verified email, subject, and email guard
  - only the two configured subjects receive revocable opaque DayFlow sessions
  - no Google access or refresh token is persisted and no Google Calendar scope is requested
  - password/register/login and invite-acceptance routes are removed or disabled as migration targets
  - endpoint tests cover allowlisted, mismatched, malformed, and unready deployments
- Out of Scope:
  - iOS Google Sign-In UI
  - calendar or budget synchronization
- Execution Mode: Sequential
- Write Scope:
  - `services/api/**`
- Dependencies: CEN-34, CEN-35

### CEN-37 — [Backend] enforce fixed calendar and owner-budget boundaries

- Primary Agent: `backend-agent`
- Inputs:
  - `docs/domain-model.md`
  - `docs/api-contract.md`
  - completed CEN-36 authentication behavior
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
- Write Scope:
  - `services/api/**`
- Dependencies: CEN-36

### CEN-38 — [Integration] define offline reconciliation and conflict contract

- Primary Agent: `integration-agent`
- Inputs:
  - `docs/api-contract.md`
  - `docs/sync-model.md`
  - completed CEN-37 API behavior
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
- Write Scope:
  - `services/api/**`
  - `docs/api-contract.md`
  - `docs/sync-model.md`
- Dependencies: CEN-37

### CEN-39 — [iOS] implement Google authentication and bootstrap

- Primary Agent: `ios-agent`
- Inputs:
  - `docs/ios-architecture.md`
  - `docs/api-contract.md`
  - completed CEN-35 private deployment and CEN-36 authentication behavior
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
- Write Scope:
  - `apps/ios/DayFlow/**`
  - `apps/ios/DayFlowTests/**`
- Dependencies: CEN-35, CEN-36

### CEN-40 — [iOS] implement offline cache and explicit event transfer

- Primary Agent: `ios-agent`
- Inputs:
  - `docs/ios-architecture.md`
  - `docs/sync-model.md`
  - completed CEN-38 offline contract and CEN-39 bootstrap
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
- Write Scope:
  - `apps/ios/DayFlow/**`
  - `apps/ios/DayFlowTests/**`
- Dependencies: CEN-38, CEN-39

### CEN-41 — [Review] verify CEN-33 cutover

- Primary Agent: `review-agent`
- Inputs:
  - completed CEN-34 through CEN-40 PRs
  - `docs/review-checklist.md`
  - all six CEN-33 scoped documents
- Done When:
  - review verifies exactly two Google identities, private MagicDNS-only transport, and no Google Calendar synchronization
  - review verifies the iMac deployment has no public ingress and includes tested backup, restore, health-check, and operator-runbook evidence
  - review verifies personal/household calendar boundaries, explicit copy/move, and owner-only budget data
  - review verifies offline cache/reconciliation and conflict tests for both roles
  - legacy password/register/login/invite/public-ingress code paths are either removed or explicitly tracked as migration blockers
- Out of Scope:
  - feature implementation
  - new product scope
- Execution Mode: Sequential
- Write Scope:
  - review comments and PR evidence only
- Dependencies: CEN-40
