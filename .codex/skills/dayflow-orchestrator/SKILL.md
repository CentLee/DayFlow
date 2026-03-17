---
name: dayflow-orchestrator
description: "Routes DayFlow work across product, backend, iOS, integration, and review agents using a pipeline plus fan-out/fan-in workflow."
---

# DayFlow Orchestrator

Use this skill when coordinating multi-step DayFlow work.

## Workflow

1. Start with product or contract truth in `docs/`.
2. Route to the smallest valid agent scope.
3. Prefer one primary agent per issue.
4. Allow a small vertical slice only when the API contract is already stable and the handoff can stay sequential.
5. Finish every PR with review.

## Execution Gate

Treat an issue as auto-runnable only if:

- `Primary Agent` is present
- `Inputs` are present
- `Done When` is concrete
- the work fits in one PR

If any of those are missing, route it back for clarification instead of expanding scope during implementation.

## Routing Guide

- product scope or Excel-derived UX: `product-agent`
- Go or migration work: `backend-agent`
- SwiftUI or client state: `ios-agent`
- contract or sync alignment: `integration-agent`
- final validation: `review-agent`

## Handoff Rules

- do not fan out multiple agents in parallel inside one issue
- use sequential handoff when an issue needs more than one agent lens
- keep budget privacy and calendar sharing boundaries explicit throughout the flow
