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
- `Done`: the develop-targeted PR was merged.

The lifecycle is `Todo -> In Progress -> In Review -> merge-ready -> Done`. `reconcile` owns PR-driven state changes; the model never mutates lifecycle state directly.

## Supervisor Queue Contract

Each cycle first acquires a singleton PID lock, reconciles dead claims, runs the runner's all-issue reconciliation, and cleans safely completed worktrees. It then reads a fresh bounded Linear snapshot and rejects missing dependency state, stale data, result truncation, or a cycle in the active blocks graph.

An issue is queue-eligible only when it is `Todo` and every blocker is `Done`. Eligible issues sort by ascending Linear priority, treating unset priority as last, then ascending issue number. Sequential dispatch is the default. The only parallel mode is an explicit maximum of two, and both active issues must declare `Parallel Safe: yes`, non-empty `Write Scope` values, and nonoverlapping paths.

A claim records the issue, PID, parallel marker, scopes, and start time while the runner owns the dispatch. Live claims consume capacity. Dead claims are released only when persisted runner state is one of the known safe lifecycle outcomes; unsafe or missing state preserves the claim and stops the cycle. The supervisor never bypasses runner admission, ownership, per-issue locking, review, or resource limits.

Locally owned `review-changes` and `publication-retry` states sort before new `Todo` work. They must retain a clean exact worktree, matching branch, session/model ownership, completed blockers, no existing claim, and valid write-scope metadata. Locks and claims compare both PID and process start identity.

## Admission and Delivery Contract

Admission requires:

- title in `[Agent] short task` form
- exactly one supported `Primary Agent`
- non-empty `Goal`, `Inputs`, and `Out of Scope`
- two to five concrete `Done When` checks
- one-PR scope

Before a non-publication Primary Agent path can mutate an issue worktree or launch Codex, admission also resolves the configured Linear transition targets `In Progress`, `In Review`, `Done`, and `Blocked`. Missing workflow state configuration produces an actionable local `blocked` record with `configuration_block` metadata and a Discord alert before worktree creation or model launch; the runner does not attempt to synthesize or change Linear workflow states.

Delivery requires:

- `feature/tasks-<number>-<slug>` checked out in `.dayflow/worktrees/CEN-N`
- at least one commit beyond `origin/develop`
- branch pushed to origin
- open PR targeting `develop`
- all proof headings populated
- no P0-P2 finding after at most one same-session remediation
- validated structured evidence for 1-8 passed tests

Codex subprocesses receive no Linear, GitHub, or Discord credential variables. Publication is a persisted `edited -> committed -> pushed -> pr-created` state machine; retries reconcile local HEAD, remote HEAD, and PR head/base/proof before continuing without re-running the primary model. GitHub CLI GraphQL failure on PR discovery or creation triggers a REST pulls fallback, including an existence check before REST creation. The normalized REST result is also used by delivery validation, read-only `status`, and `reconcile`, so a valid existing PR remains operable when GraphQL lookup is unavailable. Post-commit or post-push failure remains model-free `publication-retry` and preserves the exact worktree.

## Model and Resource Policy

`product-agent`, `integration-agent`, and `review-agent` use `gpt-5.6-sol/high`. `backend-agent` and `ios-agent` use `gpt-5.6-terra/medium`. There is no implicit fallback.

The default execution sandbox is `workspace-write`, approval policy is `never`, and review is read-only. Token policy has one hard aggregate issue limit and one observation threshold: 120K uncached-input-plus-output tokens (`DAYFLOW_RESOURCE_TOKEN_LIMIT`) is the authoritative resource limit, while 500K total context tokens including cached input (`DAYFLOW_CONTEXT_TOKEN_LIMIT`) triggers an auditable warning. The legacy `DAYFLOW_TOKEN_LIMIT` value supplies the resource limit only when the new setting is absent. Supervisor dispatch inherits this policy and does not create a separate budget.

