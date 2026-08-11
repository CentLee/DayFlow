# DayFlow Automation Model

## Summary

DayFlow uses a command-driven delivery lane. `scripts/dayflow_runner.sh` performs deterministic Linear, Git, GitHub, proof, review, and notification checks around one bounded issue execution. `scripts/dayflow_supervisor.sh once` is a dependency-aware outer cycle that reconciles, cleans up, selects, dispatches through the runner, and exits. Supported `launchd` scheduling repeats that one-shot command using a canonical, mode-0600 runtime environment file; no Symphony service, HTTP control plane, or port 4100 is involved.

Automatic behavior:

- issue admission and role/model routing
- isolated worktree and branch creation
- bounded Primary Agent execution
- delivery proof validation
- structured review and one remediation pass
- PR-to-Linear reconciliation
- merged-PR lifecycle closure in GitHub Actions
- deduplicated Discord notifications
- dependency-aware `Todo` pickup and guarded post-merge cleanup

Manual behavior:

- issue creation and prioritization
- large product decisions
- secret provisioning
- blocked issue recovery
- PR merge approval
- blocked or unsafe stale-claim recovery

## Ownership and States

One Primary Agent owns an issue through review follow-up. The orchestrator selects and starts work but does not implement product code.

- `Todo`: the only state that may create a new worktree.
- `In Progress`: active ownership; resume requires valid local state, worktree, branch, and session.
- `In Review`: a ready PR exists; requested changes return ownership to `In Progress`.
- `Blocked`: admission, model, resource, runtime, or delivery guards stopped the issue without discarding work.
- `Done`: the declared-base PR was merged.

The lifecycle is `Todo -> In Progress -> In Review -> merge-ready -> Done`. `reconcile` owns PR-driven state changes; the model never mutates lifecycle state directly.

## Supervisor Queue Contract

Each cycle first acquires a singleton PID lock, reconciles dead claims, runs the runner's all-issue reconciliation, and cleans safely completed worktrees. It then reads a fresh bounded Linear snapshot and rejects missing dependency state, stale data, result truncation, or a cycle in the active blocks graph.

An issue is queue-eligible only when it is `Todo` and every blocker is `Done`. Eligible issues sort by ascending Linear priority, treating unset priority as last, then ascending issue number. Sequential dispatch is the default. The only parallel mode is an explicit maximum of two, and both active issues must declare `Parallel Safe: yes`, non-empty `Write Scope` values, and nonoverlapping paths.

A claim records the issue, PID, parallel marker, scopes, and start time while the runner owns the dispatch. Live claims consume capacity. Dead claims are released only when persisted runner state is one of the known safe lifecycle outcomes; unsafe or missing state preserves the claim and stops the cycle. The supervisor never bypasses runner admission, ownership, per-issue locking, review, or resource limits.

Locally owned `review-changes`, `publication-retry`, and `token-accounting-recovery` states sort before new `Todo` work. They must retain a clean exact worktree, matching branch, session/model ownership, completed blockers, no existing claim, and valid write-scope metadata. Locks and claims compare both PID and process start identity.

## Admission and Delivery Contract

Admission requires:

- title in `[Agent] short task` form
- exactly one supported `Primary Agent`
- non-empty `Goal`, `Inputs`, and `Out of Scope`
- two to five concrete `Done When` checks
- one-PR scope

Delivery requires:

- `feature/tasks-<number>-<slug>` checked out in `.dayflow/worktrees/CEN-N`
- at least one commit beyond the declared `origin/<base>`
- branch pushed to origin
- open PR targeting the declared base
- all proof headings populated
- no P0-P2 finding after at most one same-owner fresh-session remediation
- validated structured evidence for 1-8 passed tests

Codex subprocesses receive no Linear, GitHub, or Discord credential variables. Publication is a persisted `edited -> committed -> pushed -> pr-created` state machine; retries reconcile local HEAD, remote HEAD, and PR head/base/proof before continuing without re-running the primary model.

## Model and Resource Policy

`product-agent`, `integration-agent`, and `review-agent` use `gpt-5.6-terra/high`. `backend-agent` and `ios-agent` use `gpt-5.6-terra/medium`. There is no fallback.

