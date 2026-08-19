# DayFlow Delivery Queue

This queue corrects the reviewed CEN-43 proposal. It separates completed
Linear history from future delivery and makes every future brief directly
copyable into a runner-admissible Linear issue.

The product baseline remains fixed: one owner, one partner, two allowlisted
Google identities, one personal calendar each, one household calendar,
owner-only budget data, and private iMac access through Tailscale MagicDNS.
Google Calendar sync, generic invitations, arbitrary membership, and public
ingress are not delivery options.

The Excel workbook remains a read-only product-design reference for the
monthly board interaction and KPI formulas. It is not an application input or
delivery artifact.

## Completed Linear History

The following identifiers are closed history and must not be reused or
reopened:

| Linear issue | Completed scope |
| --- | --- |
| CEN-34 | Aligned the local runner with the Terra policy and established the cutover execution base. |
| CEN-35 | Completed and reviewed the fixed two-person topology on its stacked topology branch. |
| CEN-36 | Corrected cached-context accounting in the runner. |
| CEN-37 | Prevented finalized lifecycle records from being dispatched again. |
| CEN-38 | Excluded auxiliary state artifacts from issue execution. |
| CEN-39 | Hardened runner publication admission. |
| CEN-40 | Bounded runner token budgets. |
| CEN-41 | Preserved stacked completed worktrees. |
| CEN-42 | Made context-budget observations non-blocking. |
| CEN-43 | Proposed the delivery-queue rebase reviewed and corrected by CEN-44. |
| CEN-44 | Corrects the reviewed delivery queue represented by this document. |

The CEN-35 topology commit `7337c1d576a4b370cc1b43baf0444daef1d9ecd9`
is on `origin/integration/private-two-person-cutover`; it is not an ancestor of
`origin/develop`. A Done Linear state therefore does not make its code a valid
prerequisite for a runner branch based on `origin/develop`. DQ-01 is the
required delivery bridge and deliberately depends only on CEN-44.

The prior CEN-24 through CEN-27 plan remains superseded or cancelled. Its
private deployment, authentication, calendar, budget, offline, and cutover
intent is represented only by the future briefs below. Its public onboarding,
generic invitation, and arbitrary sharing intent remains cancelled.

## Future Identifier and Admission Rule

`DQ-01` through `DQ-12` are stable document keys, not Linear identifiers. For
each brief:

1. Create only the earliest uncreated eligible brief and let Linear assign a
   new, unique `CEN-*` identifier. Never predict, renumber, or recycle an ID.
2. Copy the text from `Goal` through `Dependencies` into the Linear issue.
   Use the bracketed agent title after the document key as its issue title.
3. Translate each `DQ-*` dependency to the actual Linear identifier assigned
   to that predecessor. Keep completed `CEN-*` dependencies unchanged.
4. Record the assigned identifier beside the stable document key during the
   next queue-maintenance change.
5. Admit work only when every dependency is Done. Execution is sequential and
   every brief has `Parallel Safe: no`.

## Dependency-Ordered Future Delivery

### DQ-01 — [Integration] deliver reviewed two-person topology to develop

Linear ID: assigned at creation

Goal:
- Reconcile the reviewed CEN-35 topology delta onto the runner's
  `origin/develop` delivery base without importing unrelated stacked history.

Primary Agent:
- `integration-agent`

Inputs:
- `origin/develop`
- `origin/integration/private-two-person-cutover`
- topology commit `7337c1d576a4b370cc1b43baf0444daef1d9ecd9`
- `docs/product-spec.md`
- `docs/domain-model.md`

Done When:
- the application, migration, and system-Compose topology delta from the named
  commit is reconciled onto a branch created from `origin/develop`, without
  importing unrelated runner or documentation commits from the stacked branch
- deployment configuration requires exactly one owner and one partner Google
  subject with normalized-email guards
- migration preserves the mapped user IDs and personal calendars, provisions
  one household calendar with both users as editors, and preserves only the
  owner's expense-book data
