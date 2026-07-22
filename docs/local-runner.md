# DayFlow Local Runner

DayFlow executes one Linear issue per command. There is no resident daemon, polling loop, or local dashboard.

## Commands

```bash
LINEAR_API_KEY=... scripts/dayflow_runner.sh --dry-run run CEN-29
LINEAR_API_KEY=... scripts/dayflow_runner.sh run CEN-29
LINEAR_API_KEY=... scripts/dayflow_runner.sh status CEN-29
LINEAR_API_KEY=... scripts/dayflow_runner.sh reconcile CEN-29
LINEAR_API_KEY=... scripts/dayflow_runner.sh reconcile
```

- `run` starts a `Todo` issue or resumes an owned `In Progress`/`In Review` issue.
- `status` combines local state with available Linear and GitHub state without changing either.
- `reconcile` maps PR state back to Linear, handles requested changes, and sends merge-ready or completion notifications.
- `--dry-run` validates issue admission, role routing, branch naming, and resume eligibility without creating runtime state or changing external systems.

## Admission and Ownership

Runnable issues require a `[Agent] title` and non-empty `Goal`, `Primary Agent`, `Inputs`, `Done When`, and `Out of Scope` sections. `Done When` must have two to five checks and the issue must fit one PR.

Only `Todo` starts a new workspace. `In Progress` and `In Review` resume only when `.dayflow/state/CEN-N.json` points to an existing worktree, matching branch, and persisted Primary Agent session. Other states are not runnable.

New branches use `feature/tasks-<number>-<slug>` from `origin/develop`. Worktrees, state, and logs live under `.dayflow/` and are never tracked.

## Model Routing

| Agent | Model | Reasoning |
| --- | --- | --- |
| `product-agent` | `gpt-5.6-sol` | `high` |
| `integration-agent` | `gpt-5.6-sol` | `high` |
| `review-agent` | `gpt-5.6-sol` | `high` |
| `backend-agent` | `gpt-5.6-terra` | `medium` |
| `ios-agent` | `gpt-5.6-terra` | `medium` |

The mapping is explicit and has no fallback. A rejected or unavailable model blocks the issue locally, attempts to move Linear to `Blocked`, preserves the worktree, and sends a Discord notification.

Primary execution uses `workspace-write` and approval policy `never`. Review uses a read-only sandbox. A system test that needs broader access must opt in through `DAYFLOW_DEFAULT_SANDBOX` for that invocation; the resulting state and logs remain local.

## Bounds and Review

Each issue has a 120,000 aggregate token ceiling. Each Codex invocation stops after 20 minutes or five minutes without output progress. A limit breach preserves the worktree and blocks the issue.

The Primary Agent must leave a pushed branch, at least one commit beyond `origin/develop`, an open PR targeting `develop`, and non-empty proof sections. The runner then invokes `review-agent` with `gpt-5.6-sol/high`. P0-P2 findings are posted to the PR and returned once to the same Primary Agent session. A second blocking review result blocks the issue.

After review passes, the runner persists the reviewed head SHA, marks the PR ready, and moves Linear to `In Review`. It then waits for CI with a bounded, model-free polling interval and invokes reconciliation when checks turn green. A timeout leaves the issue safely in review for a later `reconcile` call. Merge-ready requires the current PR head to match the reviewed SHA, a `develop` base, a clean merge state, and green checks; any later push returns the PR to draft and requires review again. A merged PR moves to `Done` only when it still targets `develop` and matches the tracked branch.

## Local Configuration Migration

On first non-dry run, the runner creates `.dayflow/worktrees`, `.dayflow/state`, and `.dayflow/logs`. If present, it copies GitHub CLI auth, Discord notification configuration, and merge-ready dedupe state from the legacy `.symphony/` directory. It never deletes or moves the source. This exception protects the paused CEN-28 workspace until it is adopted separately.

Secrets belong only in local environment variables or ignored files:

- `LINEAR_API_KEY`
- `.dayflow/gh/`
- `.dayflow/notifications.env`
- `.dayflow/state/`
- `.dayflow/logs/`

The Discord file contains `DAYFLOW_DISCORD_WEBHOOK_URL=...`. GitHub CLI authentication defaults to `.dayflow/gh`; set `GH_CONFIG_DIR` only when an explicit alternate local store is required.

## Recovery

- Admission failure: fix the Linear metadata, return the issue to `Todo`, and rerun.
- Model, token, timeout, or delivery failure: inspect `status` and `.dayflow/logs`, retain the worktree, resolve the cause, then deliberately return the issue to a runnable state.
- Requested changes: run `reconcile`, then `run CEN-N`; the same Primary Agent session resumes.
- Merged PR: run `reconcile CEN-N` to close Linear and send completion notification.
