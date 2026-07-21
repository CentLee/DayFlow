# DayFlow Harness Engineering

The harness is maintained as product engineering infrastructure. Its purpose is to close small Linear issues with clear ownership, bounded model use, reproducible proof, and human-controlled merges.

## Principles

### Audit Before Expansion

Compare agent definitions, skills, issue metadata, runner behavior, CI, and docs before adding a new layer. Remove conflicting rules instead of documenting both.

### One Lifecycle Owner

Each issue has one Primary Agent. Sequential integration or review handoff is allowed; parallel fan-out is not the default. The owner returns for review remediation on the same session and branch.

### Models Follow Leverage

Use `gpt-5.6-sol/high` for product, integration, and review decisions. Use `gpt-5.6-terra/medium` for bounded backend and iOS implementation. Deterministic Git, Linear, proof, and webhook operations use shell logic and no model tokens.

### Fail Closed and Preserve Work

Admission, ownership, model, token, time, delivery, and review guards stop unsafe continuation. They do not erase worktrees or silently retry. Recovery is an explicit operator action.

### Progressive Disclosure

Keep agent definitions and skills short. Put operational detail in `docs/local-runner.md`, deterministic behavior in `scripts/lib/dayflow_runner.sh`, and executable expectations in tests.

### Local State Is Local

Only logic and policy are tracked. Credentials, sessions, worktrees, logs, dedupe state, and machine configuration live under ignored `.dayflow/`.

## Maintenance Flow

1. Run `scripts/audit_harness_drift.sh`.
2. Confirm the issue meets admission and one-PR scope.
3. Change runtime behavior and authoritative docs together.
4. Run `scripts/tests/run_dayflow_runner_tests.sh` and relevant product tests.
5. Apply `docs/review-checklist.md` before declaring merge readiness.

## Required Repository Truth

- `AGENTS.md`
- `docs/automation-model.md`
- `docs/local-runner.md`
- `docs/failure-taxonomy.md`
- `docs/git-tracking-policy.md`
- `docs/review-checklist.md`
- `.codex/agents/` and `.codex/skills/`
- `scripts/dayflow_runner.sh`, its library, tests, and drift audit

## Non-Goals

- a generic multi-project orchestration platform
- resident local services for issue pickup
- hidden machine-only patches
- automated merging without human approval
- agent taxonomies larger than the MVP needs
