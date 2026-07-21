# DayFlow Automation Model

## Summary

DayFlow uses a command-driven, single-issue delivery lane. `scripts/dayflow_runner.sh` performs deterministic Linear, Git, GitHub, proof, review, and notification checks around a bounded Codex execution. It runs once and exits.

Automatic behavior:

- issue admission and role/model routing
- isolated worktree and branch creation
- bounded Primary Agent execution
- delivery proof validation
- structured review and one remediation pass
- PR-to-Linear reconciliation
- deduplicated Discord notifications

Manual behavior:

- issue creation and prioritization
- large product decisions
- secret provisioning
- blocked issue recovery
- PR merge approval

## Ownership and States

One Primary Agent owns an issue through review follow-up. The orchestrator selects and starts work but does not implement product code.

- `Todo`: the only state that may create a new worktree.
- `In Progress`: active ownership; resume requires valid local state, worktree, branch, and session.
- `In Review`: a ready PR exists; requested changes return ownership to `In Progress`.
- `Blocked`: admission, model, resource, runtime, or delivery guards stopped the issue without discarding work.
- `Done`: the develop-targeted PR was merged.

The lifecycle is `Todo -> In Progress -> In Review -> merge-ready -> Done`. `reconcile` owns PR-driven state changes; the model never mutates lifecycle state directly.

## Admission and Delivery Contract

Admission requires:

- title in `[Agent] short task` form
- exactly one supported `Primary Agent`
- non-empty `Goal`, `Inputs`, and `Out of Scope`
- two to five concrete `Done When` checks
- one-PR scope

Delivery requires:

- `feature/tasks-<number>-<slug>` checked out in `.dayflow/worktrees/CEN-N`
- at least one commit beyond `origin/develop`
- branch pushed to origin
- open PR targeting `develop`
- all proof headings populated
- no P0-P2 finding after at most one same-session remediation

## Model and Resource Policy

`product-agent`, `integration-agent`, and `review-agent` use `gpt-5.6-sol/high`. `backend-agent` and `ios-agent` use `gpt-5.6-terra/medium`. There is no implicit fallback.

The default execution sandbox is `workspace-write`, approval policy is `never`, and review is read-only. The aggregate issue token limit is 120K, no-progress limit is five minutes, and per-invocation execution limit is 20 minutes. Breaches terminate the child process, preserve state, and block the issue.

## Reconciliation

- open draft PR: `In Progress`
- open ready PR: `In Review`
- current requested changes: draft PR plus `In Progress`
- ready PR with green checks: one merge-ready notification per head SHA
- merged PR: `Done` plus completion notification

`status` is read-only. `reconcile [CEN-N]` handles one issue; `reconcile` handles all locally owned issues. No background poller is required.

## Repository Truth

- `docs/local-runner.md`
- `docs/harness-engineering.md`
- `docs/failure-taxonomy.md`
- `docs/git-tracking-policy.md`
- `docs/review-checklist.md`
- `.codex/agents/`
- `.codex/skills/`
- `scripts/dayflow_runner.sh`
- `scripts/lib/dayflow_runner.sh`
- `scripts/tests/`