- invalid or incomplete topology configuration leaves existing data unchanged
  and blocks deployment readiness
- focused migration, API, and system tests pass on the reconciled delivery base

Out of Scope:
- private iMac deployment or public-ingress changes
- Google token exchange or iOS implementation
- unrelated harness or documentation history from the stacked branch

One PR Scope:
- Deliver only the reviewed CEN-35 topology delta and its focused tests from a
  branch based on `origin/develop`.

Execution Mode:
- Sequential

Parallel Safe:
- no

Write Scope:
- `services/api/**`
- `infra/docker/docker-compose.system.yml`

Dependencies:
- CEN-44

### DQ-02 — [Integration] add private iMac and Tailscale deployment

Linear ID: assigned at creation

Goal:
- Make the delivered two-person topology operable on the owner's iMac through
  a recoverable Tailscale MagicDNS path while retaining any legacy ingress only
  as a time-bounded rollback path until the iOS cutover gate.

Primary Agent:
- `integration-agent`

Inputs:
- DQ-01 delivered topology
- `docs/product-spec.md`
- `docs/api-contract.md`
- `docs/local-runner.md`

Done When:
- the API and PostgreSQL have an iMac deployment configuration with durable
  storage, deterministic restart behavior, and secrets outside version control
- an allowlisted iPhone reaches the API at the configured HTTPS Tailscale
  MagicDNS base URL while PostgreSQL remains reachable only by the API
- the private path requires no new public DNS, router forwarding, Funnel,
  public reverse proxy, or internet-facing listener
- backup, restore, restart, health, and private-connectivity checks are
  repeatable and recorded in the operator runbook
- any existing legacy public ingress is documented as rollback-only and is not
  removed by this brief

Out of Scope:
- Google ID-token exchange or iOS authentication
- removal of legacy ingress or rollback data
- Google Calendar synchronization or hosted-only infrastructure

One PR Scope:
- Add and verify the private iMac deployment path and its operator evidence.

Execution Mode:
- Sequential

Parallel Safe:
- no

Write Scope:
- `deploy/**`
- `scripts/tests/deployment/**`
- `docs/operator-runbook.md`

Dependencies:
- DQ-01

### DQ-03 — [Backend] add Google identity exchange beside legacy auth

Linear ID: assigned at creation

Goal:
- Add the two-subject Google ID-token exchange and DayFlow sessions without
  retiring the legacy authentication or invite paths before iOS cutover.

Primary Agent:
- `backend-agent`

Inputs:
- `docs/domain-model.md`
- `docs/api-contract.md`
- DQ-01 delivered topology
- DQ-02 private deployment path

Done When:
- `POST /v1/auth/google/exchange` validates issuer, audience, signature,
  expiry, verified email, subject, and normalized-email guard
- only the configured owner and partner subjects receive revocable opaque
  DayFlow sessions
- Google access and refresh tokens are neither requested nor persisted
- legacy password, registration, login, and invite-acceptance paths remain
  available only for rollback and are not used by replacement sessions
- focused tests cover both allowed roles, rejection cases, expiry, revocation,
  and deployment-not-ready behavior

Out of Scope:
- iOS Google Sign-In UI
- retirement of any legacy route, secret, client, or public ingress
- Google Calendar access or synchronization

One PR Scope:
- Add the replacement backend authentication path and its tests while leaving
  rollback paths intact.

Execution Mode:
- Sequential

Parallel Safe:
- no

Write Scope:
- `services/api/**`

Dependencies:
- DQ-02

### DQ-04 — [Backend] enforce fixed calendar and owner-budget boundaries

Linear ID: assigned at creation

Goal:
- Implement the replacement session's fixed calendar and owner-budget API
  boundary without prematurely deleting legacy creation or membership routes.

Primary Agent:
- `backend-agent`

Inputs:
- `docs/domain-model.md`
- `docs/api-contract.md`
- DQ-03 replacement authentication behavior

Done When:
- replacement sessions see only the caller's personal calendar and the
  provisioned household calendar
