# DayFlow Agents

This repository is designed for Codex-based agent execution.

## Directory Rules

- Agent definitions live in `.codex/agents`
- Skills live in `.codex/skills`
- Shared product and technical specs live in `docs`
- Reusable harness skills are expected to live in the operator's global `~/.codex/skills`
- This repository stores only the DayFlow-specific agent and skill layer

## Team Workflow

1. `dayflow-orchestrator` routes issue work to the smallest valid agent scope and uses the direct PR workflow; it never dispatches or resumes model sessions.
2. Global harness skills provide reusable orchestration patterns, while DayFlow agents apply those patterns to this domain.
3. Product Agent writes or updates product-facing specs from user needs and the Excel-derived budget model.
4. Backend, iOS, and Integration Agents implement against agreed contracts, usually as single-agent issues.
5. Implementation work follows `.codex/skills/dayflow-implementation/SKILL.md`: narrow discovery, minimum coherent diff, focused tests, and no speculative architecture.
6. Small vertical slices may use sequential handoff across agents when the contract is already stable.
7. The primary agent owns an issue through review follow-up until the PR is merge-ready; the orchestrator does not implement issue code.
8. Review Agent validates every PR for simplicity, API consistency, privacy boundaries, and test coverage, but does not replace lifecycle ownership.

## Constraints

- Keep tasks small and issue-sized.
- Linear records priority and dependencies, but a human starts the next task after checking blockers and the current PR queue.
- Prefer documentation and contract clarity before implementation.
- Budget remains personal-only in MVP.
- Calendar sharing remains calendar-level in MVP.
- Do not introduce Kubernetes or hosted-only infrastructure.
- Do not introduce Symphony, a resident local service, or a port 4100 control plane.

## Required References

- `docs/product-spec.md`
- `docs/domain-model.md`
- `docs/api-contract.md`
- `docs/ios-architecture.md`
- `docs/sync-model.md`
- `docs/development-workflow.md`
- `docs/iteration-queue.md`
- `docs/review-checklist.md`
