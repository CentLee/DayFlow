# DayFlow Runner Failure Taxonomy

Every failure is handled in this order: stop resource waste, preserve useful work, restore truthful state, notify the operator, and require a deliberate retry.

## Failure Classes

### F1. Admission Failure

Required issue metadata is absent, malformed, or names an unsupported Primary Agent. The issue is blocked before a worktree or model execution is created.

### F2. Ownership Failure

An `In Progress` or `In Review` issue lacks a state file, worktree, matching branch, or Primary Agent session. Resume fails closed; the runner never creates a replacement workspace over possible work.

### F3. Model Failure

The configured model is unavailable, rejected, or inaccessible. No fallback is attempted. The worktree is retained and the issue moves to `Blocked` when that Linear state exists.

### F4. Resource Limit

Aggregate tokens exceed 120K, output makes no progress for five minutes, or an invocation reaches 20 minutes. The Codex child is terminated and the issue is blocked with local evidence.

### F5. Delivery Failure

The Primary Agent completes without the correct branch, commit, push, develop-targeted PR, or proof sections. The incomplete workspace is preserved and the issue is blocked.

### F6. Review Failure

P0-P2 findings trigger one same-session remediation. Remaining blockers after rereview stop the run. P3 findings and residual risks remain visible but do not automatically block.

### F7. Reconciliation Failure

Linear, GitHub, or Discord is temporarily unavailable. Local state remains authoritative for ownership, external mutation is not guessed, and local `reconcile` can be rerun after service recovery. For the merged-PR GitHub workflow, a failed Discord delivery leaves no success marker and the failed job is retryable; a prior `Done` transition is detected instead of repeated.

### F8. Lock Conflict

A live per-issue lock rejects concurrent execution. A lock whose PID no longer exists is recovered without touching the worktree.

## Reusable Rules

- only `Todo` creates new work
- resumable work requires explicit local ownership state
- dirty or committed work is never silently deleted
- deterministic state and notification work stays outside model prompts
- every execution has token, progress, and wall-clock bounds
- a blocked issue requires operator intent before retry
