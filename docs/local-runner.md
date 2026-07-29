# DayFlow Local Runner

DayFlow's runner executes one Linear issue per command. The dependency-aware supervisor performs one bounded queue cycle and exits; supported `launchd` scheduling can invoke that cycle after the initiating terminal closes. There is no resident DayFlow daemon, local dashboard, Symphony service, or listener on port 4100.

## Commands

```bash
LINEAR_API_KEY=... scripts/dayflow_runner.sh --dry-run run CEN-29
LINEAR_API_KEY=... scripts/dayflow_runner.sh run CEN-29
LINEAR_API_KEY=... scripts/dayflow_runner.sh status CEN-29
LINEAR_API_KEY=... scripts/dayflow_runner.sh reconcile CEN-29
LINEAR_API_KEY=... scripts/dayflow_runner.sh reconcile

LINEAR_API_KEY=... scripts/dayflow_supervisor.sh once
scripts/dayflow_supervisor.sh start
scripts/dayflow_supervisor.sh stop
scripts/dayflow_supervisor.sh status
LINEAR_API_KEY=... scripts/dayflow_supervisor.sh reconcile
LINEAR_API_KEY=... scripts/dayflow_supervisor.sh cleanup
```

- `run` starts a `Todo` issue or resumes an owned `In Progress`/`In Review` issue.
- `status` combines local state with available Linear and GitHub state without changing either.
- `reconcile` maps PR state back to Linear, handles requested changes, and sends merge-ready notifications. The hosted claim-marked lifecycle owns completion notifications.
- merged task PRs are normally closed by `.github/workflows/merge-lifecycle.yml`; local `reconcile` remains a recovery path.
- `--dry-run` validates issue admission, role routing, branch naming, and resume eligibility without creating runtime state or changing external systems.

Supervisor commands:

- `once` locks the queue cycle, reconciles claims and PR state, safely cleans completed worktrees, snapshots Linear dependencies, and dispatches eligible work before exiting.
- `start` securely persists the required launchd runtime and installs the repository plist as a per-user job configured to run `once` at load and on the configured interval. `stop` unloads that job.
- `status` returns read-only JSON containing `launchd` load state, the latest queue snapshot, and active claims.
- `reconcile` performs claim recovery and delegates all owned issue reconciliation to the runner. `cleanup` applies only the guarded post-merge worktree cleanup.

`launchd` does not load interactive shell startup files. `start` atomically writes `LINEAR_API_KEY`, effective `PATH`, and an explicitly configured `DAYFLOW_SUPERVISOR_MAX_PARALLEL` to canonical `.dayflow/supervisor.env` with mode `0600`; the plist contains no secret. Parallelism is validated as 1 or 2. The private launchd bootstrap validates and loads that ignored file before loading the supervisor library or checking tools, and fails closed to the supervisor error log when it is missing, malformed, insecure, or insufficient.

## Queue Selection and Concurrency

Only `Todo` issues whose blockers are all `Done` are eligible. Before selection, `once` reconciles merged PRs so a newly completed blocker can make the next issue eligible in the same cycle. Malformed, stale, oversized, or cyclic dependency snapshots fail closed.

Selection is deterministic: Linear priority ascending, with unset priority last, then ascending `CEN-N`. The default is one issue at a time. `DAYFLOW_SUPERVISOR_MAX_PARALLEL=2` is allowed only when each concurrent issue explicitly declares `Parallel Safe: yes` and a non-empty `Write Scope`, and all declared scopes are nonoverlapping. Two is the hard maximum.

The cycle has a singleton PID lock, and every dispatch has a PID-backed claim under `.dayflow/supervisor/claims`. A live lock rejects an overlapping cycle; a dead lock is recovered. On restart, dead claims are removed only when runner state is safely terminal or resumable through normal lifecycle handling. Missing or unsafe runner state preserves the claim and fails closed. The runner's per-issue ownership and lock checks remain authoritative.

Owned `review-changes`, `publication-retry`, and `token-accounting-recovery` work is eligible ahead of new `Todo` work only when local issue, session, worktree, branch, dependency, claim, and write-scope guards all pass. Unrelated Linear `In Progress` or `In Review` issues are never adopted. PID locks and claims include process start identity so PID reuse is not mistaken for live ownership.

## Admission and Ownership

Runnable issues require a `[Agent] title` and non-empty `Goal`, `Primary Agent`, `Inputs`, `Done When`, and `Out of Scope` sections. `Done When` must have two to five checks and the issue must fit one PR.

Only `Todo` starts a new workspace. `In Progress` and `In Review` resume only when `.dayflow/state/CEN-N.json` points to an existing worktree, matching branch, and persisted Primary Agent session. Other states are not runnable.

New branches use `feature/tasks-<number>-<slug>` from `origin/develop` by default. A Linear description may declare exactly `Integration Base: integration/private-two-person-cutover`; this is the only non-`develop` value accepted, and malformed or duplicate fields fail admission without fallback. The resolved base is persisted and must match on resume, delivery, reconciliation, and cleanup. Worktrees, state, and logs live under `.dayflow/` and are never tracked.

## Model Routing

| Agent | Model | Reasoning |
| --- | --- | --- |
| `product-agent` | `gpt-5.6-terra` | `high` |
| `integration-agent` | `gpt-5.6-terra` | `high` |
| `review-agent` | `gpt-5.6-terra` | `high` |
| `backend-agent` | `gpt-5.6-terra` | `medium` |
| `ios-agent` | `gpt-5.6-terra` | `medium` |

