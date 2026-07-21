# Symphony Setup

This repository uses a minimal local Symphony workflow modeled after the official Symphony README and SPEC.

## Goals

- Linear issue ingestion
- isolated issue workspaces
- Codex execution per issue
- PR-based review loop
- proof-of-work summaries

## Required Files

- `WORKFLOW.md`
- `docs/automation-model.md`
- `docs/harness-engineering.md`
- `docs/git-tracking-policy.md`
- `docs/github-local-auth.md`
- `docs/iteration-queue.md`
- `docs/review-checklist.md`
- `.codex/skills/commit/SKILL.md`
- `.codex/skills/push/SKILL.md`
- `.codex/skills/pull/SKILL.md`
- `.codex/skills/land/SKILL.md`
- `.codex/skills/linear/SKILL.md`

## Minimal Local Workflow

1. Create a Linear project for DayFlow.
2. Configure Symphony to poll that project.
3. Start `scripts/run_symphony.sh` instead of invoking Symphony directly.
4. The wrapper keeps Linear issue states aligned with GitHub PR state.
5. The wrapper starts a single lifecycle-owner lane via `WORKFLOW.md`.
6. For each issue, Symphony creates an isolated workspace under the configured root.
7. Symphony runs `codex app-server` in that workspace.
8. The assigned primary agent keeps ownership through review follow-up until the PR is merge-ready.
9. Results are returned through branch, PR, CI status, and proof-of-work summary.
10. Use `scripts/audit_harness_drift.sh` during maintenance to check doc/workflow/script alignment.

## Token Budget Defaults

DayFlow does not use the upstream default token posture unchanged. The local workflow keeps the agent budget tighter:

- shallow clone in `after_create`
- `agent.max_turns: 5`
- `codex.turn_timeout_ms: 420000`
- `codex.stall_timeout_ms: 90000`
- generated iOS build artifacts are excluded from normal issue work unless the issue explicitly targets them

These values are based on the official Symphony configuration surface in the README and SPEC, but tuned more aggressively for local-first MVP work.

## DayFlow State Machine

Current DayFlow workflow still uses `Todo` as the runnable queue state, with admission checks in the wrapper to keep malformed issues from being retried indefinitely.
If a `Blocked` state exists in Linear, the admission validator may move incomplete issues there.

Current state usage:

- `Todo`: auto-runnable queue state
- `In Progress`: actively executing
- `In Review`: PR open and under review
- `Blocked`: optional manual intervention state for malformed or externally blocked work
- `Done`: merged and complete
- `Canceled` and `Duplicate`: terminal

Planned future refinement:

- add `Ready` later if the workflow needs a separate admission-passed queue state

## Required Issue Metadata

Every auto-runnable Linear issue should contain:

- `Goal`
- `Primary Agent`
- `Secondary Agents`
- `Inputs`
- `Constraints`
- `Done When`
- `Out of Scope`
- `Test Notes`
- `Follow-up Issues`

The title should follow `[Agent] short task description`.

## DayFlow Conventions

- each issue should map to one agent-sized task
- each issue should produce a visible artifact
- PRs should include changed files, tests, risks, and next issue suggestions
- all PRs should go through the review-agent checklist
- small vertical slices are allowed only when handoff stays sequential

## Branch and Workspace Rules

- branch format: `feature/tasks-<issue-number>-<short-slug>` preferred
- legacy `codex/<issue-number>-<short-slug>` and `codex/<issue-id>-<short-slug>` remain supported for compatibility
- workspace format: `<workspace-root>/<issue-id>`
- one Linear issue per branch
- issue branches should be created from `develop`
- implementation PRs should target `develop`
- `develop` should be merged into `main` only after stabilization

## GitHub Auth Scope

For this repository, keep GitHub CLI auth local to the repo instead of global user config.

- local auth dir: `/Users/kakao_ent/Documents/DayFlow/.symphony/gh`
- Symphony launches Codex with `GH_CONFIG_DIR` pointing to that path
- refresh auth with the instructions in `docs/github-local-auth.md`

## Suggested Symphony Pickup Filter

Current DayFlow filter:

- team/project is DayFlow
- state is `Todo`
- no blocking label is present

Automatic reconciliation rules:

- draft PR keeps the issue in `In Progress`
- ready-for-review PR moves the issue to `In Review`
- fresh review findings return the PR to draft and the issue to `Todo`
- stale in-progress work with no diff returns to `Todo`
- stale in-progress work with commits but no PR stays owned for manual follow-up instead of being silently retried
- merged PR moves the issue to `Done`
- review follow-up returns to the same issue owner instead of a separate review lane

Future target filter after adding more Linear states:

- state is `Ready`
- blocked items stay out of pickup

## Notes

- local-first means Postgres runs locally, while app and API can be launched from the workspace
- initial setup can use personal Linear and GitHub accounts
- the vendored Symphony runtime is pinned through the upstream submodule at `/Users/kakao_ent/Documents/DayFlow/vendor/symphony`
- new workspaces must initialize submodules so the vendored Symphony runtime is available
- the vendored Symphony Elixir runtime under `/Users/kakao_ent/Documents/DayFlow/vendor/symphony/elixir` should stay aligned with upstream unless a DayFlow-specific patch is proven necessary
- specifically, `thread/start` sandbox values should be passed as `read-only`, `workspace-write`, or `danger-full-access`, while `turn/start` sandbox policies should use a `type` field with app-server variants such as `workspaceWrite`, `readOnly`, or `dangerFullAccess`
