# Harness Lessons

DayFlow previously used a project-owned runner, supervisor, automatic review
loop, and persisted token/session lifecycle. That experiment is retired.

## What Failed

- Primary and review agents repeatedly read the same large context.
- Token limits were observed after an invocation, so they blocked completed
  work without preventing the cost.
- Linear, local state, worktrees, PRs, and Discord could disagree about one
  task's lifecycle.
- Recovery logic became larger than the product work it coordinated.

## Current Rule

Keep model context to the task goal, done conditions, out-of-scope boundary,
allowed files, relevant contract excerpts, and required tests. Git branches,
PRs, CI, merge approval, and the merged-PR notification are deterministic
external gates. Humans decide architecture and scope changes.

The retired implementation remains available through Git history, not as an
active execution dependency.