The mapping is explicit and has no fallback. A rejected or unavailable model blocks the issue locally, attempts to move Linear to `Blocked`, preserves the worktree, and sends a Discord notification.

Primary execution uses `workspace-write` and approval policy `never`. Review uses a read-only sandbox. A system test that needs broader access must opt in through `DAYFLOW_DEFAULT_SANDBOX` for that invocation; the resulting state and logs remain local.

## Bounds and Review

The supervisor adds no model invocation or token pool. Every dispatched issue inherits the runner's resource boundaries, including its 120,000 aggregate **billable** token ceiling, prompt and output caps, 20-minute invocation limit, and five-minute no-progress limit. Billable tokens are uncached input plus output; cached input remains separately persisted as raw observability and never consumes `DAYFLOW_TOKEN_LIMIT`. Admission, live monitoring, persisted aggregate accounting, and post-exit checks use that same billable value. A limit breach preserves the worktree and blocks the issue.

The Primary Agent must leave a pushed branch, at least one commit beyond `origin/<declared-base>`, an open PR targeting that base, and non-empty proof sections. The runner then invokes `review-agent` with `gpt-5.6-terra/high`. P0-P2 findings are posted to the PR and returned once to the same Primary Agent session. A second blocking review result blocks the issue.

Every primary or remediation final output must be one bounded JSON object with a short `summary` and 1-8 `{name,status:"passed"}` test records. Missing, malformed, failed, or extra evidence blocks before publication; model-provided commands are never executed. Validated test names populate the PR proof. Linear, GitHub, and Discord credential variables are removed from primary, resume, and review Codex subprocesses.

Publication persists `edited`, `committed`, `pushed`, and `pr-created` phases. A retry validates exact ownership, deterministic commit and HEAD, fast-forward remote state, declared-base PR head/base, and proof before continuing without another primary model call. It never duplicates commits or PRs, force-pushes, or guesses through an integrity mismatch.

After review passes, the runner persists the reviewed head SHA, marks the PR ready, and moves Linear to `In Review`. It then waits for CI with a bounded, model-free polling interval and invokes reconciliation when checks turn green. A timeout leaves the issue safely in review for a later `reconcile` call. Merge-ready requires the current PR head to match the reviewed SHA, the declared base, a clean merge state, and green checks; any later push returns the PR to draft and requires review again. A merged PR moves to `Done` only when it still targets the declared base and matches the tracked branch.

## Local Configuration Migration

On first non-dry run, the runner creates `.dayflow/worktrees`, `.dayflow/state`, and `.dayflow/logs`. If present, it copies GitHub CLI auth, Discord notification configuration, and merge-ready dedupe state from the legacy `.symphony/` directory. It never deletes or moves the source. This exception protects the paused CEN-28 workspace until it is adopted separately.

Secrets belong only in local environment variables or ignored files:

- `LINEAR_API_KEY`
- `.dayflow/gh/`
- `.dayflow/notifications.env`
- `.dayflow/state/`
- `.dayflow/logs/`

The Discord file contains `DAYFLOW_DISCORD_WEBHOOK_URL=...`. GitHub CLI authentication defaults to `.dayflow/gh`; set `GH_CONFIG_DIR` only when an explicit alternate local store is required.

## Merge Closure and Cleanup

For a repository-owned `feature/tasks-N-*` PR merged into `develop` or the exact temporary integration base, GitHub Actions moves `CEN-N` to `Done` and sends the deduplicated Discord completion notification. The final integration-to-`develop` PR is never a task completion. Rerun a failed merge-lifecycle job from GitHub Actions after a Linear, GitHub, or Discord outage; no local polling loop is needed.

Enable GitHub's **Automatically delete head branches** repository setting for remote cleanup. The event reconciler does not fetch or delete the head ref, so automatic deletion is safe even when it happens before the job runs.

The hosted job never deletes local `.dayflow` state or worktrees. Supervisor `once` and `cleanup` may remove only the exact owned worktree after runner status proves Linear `Done`, a merged PR into its persisted declared base from the tracked branch, and a clean worktree. Cleanup fetches and prunes that base, uses non-forced `git worktree remove`, records cleanup in local state, and never removes dirty workspaces or CEN-28. This preserves the CEN-28 migration exception and paused workspace.

## Recovery

- Admission failure: fix the Linear metadata, return the issue to `Todo`, and rerun.
- Model, token, timeout, or delivery failure: inspect `status` and `.dayflow/logs`, retain the worktree, resolve the cause, then deliberately return the issue to a runnable state.
- Cached-context false block: when a blocked state has retained, internally consistent raw usage, exactly one primary log/output pair, valid passed evidence, and matching owned worktree metadata, run `reconcile CEN-N` and then `run CEN-N`. Reconciliation recomputes billable tokens and stages deterministic publication/review from that retained primary output; it does not launch a second primary model. Any missing or inconsistent evidence remains blocked for operator review.
- Requested changes: run `reconcile`, then `run CEN-N`; the same Primary Agent session resumes.
- Failed merged-PR workflow: rerun the failed GitHub Actions job; use local `reconcile CEN-N` only as a deliberate fallback.
