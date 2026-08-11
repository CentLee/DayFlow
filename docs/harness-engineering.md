# DayFlow Harness Engineering

The harness is maintained as product engineering infrastructure. Its purpose is to close small Linear issues with clear ownership, bounded model use, reproducible proof, and human-controlled merges.

## Principles

### Audit Before Expansion

Compare agent definitions, skills, issue metadata, runner behavior, CI, and docs before adding a new layer. Remove conflicting rules instead of documenting both.

### One Lifecycle Owner

Each issue has one Primary Agent. Sequential integration or review handoff is allowed, and queue dispatch is sequential by default. At most two separate issues may overlap only when each is explicitly `Parallel Safe` with a non-empty, nonoverlapping `Write Scope`. The owner returns for review remediation on the same branch in a fresh bounded session.

### Models Follow Leverage

Use `gpt-5.6-terra/high` for product, integration, and review decisions and `gpt-5.6-terra/medium` for bounded backend and iOS implementation. There is no alternate-model fallback. Deterministic Git, Linear, proof, and webhook operations use shell logic and no model tokens.

### Fail Closed and Preserve Work

Admission, ownership, model, token, time, delivery, and review guards stop unsafe continuation. They do not erase worktrees or silently retry. Recovery is an explicit operator action.

Publication transport recovery is the bounded exception: persisted deterministic phases may resume commit publication, push, or PR creation without invoking Codex again. Integrity mismatches still fail closed. Model output contributes only validated structured test evidence; lifecycle code never executes model-provided commands and model subprocesses receive no lifecycle credentials.

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

Keep the supervisor as a one-shot dependency-aware cycle. Supported unattended pickup uses `start` to atomically persist only the required credential and effective PATH in canonical ignored state with mode `0600`; launchd loads that file before the supervisor library and never sources interactive shell startup files. Do not add secrets to the plist, logs, status output, or git, and do not add a resident service, local HTTP control plane, Symphony dependency, or port 4100 listener. Queue selection must remain deterministic and must delegate issue execution and resource enforcement to the runner.

## Required Repository Truth

- `AGENTS.md`
- `docs/automation-model.md`
- `docs/local-runner.md`
- `docs/failure-taxonomy.md`
- `docs/git-tracking-policy.md`
- `docs/review-checklist.md`
- `.codex/agents/` and `.codex/skills/`
- `scripts/dayflow_runner.sh`, `scripts/dayflow_supervisor.sh`, their libraries, tests, and drift audit

## Non-Goals

- a generic multi-project orchestration platform
- resident local services or HTTP listeners for issue pickup
- hidden machine-only patches
- automated merging without human approval
- agent taxonomies larger than the MVP needs
