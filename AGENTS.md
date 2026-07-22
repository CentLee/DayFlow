# DayFlow Agents

This repository is designed for Codex-based agent execution.

## Directory Rules

- Agent definitions live in `.codex/agents`
- Skills live in `.codex/skills`
- Shared product and technical specs live in `docs`
- Reusable harness skills are expected to live in the operator's global `~/.codex/skills`
- This repository stores only the DayFlow-specific agent and skill layer

## Team Workflow

1. `dayflow-orchestrator` routes issue work to the smallest valid agent scope and invokes the local runner.
2. Global harness skills provide reusable orchestration patterns, while DayFlow agents apply those patterns to this domain.
3. Product Agent writes or updates product-facing specs from user needs and the Excel-derived budget model.
4. Backend, iOS, and Integration Agents implement against agreed contracts, usually as single-agent issues.
5. Small vertical slices may use sequential handoff across agents when the contract is already stable.
6. The primary agent owns an issue through review follow-up until the PR is merge-ready; the orchestrator does not implement issue code.
7. Review Agent validates every PR for simplicity, API consistency, privacy boundaries, and test coverage, but does not replace lifecycle ownership.

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
- `docs/local-runner.md`
- `docs/automation-model.md`
- `docs/iteration-queue.md`
- `docs/review-checklist.md`
