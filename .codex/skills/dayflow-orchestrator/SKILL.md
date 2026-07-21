---
name: dayflow-orchestrator
description: "Coordinates DayFlow harness work and issue execution. Use for harness audit, harness engineering, agent/skill drift review, orchestrating DayFlow product/backend/iOS/integration/review work, or when asked to restructure how the DayFlow agent system operates."
---

# DayFlow Orchestrator

Use this skill when coordinating multi-step DayFlow work or maintaining the DayFlow harness itself.

## Operating Principle

The harness is an evolving engineering system, not a fixed bootstrap artifact.
Before adding agents, skills, or workflow rules, audit the current system and identify drift.

## Phase 0: Harness Audit

Start here for any harness engineering, maintenance, or suspicious workflow behavior.

Read and compare:

- `WORKFLOW.md`
- `docs/automation-model.md`
- `docs/symphony-setup.md`
- `docs/harness-engineering.md`
- `.codex/agents/`
- `.codex/skills/`
- relevant `scripts/`

Classify the request:

- new capability
- existing capability expansion
- maintenance / drift correction

Check for drift across:

- docs vs workflow prompt
- workflow prompt vs scripts
- agent role definitions vs issue template expectations
- skill instructions vs actual repository paths

If drift exists, fix alignment before expanding scope.

## Phase 1: Scope and Architecture Choice

Route to the smallest valid agent scope.

Default DayFlow architecture:

- one primary agent per issue
- sequential handoff only when needed
- review before merge readiness

Use architecture-pattern reasoning only as support:

- pipeline for strongly dependent phases
- producer-reviewer for implementation plus review
- expert-pool thinking for selective consultation
- supervisor thinking for outer-loop guards and reconciliation

Do not introduce parallel multi-agent fan-out inside one issue unless the user-facing outcome is small, stable, and the handoff remains sequential in practice.

## Phase 2: Execution Gate

Treat an issue as auto-runnable only if:

- `Primary Agent` is present
- `Inputs` are present
- `Done When` is concrete
- `Out of Scope` is present
- the work fits in one PR

If any of those are missing, block or clarify instead of expanding scope during implementation.

## Phase 3: Model Posture

Match model strength to task leverage:

- high-capability reasoning models for `product-agent`, `integration-agent`, and `review-agent`
- medium-capability implementation models for `backend-agent` and `ios-agent`
- escalate implementation work to a stronger model only when contracts, product rules, or risk analysis are still ambiguous

Do not spend top-tier model budget on deterministic or repetitive implementation work once the contract is stable.

## Routing Guide

- product scope or Excel-derived UX: `product-agent`
- Go or migration work: `backend-agent`
- SwiftUI or client state: `ios-agent`
- contract or sync alignment: `integration-agent`
- final validation: `review-agent`

## Phase 4: Handoff Rules

- do not fan out multiple agents in parallel inside one issue
- use sequential handoff when an issue needs more than one agent lens
- keep budget privacy and calendar sharing boundaries explicit throughout the flow
- preserve the same lifecycle owner through review follow-up unless the issue is explicitly re-scoped

## Phase 5: Drift Maintenance

When working on the harness itself:

- prefer removing duplicate or conflicting rules over adding another layer of wording
- keep short operational rules in active files and move detail to supporting docs or scripts
- push repetitive deterministic work into `scripts/`
- keep local-only machine configuration out of git
- use `scripts/audit_harness_drift.sh` when checking repo-level harness alignment

## Completion Standard

A DayFlow orchestration change is complete only when:

- the runtime behavior and repo docs agree
- agent boundaries remain clear
- issue admission rules stay enforceable
- token waste is reduced or at least not worsened
- review remains a required final gate
