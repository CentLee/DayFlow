# DayFlow Orchestration Failure Taxonomy

This document captures recurring failure modes discovered while running DayFlow through Symphony.
The goal is to turn one-off firefighting into reusable outer-loop guardrails for future projects.

## Core principle

- do not treat an issue failure as only an issue failure
- identify which layer failed:
  - Symphony runtime
  - outer orchestration supervisor
  - issue lifecycle state reconciliation
  - primary implementation agent
  - review / proof / merge closure
- add a reusable guard or recovery rule before moving on

## Failure classes

### F1. Empty workspace spin

Symptoms:

- `Todo` or `In Progress` issue has no real workspace contents
- Symphony child is alive
- tokens keep increasing
- dashboard may show activity without usable artifacts

Recovery:

- kill the current child runtime
- preserve supervisor loop
- retry from a fresh workspace

Guard:

- `scripts/guard_empty_workspace_spins.sh`

### F2. State / ownership mismatch

Symptoms:

- workspace exists and branch exists
- issue still shows `Todo`
- code changes may already exist

Recovery:

- promote owned workspace issue to `In Progress`

Guard:

- `scripts/reconcile_issue_ownership.sh`

### F3. Dirty workspace without PR

Symptoms:

- issue branch contains uncommitted work
- no PR exists
- child runtime keeps consuming turns or tokens
- the issue is not progressing toward review

Recovery:

- stop the current child runtime
- keep the dirty workspace for continuation or manual review
- do not silently restart the same issue immediately

Guard:

- `scripts/guard_issue_sessions.sh`

### F4. Completed turn without lifecycle closure

Symptoms:

- Codex emits `task_complete`
- no PR exists and no valid completion artifact exists
- issue remains runnable and gets picked again

Recovery:

- validate branch, diff, PR, and recent activity
- return the issue to `Todo` when the run produced no reviewable output

Guard:

- `scripts/validate_issue_outcomes.sh`

### F5. Review finding loop break

Symptoms:

- PR receives review findings
- issue stays in `In Review`
- implementation owner does not regain control

Recovery:

- return issue to retry queue
- move PR back to draft when needed

Guard:

- `scripts/reconcile_review_feedback.sh`

### F6. Dashboard / runtime observability mismatch

Symptoms:

- Linear shows `In Progress`
- workspace has a branch or diff
- dashboard does not show an active issue session

Recovery:

- trust workspace + branch + diff over dashboard alone
- use outer-loop guards to decide whether to preserve, retry, or block the issue

Follow-up:

- improve supervisor health summaries so active ownership can be inferred even when dashboard session display lags

### F7. Branch bootstrap stall

Symptoms:

- fresh workspace exists
- branch remains `develop`
- no diff appears
- issue stays in `Todo`

Recovery:

- treat the workspace as an invalid bootstrap attempt
- move the stale workspace aside
- keep the supervisor alive
- retry from a fresh workspace
- stale workspaces must not count as active ownership on later reconciliation passes

Guard:

- `scripts/guard_branch_bootstrap_stalls.sh`

### F8. Branch-only stall

Symptoms:

- issue branch exists
- workspace is still clean
- `HEAD == origin/develop`
- no PR exists

Recovery:

- treat the branch as a failed bootstrap continuation
- move the workspace aside as stale
- retry from a fresh workspace

Guard:

- `scripts/guard_issue_sessions.sh`

## Recovery priorities

When a failure occurs, apply this order:

1. stop uncontrolled token burn
2. preserve useful workspace artifacts
3. restore correct issue state
4. decide between continue, retry, or block
5. add or strengthen a reusable guard

## Reusable design rules

- only `Todo` is a runnable queue state
- `In Progress` is an ownership state, not a runnable queue state
- dirty work should not be silently discarded
- a child runtime should be killable without tearing down the whole supervisor
- every repeated failure must become either:
  - a scripted guard
  - a documented recovery rule
  - an explicit blocked condition