The default execution sandbox is `workspace-write`, approval policy is `never`, and review is read-only. Codex subprocesses use `--ignore-user-config`, so personal MCP servers and configuration cannot add tools, context, or background initialization to issue execution. The aggregate issue token limit is 400K **billable tokens**: uncached input plus output. The runner records cumulative phase budgets of primary 220K, review 100K, and remediation 180K, but Codex may report usage only at process completion; these values are admission and diagnostic guards, not a promise of preemptive spend control. When an otherwise successful execution reports a token overage only after exit, the runner records `late_token_limit`, preserves validated test evidence, and continues deterministic publication; the next model stage is rejected at admission. The hard preemptive guard is a phase execution slice: primary 120 seconds, review 90 seconds, and remediation 90 seconds. A slice breach terminates the process, preserves the worktree, and blocks the issue before publication or another model step. Review and requested-changes remediation always start a fresh Primary Agent session with only the current findings, rather than rehydrating an unbounded transcript. Cached input does not consume either token cap, but raw input, cached input, uncached input, output, raw totals, aggregate billable totals, and phase billable totals remain persisted for diagnostics. Prompt, command-output, no-progress, and wall-clock bounds are enforced by the runner. Supervisor dispatch inherits these per-issue limits and does not create a separate token budget.

## Reconciliation

- open draft PR: `In Progress`
- open ready PR: `In Review`
- current requested changes: draft PR plus `In Progress`
- ready PR with green checks: one merge-ready notification per head SHA
- merged PR: local `Done` convergence; the hosted claim-marked lifecycle sends the sole completion notification

Runner `status` is read-only. Runner `reconcile [CEN-N]` handles one issue and runner `reconcile` handles all locally owned issues. Supervisor `reconcile` combines claim recovery with that all-issue reconciliation; supervisor `cleanup` performs only guarded local cleanup. `start` atomically captures `LINEAR_API_KEY` and effective `PATH` in canonical `.dayflow/supervisor.env` before loading the per-user `launchd` job; `stop` unloads it, and supervisor `status` reports scheduling, snapshot, and claims without exposing the environment or dispatching work.

For an historical cached-context false block, `reconcile CEN-N` may correct local accounting only when it can prove billable usage from persisted raw fields, find exactly one matching retained primary log/output pair, validate passed evidence, and revalidate owned worktree metadata. It changes local state to deterministic publication recovery without a primary model call; a subsequent `run CEN-N` publishes and reviews that retained work. Ambiguous or incomplete state remains blocked.

### Merged PR event closure

`.github/workflows/merge-lifecycle.yml` runs when a pull request closes. The deterministic reconciler accepts only a merged PR targeting `develop` or the exact temporary `integration/private-two-person-cutover` base whose repository-owned head matches `feature/tasks-N-<slug>`. It derives `CEN-N` from that branch, reads the issue from Linear, and moves it to `Done` only when it is not already there. The final integration-to-`develop` PR cannot match the task-head contract and never closes a CEN task.

Before changing Linear or calling Discord, the workflow creates a hidden claim marker in a PR comment and captures that comment ID. It then converges Linear to `Done`, delivers Discord, and patches the same comment to `delivered`. A delivered marker makes replays a clean no-op. An unresolved claim fails closed without another Discord call and requires an operator to reconcile whether delivery occurred.

A definite non-2xx Discord response changes the claim to `retryable` and fails the job, allowing a rerun to create a new claim. A transport error keeps the claim because delivery is ambiguous. If Discord accepts the message but the delivered-marker PATCH fails, the claim also remains and reruns must not duplicate Discord. Linear failures before Discord release the claim for retry, preserving convergence to `Done`. The per-PR workflow concurrency group prevents overlapping event attempts.

The repository setting **Settings > General > Pull Requests > Automatically delete head branches** owns remote feature-branch deletion. The workflow relies only on the immutable event payload and the merged base branch, so deletion may happen before reconciliation without losing the `CEN-N` mapping. The workflow never calls the Git ref deletion API.

GitHub-hosted reconciliation does not access `.dayflow/` and never removes a local worktree. Local supervisor reconciliation and cleanup are deliberately ordered before queue selection so merged blockers can release dependent work. Cleanup fetches/prunes and removes only an exact owned worktree after runner status proves `Done`, the tracked PR is merged into its persisted declared base, and the worktree is clean. Dirty workspaces are preserved, and CEN-28 is always excluded from supervisor cleanup.

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
- `scripts/dayflow_supervisor.sh`
- `scripts/lib/dayflow_supervisor.sh`
- `scripts/tests/`
