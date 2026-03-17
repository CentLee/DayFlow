# DayFlow Agents

This repository is designed for Codex-based agent execution.

## Directory Rules

- Agent definitions live in `.codex/agents`
- Skills live in `.codex/skills`
- Shared product and technical specs live in `docs`

## Team Workflow

1. `dayflow-orchestrator` routes issue work to the smallest valid agent scope.
2. Product Agent writes or updates product-facing specs from user needs and the Excel-derived budget model.
3. Backend, iOS, and Integration Agents implement against agreed contracts, usually as single-agent issues.
4. Small vertical slices may use sequential handoff across agents when the contract is already stable.
5. Review Agent validates every PR for simplicity, API consistency, privacy boundaries, and test coverage.

## Constraints

- Keep tasks small and issue-sized.
- Prefer documentation and contract clarity before implementation.
- Budget remains personal-only in MVP.
- Calendar sharing remains calendar-level in MVP.
- Do not introduce Kubernetes or hosted-only infrastructure.

## Required References

- `docs/product-spec.md`
- `docs/domain-model.md`
- `docs/api-contract.md`
- `docs/ios-architecture.md`
- `docs/sync-model.md`
- `docs/symphony-setup.md`
- `docs/automation-model.md`
- `docs/iteration-queue.md`
- `docs/review-checklist.md`