- event CRUD and explicit personal-to-household copy or move enforce the fixed
  topology and atomicity rules
- owner budget endpoints authorize before resolving or serializing data, and
  partner responses contain no budget fields or placeholders
- legacy invite, calendar-creation, membership, and role-management routes are
  inaccessible to replacement sessions but remain rollback-only until cutover
- integration tests prove personal-calendar isolation and owner-only budget
  access for both roles

Out of Scope:
- deletion of legacy routes or data
- iOS screens or offline cursor and outbox behavior
- additional calendar kinds, roles, or sharing models

One PR Scope:
- Implement and test only the fixed replacement-session calendar and budget
  boundary.

Execution Mode:
- Sequential

Parallel Safe:
- no

Write Scope:
- `services/api/**`

Dependencies:
- DQ-03

### DQ-05 — [Backend] add idempotent offline and change-feed contract

Linear ID: assigned at creation

Goal:
- Implement the agreed offline mutation and authorized change-feed behavior
  for the fixed two-person API.

Primary Agent:
- `backend-agent`

Inputs:
- `docs/api-contract.md`
- `docs/sync-model.md`
- DQ-04 fixed-boundary behavior

Done When:
- supported event and owner-budget writes accept stable mutation IDs and the
  required base versions
- retries are idempotent and stale writes return `409 conflict` with current
  authorized state
- `/v1/sync/changes` returns authorized changes and tombstones by cursor
- partner responses contain no budget data, identifiers, or placeholders
- contract tests cover replay, conflict, deletion, transfer, and owner-only
  budget isolation

Out of Scope:
- SwiftUI cache implementation
- push notifications or real-time collaboration
- changes to the fixed sharing or privacy model

One PR Scope:
- Implement the server-side offline mutation and change-feed contract with
  focused contract tests.

Execution Mode:
- Sequential

Parallel Safe:
- no

Write Scope:
- `services/api/**`
- `docs/api-contract.md`
- `docs/sync-model.md`

Dependencies:
- DQ-04

### DQ-06 — [iOS] complete replacement authentication cutover gate

Linear ID: assigned at creation

Goal:
- Ship and verify the replacement Google-authenticated iOS bootstrap on both
  supported roles before any legacy client, server, or ingress path is retired.

Primary Agent:
- `ios-agent`

Inputs:
- `docs/ios-architecture.md`
- `docs/api-contract.md`
- DQ-02 private deployment path
- DQ-03 replacement authentication behavior
- DQ-04 fixed calendar and budget boundary

Done When:
- the replacement client exchanges Google ID tokens only with the configured
  HTTPS Tailscale MagicDNS API and stores only the DayFlow session
- owner and partner bootstrap render the correct tabs, calendar scope, and
  budget-access boundary without calling legacy invite, creation, or membership
  paths
- unauthorized identity, expired session, and unreachable-iMac states are
  visible and covered by focused tests
- evidence from both supported roles marks the
  `replacement-ios-auth-cutover` gate complete while legacy client, server, and
  ingress rollback paths remain intact

Out of Scope:
- removal of legacy UI, server routes, secrets, or public ingress
- offline mutation replay
- Google Calendar access, generic onboarding, or additional users

One PR Scope:
- Add and verify the replacement iOS authentication and bootstrap path through
  the explicit cutover gate, without legacy retirement.

Execution Mode:
- Sequential

Parallel Safe:
- no

Write Scope:
- `apps/ios/DayFlow/**`
- `apps/ios/DayFlowTests/**`
- `docs/evidence/ios-auth-cutover/**`

Dependencies:
- DQ-02
- DQ-03
- DQ-04

### DQ-07 — [iOS] add identity-partitioned offline cache and replay

Linear ID: assigned at creation

Goal:
- Make the replacement client useful during iMac downtime while preserving
  identity and owner-budget privacy boundaries.

Primary Agent:
- `ios-agent`

Inputs:
- `docs/ios-architecture.md`
- `docs/sync-model.md`
- DQ-05 offline server contract
- DQ-06 replacement iOS authentication gate

