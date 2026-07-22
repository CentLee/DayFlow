# DayFlow Git Tracking Policy

## Track in Git

Shared engineering truth belongs in the repository:

- `AGENTS.md` and `docs/*.md` policy, product, architecture, and contracts
- `.codex/agents/*.md` and `.codex/skills/**`
- `scripts/dayflow_runner.sh`, its library, schema, tests, and drift audit
- CI workflows and PR/issue templates
- product source, migrations, and deterministic test fixtures

## Keep Local

Machine state, credentials, and generated output must stay untracked:

- `.dayflow/worktrees/`, `.dayflow/state/`, `.dayflow/logs/`, `.dayflow/gh/`, and `.dayflow/notifications.env`
- `.env*`, API keys, webhook URLs, and account-scoped CLI authentication
- build output, DerivedData, coverage output, and user-specific Xcode state
- temporary HTML reviews and one-off audit exports

The ignored legacy `.symphony/` directory remains only to protect CEN-28 and copy existing local auth/notification state during first-run migration. New execution never writes there, and the source is not deleted by the runner.

## Review Rule

Track a file only when another operator needs it for reproducible behavior, it represents stable policy or source, and it is safe for every collaborator. Runtime evidence belongs in the PR proof summary, not in committed state files.
