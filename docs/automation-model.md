# DayFlow Automation Model

## Summary

DayFlow uses semi-automated delivery.

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

## Linear Issue Template

Use this exact body structure for every DayFlow Linear issue:

```md
## Goal

- <one issue-sized outcome>

## Primary Agent

- <exactly one of: product-agent, backend-agent, ios-agent, integration-agent, review-agent>

## Secondary Agents

- <ordered helper agents or `none`>

## Inputs

- <specific repo file, doc, contract, PR, or artifact>

## Constraints

- <must-keep boundary or `none`>

## Done When

- <observable completion check>
- <observable completion check>

## Out of Scope

- <explicit non-goal>

## Test Notes

- <how the result should be validated or `none`>

## Follow-up Issues

- <issue identifier or `none`>
```

Template rules:

- keep the section headings exactly as written so Symphony can route consistently
- use bullet lists under every section, even for a single item
- write `none` instead of leaving optional sections blank
- keep the issue self-contained enough for the Primary Agent to start without chat follow-up

## Ready Criteria

An issue is `Ready` only if:

- it is in the current Symphony pickup queue state for DayFlow (`Todo` today, `Ready` after that state exists)
- title follows `[Agent] short task description`
- the issue body uses the standard Linear issue template
- `Goal` describes one issue-sized outcome
- `Primary Agent` is exactly one value
- `Primary Agent` matches a supported DayFlow agent
- `Secondary Agents` is either `none` or a short sequential handoff list
- `Inputs` references specific docs or files
- `Constraints` records any must-keep boundaries or says `none`
- `Done When` has 2 to 5 concrete checks
- `Out of Scope` is filled in
- `Test Notes` explains how the result should be checked or says `none`
- `Follow-up Issues` lists linked issues or says `none`
- the work should land in one PR
- the issue does not satisfy any blocked criteria

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

## Blocked Criteria

Move an issue to `Blocked` when:

- the issue body is missing required sections or still contains placeholders such as `TBD`
- required secrets are missing
- local services cannot start
- another unfinished issue or manual approval must happen first
- docs conflict and product intent is unclear
- the issue would require splitting into smaller tasks first
- the work no longer fits one PR or one Primary Agent owner

## Required Supporting Artifacts

- `WORKFLOW.md`
- `docs/automation-model.md`
- `docs/iteration-queue.md`
- `docs/review-checklist.md`
- `.github/pull_request_template.md`
- `.codex/skills/dayflow-orchestrator/SKILL.md`