Done When:
- cache, cursor, session, and outbox state are partitioned by identity and
  cleared on sign-out or account change
- confirmed calendar data remains usable with visible pending overlays while
  the iMac is unavailable
- mutations replay idempotently, conflicts require explicit user action, and
  copy or move is limited to personal-to-household transfer
- the partner has no budget DTO, request path, cache, outbox, or UI
- focused tests cover replay, conflicts, identity changes, and partner privacy

Out of Scope:
- Google Calendar synchronization
- new calendar types, memberships, or sharing UI
- server or ingress retirement

One PR Scope:
- Implement the replacement client's identity-partitioned cache and offline
  replay behavior with focused tests.

Execution Mode:
- Sequential

Parallel Safe:
- no

Write Scope:
- `apps/ios/DayFlow/**`
- `apps/ios/DayFlowTests/**`

Dependencies:
- DQ-05
- DQ-06

### DQ-08 — [Backend] retire legacy auth and sharing routes after cutover

Linear ID: assigned at creation

Goal:
- Retire legacy authentication, invitation, calendar-creation, membership, and
  role-management server paths only after the replacement iOS cutover gate and
  offline client are complete.

Primary Agent:
- `backend-agent`

Inputs:
- DQ-06 `replacement-ios-auth-cutover` evidence
- DQ-07 replacement client behavior
- `docs/product-spec.md`
- `docs/api-contract.md`

Done When:
- the completed replacement-iOS cutover evidence is verified before any
  destructive migration or route removal runs
- password registration, password login, invite creation or acceptance,
  arbitrary calendar creation, membership changes, and role changes are absent
- password hashes, invite secrets, and obsolete delivery fields are removed
  only after rollback data is retained for the operator-defined window
- endpoint and migration tests prove replacement owner and partner sessions
  continue to work and retired routes cannot be reached

Out of Scope:
- public-ingress configuration removal
- iOS legacy UI removal
- changes to replacement auth, calendar, budget, or offline behavior

One PR Scope:
- Remove the legacy server routes and secrets gated by recorded replacement
  client cutover evidence.

Execution Mode:
- Sequential

Parallel Safe:
- no

Write Scope:
- `services/api/**`

Dependencies:
- DQ-06
- DQ-07

### DQ-09 — [Integration] retire legacy public ingress after cutover

Linear ID: assigned at creation

Goal:
- Remove the rollback-only public ingress after replacement iOS cutover and
  legacy server-route retirement have been verified.

Primary Agent:
- `integration-agent`

Inputs:
- DQ-02 private deployment and recovery evidence
- DQ-06 `replacement-ios-auth-cutover` evidence
- DQ-08 server retirement evidence
- `docs/operator-runbook.md`

Done When:
- the replacement-iOS cutover gate, private MagicDNS path, backup, restore,
  restart, and health evidence are verified before ingress removal
- public DNS, router forwarding, Funnel, public reverse proxy, tunnel, and
  internet-facing listener configuration are absent
- both supported roles reach the iMac only through the configured Tailscale
  MagicDNS API path after restart
- the operator runbook records the final private-only topology and retained
  rollback data without retaining an executable public path

Out of Scope:
- backend route or iOS client changes
- hosted failover, purchased domains, or Kubernetes
- removal of operator-approved rollback data

One PR Scope:
- Remove and verify only the legacy public-ingress configuration and update its
  operator evidence.

Execution Mode:
- Sequential

Parallel Safe:
- no

Write Scope:
- `deploy/**`
- `scripts/tests/deployment/**`
- `docs/operator-runbook.md`

Dependencies:
- DQ-08

### DQ-10 — [iOS] retire the legacy authentication client

Linear ID: assigned at creation

Goal:
- Remove the legacy iOS authentication and onboarding client paths after the
  replacement cutover gate and corresponding server and ingress retirements.

Primary Agent:
- `ios-agent`

