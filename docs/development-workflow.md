# DayFlow Development Workflow

DayFlow uses the standard Codex and GitHub PR flow. There is no project-owned
agent dispatcher, session runner, token budget manager, worktree service, or
automatic model-review loop.

## Task Context

Each implementation task supplies only the goal, done conditions, out-of-scope
boundary, allowed files, relevant contract excerpts, and required tests. The
primary agent creates one focused branch and PR. Product or contract ambiguity
is resolved before implementation, not through an orchestration retry loop.

## Deterministic Gates

- Git enforces isolated branches and reviewable diffs.
- GitHub Actions runs repository tests and checks.
- Pull requests record the changed behavior, tests, and residual risks.
- A human decides scope changes and merge readiness.
- The merged-PR workflow may update the matching Linear issue and notify
  Discord; it never launches or resumes a model.

## Agent Use

Use the smallest valid agent. Backend and iOS work default to Terra/medium;
product, contract, and review decisions use Sol/high only when the decision
cannot be made from the named contract. Review reads the PR diff, supplied test
results, and only relevant contract sections.

## Archived Automation

The former local runner and supervisor remain in Git history while preserved
workspaces are retired. They are not an approved execution path for new work.
