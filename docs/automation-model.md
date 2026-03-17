# DayFlow Automation Model

## Summary

DayFlow uses semi-automated delivery.

The automation model assumes a global harness skill layer in `~/.codex/skills` plus a thin
DayFlow-specific layer in this repository.

Automatic:

- Linear issue detection
- issue workspace creation
- Codex execution
- branch and PR creation
- CI result collection

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

### dayflow-orchestrator

- routes work to the correct agent path
- enforces DayFlow handoff rules
- keeps multi-agent issues sequential

### Project Agents

- `product-agent`
- `backend-agent`
- `ios-agent`
- `integration-agent`
- `review-agent`

## State Machine

### Todo

- not executable yet
- may be underspecified or still under product discussion

### Ready

- Symphony may execute automatically
- must satisfy all ready criteria

### In Progress

- workspace exists
- Codex is actively working the issue

### In Review

- PR is open
- review findings are being addressed

### Blocked

- external approvals or missing details prevent progress

### Done

- changes merged
- follow-up issues created if needed

## Ready Criteria

An issue is `Ready` only if:

- title follows `[Agent] short task description`
- `Primary Agent` is exactly one value
- `Inputs` references specific docs or files
- `Done When` has 2 to 5 concrete checks
- `Out of Scope` is filled in
- the work should land in one PR

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
- The first Git action in any workspace is creating or switching to `codex/<issue-id>-<short-slug>`
- `main` is never a working branch for agent implementation
- Review Agent evaluates every PR

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

## Branch and Workspace Naming

- branch: `codex/<issue-id>-<short-slug>`
- workspace: `<workspace-root>/<issue-id>`

## Failure Handling

Move an issue to `Blocked` when:

- required secrets are missing
- local services cannot start
- docs conflict and product intent is unclear
- the issue would require splitting into smaller tasks first

## Required Supporting Artifacts

- `WORKFLOW.md`
- `docs/automation-model.md`
- `docs/harness-skill-model.md`
- `docs/iteration-queue.md`
- `docs/review-checklist.md`
- `.github/pull_request_template.md`
- `.codex/skills/dayflow-orchestrator/SKILL.md`