Inputs:
- DQ-06 `replacement-ios-auth-cutover` evidence
- DQ-08 server retirement behavior
- DQ-09 private-only deployment evidence
- `docs/ios-architecture.md`

Done When:
- password, registration, invite, legacy endpoint, and public-base-URL UI or
  configuration are absent from the iOS target
- only Google ID-token exchange through the configured Tailscale MagicDNS base
  URL can establish a DayFlow session
- owner and partner tests cover launch, authentication, bootstrap, expiry, and
  unreachable-iMac behavior after legacy removal

Out of Scope:
- server or deployment changes
- new onboarding, identities, roles, or calendar types
- Google Calendar access or synchronization

One PR Scope:
- Remove only the legacy iOS authentication/onboarding client and prove the
  replacement path remains complete.

Execution Mode:
- Sequential

Parallel Safe:
- no

Write Scope:
- `apps/ios/DayFlow/**`
- `apps/ios/DayFlowTests/**`

Dependencies:
- DQ-08
- DQ-09

### DQ-11 — [Integration] verify the private two-role system end to end

Linear ID: assigned at creation

Goal:
- Prove the completed private system works for both roles online, offline, and
  through recovery with every legacy path retired.

Primary Agent:
- `integration-agent`

Inputs:
- DQ-07 replacement offline client
- DQ-08 server retirement
- DQ-09 private-only deployment
- DQ-10 legacy iOS client retirement
- `docs/review-checklist.md`
- `docs/operator-runbook.md`

Done When:
- owner and partner flows pass on both supported iPhones, an iOS Simulator
  where practical, and the iMac-hosted API over Tailscale
- evidence proves MagicDNS-only remote transport, no public ingress, and no
  legacy client or server path
- evidence covers calendar isolation, explicit transfer, owner-only budget
  data, and absence of partner budget state online and offline
- pending edits, replay, conflict handling, identity cleanup, restart, backup,
  restore, health, and recovery are exercised

Out of Scope:
- public beta, external identities, or public network testing
- Google Calendar synchronization
- new features or lifecycle automation

One PR Scope:
- Add only the bounded E2E harness, fixtures, and evidence needed to verify the
  completed private two-role system.

Execution Mode:
- Sequential

Parallel Safe:
- no

Write Scope:
- `scripts/tests/integration/**`
- `docs/evidence/private-cutover/**`
- `docs/operator-runbook.md`

Dependencies:
- DQ-07
- DQ-08
- DQ-09
- DQ-10

### DQ-12 — [Review] verify private cutover readiness

Linear ID: assigned at creation

Goal:
- Decide whether the private two-role system is merge-ready against the product
  baseline and review checklist.

Primary Agent:
- `review-agent`

Inputs:
- DQ-11 system evidence
- `docs/product-spec.md`
- `docs/review-checklist.md`
- `docs/operator-runbook.md`

Done When:
- review verifies exactly two Google identities, MagicDNS-only transport, no
  Google Calendar synchronization, and no public ingress
- review verifies personal and household calendar boundaries, explicit
  transfer, and owner-only budget data online and offline
- iPhone, Simulator, iMac, restart, backup, restore, health, and recovery
  evidence satisfies the review checklist
- legacy password, registration, login, invite, calendar-creation, membership,
  client, and public-ingress paths are absent or recorded as merge blockers

Out of Scope:
- implementation or remediation
- new product scope
- lifecycle automation or reopening completed issues

One PR Scope:
- Produce only the review findings and readiness evidence for the completed
  private cutover.

Execution Mode:
- Sequential

Parallel Safe:
- no

Write Scope:
- `docs/reviews/private-cutover.md`

Dependencies:
- DQ-11

## Immediate Linear Task-Creation Handoff

After CEN-44 merges and is Done, create DQ-01 with title
`[Integration] deliver reviewed two-person topology to develop`. Let Linear
assign a new identifier, set only CEN-44 as its completed blocker, and copy the
brief exactly. Its runner branch must start at `origin/develop`; the named
CEN-35 commit is a reviewed source delta, not an assumed ancestor or completed
code prerequisite.
