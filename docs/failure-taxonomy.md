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

The Primary Agent completes without valid passed-test evidence, the correct branch, commit, push, develop-targeted PR, or proof sections. Missing or malformed evidence blocks before publication. Recoverable commit/push/PR transport failures retain a deterministic publication phase for retry without another primary model call; branch, head, base, or proof mismatches block as integrity failures.

### F6. Review Failure

P0-P2 findings trigger one same-session remediation. Remaining blockers after rereview stop the run. P3 findings and residual risks remain visible but do not automatically block.

### F7. Reconciliation Failure

Linear, GitHub, or Discord is temporarily unavailable. Local state remains authoritative for ownership, external mutation is not guessed, and local `reconcile` can be rerun after service recovery. The merged-PR workflow uses a PR-comment claim as its durable delivery outbox: definite Discord rejection releases the claim for retry, while transport uncertainty or failure to mark an accepted delivery keeps the claim and requires operator reconciliation without automatic resend. Linear `Done` remains convergent and is not transitioned twice.

### F8. Lock Conflict

A live per-issue runner lock rejects concurrent execution. The supervisor also has a singleton cycle lock: a matching PID and process-start identity rejects an overlapping `once`, `reconcile`, or `cleanup`, while stale or reused identity is recovered without touching issue worktrees.

### F9. Queue Snapshot Failure

Missing dependency data, a stale or oversized Linear snapshot, pagination beyond the configured bound, or a cycle in the active blocks graph stops the cycle before dispatch. The previous snapshot remains diagnostic only and is never used to guess eligibility.

### F10. Supervisor Claim Failure

A live PID-backed claim consumes dispatch capacity. A dead claim is released only when persisted runner state is a known safe lifecycle outcome. Missing or unsafe state preserves the claim and fails closed so restart cannot duplicate uncertain work.

### F11. Cleanup Failure

Cleanup requires exact worktree ownership, runner proof of Linear `Done` and a matching merged PR into `develop`, and an empty worktree. Any failed guard preserves the workspace. CEN-28 is unconditionally excluded.

### F12. Launchd Environment Failure

`start` requires `LINEAR_API_KEY` and effective `PATH`, writes them atomically to canonical ignored state with mode `0600`, and never places them in the plist. A missing, malformed, symlinked, wrongly owned, or insecurely permissioned environment file stops the scheduled cycle before the supervisor library loads and records only a non-secret diagnostic.

## Reusable Rules

- only `Todo` creates new work
- supervisor pickup additionally requires every blocker to be `Done`
- parallel dispatch requires explicit safety and nonoverlapping write scopes, with a hard maximum of two
- resumable work requires explicit local ownership state
- dirty or committed work is never silently deleted
- deterministic state and notification work stays outside model prompts
- every execution has token, progress, and wall-clock bounds
- a blocked issue requires operator intent before retry
