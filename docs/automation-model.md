# DayFlow Automation Model

## Summary

DayFlow uses semi-automated delivery.

The automation model assumes a global harness skill layer in `~/.codex/skills` plus a thin
DayFlow-specific layer in this repository.

Automatic:

- Linear issue detection
- issue admission validation for required metadata before repeated pickup
- issue workspace creation
- Codex execution
- branch and PR creation
- CI result collection
- PR-to-Linear state reconciliation
- review finding to draft / `Todo` reconciliation
- active workspace ownership to `In Progress` reconciliation
- issue branch bootstrap for fresh `Todo` workspaces that are still on `develop`
- post-run outcome validation for stale in-progress work without PR closure
- proof-of-work refresh for open develop-targeted PRs
- branch-bootstrap stall recovery for fresh workspaces that never leave `develop`
- low-token workflow defaults through shallow clone, reduced turn budget, and tighter stall/turn timeouts

Manual:

- large spec changes
- merge approval
- secret provisioning
- blocked issue resolution

## Roles

### Symphony

- polls Linear
- creates issue workspaces
- launches `codex app-server`
- collects branch, PR, and CI output

DayFlow runs Symphony in one lifecycle-owner lane:

- lifecycle-owner lane: `Todo`

### dayflow-orchestrator

- routes work to the correct agent path
- enforces DayFlow handoff rules
- keeps multi-agent issues sequential
- advances the queue only after the current issue owner has either closed the review loop or marked the issue blocked

### Project Agents

- `product-agent`
- `backend-agent`
- `ios-agent`
- `integration-agent`
- `review-agent`

## State Machine

### Todo

- runnable queue state
- new work enters here
- retries also re-enter here

### In Progress

- workspace exists
- Codex is actively working the issue or the last implementation attempt has completed
- not directly runnable by Symphony

### In Review

- PR is open and ready for review
- fresh blocking findings should push the issue back to `Todo`

### Blocked

- external approvals or missing details prevent progress

### Done

- changes merged
- follow-up issues created if needed

## Admission Criteria

An issue is auto-runnable only if:

- title follows `[Agent] short task description`
- `Primary Agent` is exactly one value
- `Inputs` references specific docs or files
- `Done When` has 2 to 5 concrete checks
- `Out of Scope` is filled in
- the work should land in one PR

If the workspace has a `Blocked` state configured, malformed `Todo` issues should be moved there instead of being retried indefinitely.

## Issue Granularity Policy

Default policy:

- one primary agent
- one issue-sized outcome

Vertical slice exception:

- allowed only for small user-facing changes
- must already have stable contracts
- must remain a single PR
- handoffs are sequential

## Handoff Policy

### Default

- Primary Agent owns the branch and completes the scoped work
- Primary Agent remains responsible for the issue until it is merge-ready, including review-follow-up commits on the same branch
- The first Git action in any workspace is creating or switching to `feature/tasks-<issue-number>-<short-slug>`
- `main` is the release branch and `develop` is the integration branch
- agent implementation never happens directly on `main` or `develop`
- issue branches start from `develop`
- issue PRs target `develop` and should normally use squash merge
- `develop` moves to `main` only after human-reviewed stabilization
- Review Agent provides the review standard, but review follow-up returns to the same primary owner

### Vertical Slice

1. Primary Agent performs the first implementation step
2. Integration validation happens if contracts changed
3. Secondary implementation step happens if needed
4. Review Agent performs final validation

## Review Policy

All PRs must answer:

- does this conflict with `docs/product-spec.md`?
- does this drift from `docs/api-contract.md`?
- does this cross private budget data boundaries?
- are tests missing for behavior changes?
- does this add non-MVP complexity?

## State Reconciliation Rules

DayFlow now enforces these automatic state transitions:

- no PR: issue stays in `Todo` before pickup, then becomes `In Progress` while owned
- branch creation alone does not count as ownership; a dirty diff or `HEAD != origin/develop` is required
- open draft PR: issue stays in `In Progress`
- open ready-for-review PR: issue moves to `In Review`
- ready PR with fresh review findings: PR returns to draft and issue returns to `Todo`
- merged PR: issue moves to `Done`
- stale `In Progress` work with no diff and no branch advancement returns to `Todo`
- stale `In Progress` work with commits but no PR is preserved in `In Progress` for manual follow-up instead of being silently retried
- the same issue owner resumes work after review findings

The reconciliation source of truth is the issue branch name:

- `feature/tasks-9-...` maps to `CEN-9`
- legacy `codex/9-...` or `codex/CEN-9-...` remains supported for older in-flight workspaces

Automation scripts:

- `scripts/sync_linear_pr_states.sh`
- `scripts/reconcile_issue_ownership.sh`
- `scripts/reconcile_review_feedback.sh`
- `scripts/bootstrap_issue_branches.sh`
- `scripts/validate_issue_outcomes.sh`
- `scripts/guard_branch_bootstrap_stalls.sh`
- `scripts/collect_pr_proof.sh`
- `scripts/update_pr_proof.sh`
- `scripts/run_symphony.sh`

## Token Budget Controls

DayFlow keeps Symphony on a tighter token budget than the upstream defaults:

- shallow clone in `hooks.after_create`
- `agent.max_turns` reduced from the upstream default of `20` to `5`
- `codex.stall_timeout_ms` reduced from the upstream default of `300000` to `90000`
- `codex.turn_timeout_ms` reduced from the upstream default of `3600000` to `420000`
- generated build artifacts are treated as noise unless a task explicitly requires them

These controls are intended to stop long, low-yield runs early and keep issue retries cheap.

Additional guardrails:

- fresh workspaces are not treated as bootstrap stalls during the initial runtime warm-up window
- branch-bootstrap stalls must remain clean and still match `origin/develop` before being recovered
- requested-changes handling should rely on structured GitHub review state rather than comment text heuristics
- a locally paused issue must be moved out of the runnable `Todo` queue state before the next dispatch cycle
- when a guard pauses or blocks an active issue, the harness must stop the active Symphony/Codex process tree instead of waiting for the run to end on its own

## Branch and Workspace Naming

- branch: `feature/tasks-<issue-number>-<short-slug>` preferred
- legacy `codex/<issue-number>-<short-slug>` and `codex/<issue-id>-<short-slug>` remain supported for compatibility
- workspace: `<workspace-root>/<issue-id>`

## Git Flow

DayFlow uses a three-level branch strategy:

- `main`: release branch
- `develop`: active integration branch
- `feature/tasks-<issue-number>-<short-slug>`: isolated implementation branch for a single Linear issue

Expected merge flow:

1. create or update issue branch from `develop`
2. open PR from issue branch to `develop`
3. squash-merge issue PR into `develop`
4. when `develop` is stable, merge `develop` into `main`

## Failure Handling

Move an issue to `Blocked` when:

- required secrets are missing
- local services cannot start
- docs conflict and product intent is unclear
- the issue would require splitting into smaller tasks first

## Required Supporting Artifacts

- `WORKFLOW.md`
- `docs/automation-model.md`
- `docs/harness-engineering.md`
- `docs/pain-points.md`
- `docs/failure-taxonomy.md`
- `docs/harness-skill-model.md`
- `docs/git-tracking-policy.md`
- `docs/iteration-queue.md`
- `docs/review-checklist.md`
- `.github/pull_request_template.md`
- `.codex/skills/dayflow-orchestrator/SKILL.md`
- `scripts/audit_harness_drift.sh`
