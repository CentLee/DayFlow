# DayFlow Git Tracking Policy

This document defines what belongs in git for the DayFlow harness and what must stay local-only.

## Track In Git

These files define shared engineering truth and should be versioned.

### Harness Policy and Workflow

- `WORKFLOW.md`
- `docs/automation-model.md`
- `docs/symphony-setup.md`
- `docs/harness-engineering.md`
- `docs/harness-skill-model.md`
- `docs/review-checklist.md`
- `docs/iteration-queue.md`

### Agent and Skill Definitions

- `.codex/agents/*.md`
- `.codex/skills/**/SKILL.md`
- `.codex/skills/**/references/*`
- any reusable bundled scripts or assets that are part of a committed skill

### Harness Runtime Logic

- `scripts/run_symphony.sh`
- `scripts/audit_harness_drift.sh`
- `scripts/validate_issue_admission.sh`
- guard, reconciliation, proof, and issue creation scripts
- `scripts/lib/*.sh`

### Product and Contract Truth

- `docs/product-spec.md`
- `docs/domain-model.md`
- `docs/api-contract.md`
- `docs/ios-architecture.md`
- `docs/sync-model.md`

## Keep Local Only

These files are machine-specific, account-specific, or runtime-state artifacts and should not be committed.

### Symphony Runtime State

- `.symphony/workspaces/`
- `.symphony/symphony.log`
- `.symphony/gh/`
- `.symphony/notifications.env`

### Secrets and Personal Machine Config

- `.env`
- `.env.local`
- GitHub auth state
- Linear API tokens
- Discord webhook URLs

### Generated Artifacts

- build outputs
- Xcode generated user state
- coverage files unless explicitly requested for committed reporting

## Review / Ad-Hoc Output

Do not keep one-off review deliverables in git unless they become stable reference material.

Usually local-only:

- temporary HTML review documents
- ad-hoc audit exports
- one-time exploratory reports

If a review result becomes part of ongoing repo truth, convert it into Markdown policy or operational documentation and commit that version instead.

## Practical Rule

When deciding whether to commit a file, ask:

1. does another operator need this file for the harness to behave correctly?
2. is it stable policy/logic rather than local runtime state?
3. is it safe to expose to every collaborator with repo access?

If any answer is no, keep it out of git.