Primary, resume, and review execution all enforce a 32 KiB prompt cap before launch, then a 5 MiB captured command-output cap, a five-minute no-progress cap, and a 20-minute wall-clock cap. Repeated cumulative JSONL usage snapshots are reduced to one invocation total, including a final snapshot observed after process exit, and invocation totals are added once to issue state. `.usage` records cached input, uncached input, output, total tokens, and invocation count; `.token_budget` exposes the resource and total-context formulas, configured values, and current use. Crossing the total-context threshold records `.context_observation` with used and threshold tokens, first and latest phases, timestamps, count, and an operator-facing reason. It warns again before any later primary, resume, or review launch, but does not reclassify a successful invocation. The resource, prompt, command-output, stall, and wall-clock guards still terminate the child process tree, preserve state, and block with their exact runner reasons; model rejection and other nonzero Codex exits retain their existing classifications.

## Reconciliation

- open draft PR: `In Progress`
- open ready PR: `In Review`
- current requested changes: draft PR plus `In Progress`
- ready PR with green checks: one merge-ready notification per head SHA
- merged PR: `Done` plus completion notification

Runner `status` is read-only. Runner `reconcile [CEN-N]` handles one issue and runner `reconcile` handles all locally owned issues. Lifecycle, claim, status, and cleanup scans accept only exact `CEN-N.json` records; auxiliary runtime artifacts such as `CEN-N-publication.json` are ignored and never become issue, lock, Linear, or GitHub inputs. Supervisor `reconcile` combines claim recovery with that all-issue reconciliation; supervisor `cleanup` performs only guarded local cleanup. `start` atomically captures `LINEAR_API_KEY` and effective `PATH` in canonical `.dayflow/supervisor.env` before loading the per-user `launchd` job; `stop` unloads it, and supervisor `status` reports scheduling, snapshot, and claims without exposing the environment or dispatching work.

Local records already marked `done` are terminal reconciliation inputs and are skipped before any Linear or GitHub lookup. This keeps historical merged records, including completed stacked PRs with a non-`develop` base, from blocking a supervisor cycle. Every non-`done` local state remains subject to the normal develop-target, reviewed-head, CI, and lifecycle checks and fails closed on a mismatch.

### Merged PR event closure

`.github/workflows/merge-lifecycle.yml` runs when a pull request closes. The deterministic reconciler accepts only a merged, `develop`-targeted PR whose repository-owned head matches `feature/tasks-N-<slug>`. It derives `CEN-N` from that branch, reads the issue from Linear, and moves it to `Done` only when it is not already there.

Before changing Linear or calling Discord, the workflow creates a hidden claim marker in a PR comment and captures that comment ID. It then converges Linear to `Done`, delivers Discord, and patches the same comment to `delivered`. A delivered marker makes replays a clean no-op. An unresolved claim fails closed without another Discord call and requires an operator to reconcile whether delivery occurred.

A definite non-2xx Discord response changes the claim to `retryable` and fails the job, allowing a rerun to create a new claim. A transport error keeps the claim because delivery is ambiguous. If Discord accepts the message but the delivered-marker PATCH fails, the claim also remains and reruns must not duplicate Discord. Linear failures before Discord release the claim for retry, preserving convergence to `Done`. The per-PR workflow concurrency group prevents overlapping event attempts.

The repository setting **Settings > General > Pull Requests > Automatically delete head branches** owns remote feature-branch deletion. The workflow relies only on the immutable event payload and the merged base branch, so deletion may happen before reconciliation without losing the `CEN-N` mapping. The workflow never calls the Git ref deletion API.

GitHub-hosted reconciliation does not access `.dayflow/` and never removes a local worktree. Local supervisor reconciliation and cleanup are deliberately ordered before queue selection so merged blockers can release dependent work. Cleanup fetches/prunes and removes only an exact owned worktree after runner status proves `Done`, the tracked PR is merged into `develop`, and the worktree is clean. A local `done` record whose tracked PR is merged from the recorded branch into a non-`develop` base is instead marked with `worktree_preservation.kind: stacked-pr`; cleanup skips that marker on later cycles and continues queue selection. Dirty workspaces are preserved as failures, and CEN-28 is always excluded from supervisor cleanup.

The stacked marker is an audit boundary, not proof that the delivery reached `develop`. To recover the workspace, first audit the recorded `base_ref` delivery chain through `develop`. If the chain is incomplete, retain the worktree and repair the chain outside supervisor cleanup. Once the chain is proven delivered, verify the exact owned worktree is clean, remove it non-forced, and retain the local record and preservation metadata as the audit trail.

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
