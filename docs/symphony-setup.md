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
3. For each issue, Symphony creates an isolated workspace under the configured root.
4. Symphony runs `codex app-server` in that workspace.
5. The assigned agent follows `WORKFLOW.md`.
6. Results are returned through branch, PR, CI status, and proof-of-work summary.

## DayFlow State Machine

Current Linear workspace does not have a dedicated `Ready` state yet, so DayFlow currently uses:

- `Todo`: auto-runnable queue state
- `In Progress`: actively executing
- `In Review`: PR open and under review
- `Done`: merged and complete
- `Canceled` and `Duplicate`: terminal

Planned future refinement:

- add `Ready` and `Blocked` when the workflow is mature enough to separate queued work from draft work

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

- branch format: `codex/<issue-id>-<short-slug>`
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

Future target filter after adding more Linear states:

- state is `Ready`
- blocked items stay out of pickup

## Notes

- local-first means Postgres runs locally, while app and API can be launched from the workspace
- initial setup can use personal Linear and GitHub accounts
- the vendored Symphony Elixir runtime under `/Users/kakao_ent/Documents/DayFlow/vendor/symphony/elixir` contains a local compatibility patch for the current `codex app-server` v2 schema
- specifically, `thread/start` sandbox values are normalized to `readOnly`, `workspaceWrite`, `dangerFullAccess`, and the default `turn/start` sandbox policy uses `mode` plus snake_case keys expected by the local app-server schema
