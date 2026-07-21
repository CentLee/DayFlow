# DayFlow Harness Engineering

This document defines the DayFlow harness engineering baseline.

It borrows the strongest reusable ideas from the external Harness project while adapting them to the DayFlow Codex runtime, single-lane ownership model, and token-efficiency constraints.

## Purpose

DayFlow does not treat its harness as a one-time bootstrap artifact.
The harness is part of the product engineering system and must evolve when:

- issue quality drifts
- agent boundaries become ambiguous
- token cost becomes wasteful
- review loops become unreliable
- docs and automation stop matching

## Adapted Principles

### 1. Audit Before Expansion

Every harness change starts by auditing the current state before adding new agents, skills, or rules.

Audit targets:

- `.codex/agents/`
- `.codex/skills/`
- `WORKFLOW.md`
- core docs in `docs/`
- harness scripts in `scripts/`

The first question is not "what should we add?"
The first question is "what already exists, and where is it drifting?"

### 2. Team Architecture Is a Design Choice

DayFlow keeps a small, opinionated architecture instead of adding agents freely.

Current preferred structure:

- one primary agent per issue
- sequential handoff only when needed
- review always happens before merge readiness

Harness patterns are still useful as a reasoning tool:

- pipeline for dependent phases
- producer-reviewer for implementation plus review
- expert-pool thinking for selective consultation
- supervisor thinking for outer-loop state reconciliation

DayFlow does not adopt multi-agent fan-out inside a single issue by default because ownership clarity and token efficiency matter more than maximal parallelism.

### 3. Stronger Models Belong at High-Leverage Decision Points

Model selection is part of harness design, not an implementation detail.

Use higher-capability models for:

- product definition
- contract alignment
- review and risk detection
- ambiguous architecture decisions

Use medium-capability models for:

- bounded backend implementation
- bounded iOS implementation
- predictable refactors
- small follow-up fixes after review

### 4. Progressive Disclosure Is Mandatory

Keep the active prompt layer small.

Rules:

- short skill body first
- deeper detail in `references/`
- repetitive deterministic work in `scripts/`
- avoid duplicating the same rules in agent files, skills, docs, and workflow unless the duplication serves a different runtime boundary

### 5. Drift Must Be Treated as an Engineering Problem

Drift includes:

- docs no longer matching workflow behavior
- workflow no longer matching scripts
- agent boundaries no longer matching issue templates
- skills mentioning files or rules that no longer exist
- local-only runtime rules silently replacing repo truth

Drift is not housekeeping.
It is a reliability problem.

### 6. Runtime Guardrails Should Reduce Retries, Not Hide Failures

When a run fails, the harness should:

1. stop wasteful repetition
2. preserve useful artifacts
3. restore correct ownership state
4. signal whether the issue should retry, continue, or block

The harness should not silently convert every failure into a fresh retry.

### 7. Local Secrets and Runtime State Stay Out of Git

DayFlow keeps runtime-local state out of version control.

Examples:

- `.symphony/gh/`
- `.symphony/workspaces/`
- `.symphony/notifications.env`
- local auth/session material
- generated runtime logs

The repo should contain the harness logic and policy, not personal machine state.

## Operating Modes

Harness work should explicitly fall into one of three modes.

### New Build

Use when the repository has no meaningful harness structure yet.

Expected work:

- define agent set
- define orchestrator
- define core skills
- define workflow rules

### Existing Expansion

Use when the harness exists and needs additional capability.

Expected work:

- add or adjust one agent
- add or adjust one skill
- update orchestrator routing
- verify no overlap or drift is introduced

### Maintenance / Audit

Use when the harness is already in active use and needs correction, alignment, or cleanup.

Expected work:

- drift review
- doc/script alignment
- token-efficiency improvements
- state-machine corrections
- tracking policy cleanup

## Required Repository Truth

The following files define the DayFlow harness baseline and should stay aligned:

- `WORKFLOW.md`
- `docs/automation-model.md`
- `docs/symphony-setup.md`
- `docs/harness-skill-model.md`
- `docs/review-checklist.md`
- `.codex/skills/dayflow-orchestrator/SKILL.md`
- `.codex/agents/*.md`
- `scripts/run_symphony.sh`
- state reconciliation and guard scripts in `scripts/`

## Change Discipline

When changing the harness:

1. update the runtime behavior first if the current behavior is actively wasteful or incorrect
2. update the authoritative docs in the same change
3. keep local-only configuration out of git
4. prefer removing duplicate rules over adding another copy
5. verify shell syntax for any changed harness script

## Non-Goals

DayFlow harness engineering should not drift into:

- generic multi-project framework design inside this repo
- tool-specific hype without runtime payoff
- large agent taxonomies that exceed the MVP scope
- hidden local patches that are not reflected in repo policy
