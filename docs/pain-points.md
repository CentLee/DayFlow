# DayFlow Automation Pain Points

## Purpose

DayFlow reached a stage where a resident external runner could start work, open PRs, and trigger review, but the
full lifecycle still needed manual rescue. This document records the concrete failures seen during
`CEN-11` and `CEN-12` so the workflow can be simplified before more feature work continues.

## Pain Points

### Split implementation and review lanes added too much orchestration overhead

- separate long-lived runtimes meant state, PR status, and ownership could drift apart
- a stopped review process looked like a workflow bug, even when the issue state itself was correct
- implementation could accidentally move on to the next issue while review work was still unresolved

### Review feedback did not reliably return to the same issue owner

- findings were posted, but the path back to `In Progress` and draft PR state was inconsistent
- fixing review comments often required manual state changes or manual PR toggles
- this broke the expected lifecycle contract of "one issue, one owner until merge-ready"

### Proof-of-work was promised earlier than it was enforced

- PR templates existed, but the content was not refreshed automatically
- CI results, addressed findings, and complexity snapshots had to be reconstructed by hand
- reviewers still had to infer too much from raw comments and diffs

### Current contract and target contract were mixed together

- docs sometimes described the desired payload instead of the current mock/backend truth
- review surfaced one mismatch at a time, causing repeated reopen cycles
- current behavior must be documented first, with forward-looking gaps made explicit

### Debugging the runtime became harder than debugging the product code

- process liveness and lane routing became recurring sources of confusion
- the system spent too much energy coordinating runners rather than closing issues

## New Operating Principles

### One issue, one lifecycle owner

- the primary agent owns the issue branch from first commit through review follow-up
- review findings return to that same owner until the PR is merge-ready

### The orchestrator coordinates, but does not close issues itself

- the top-level orchestrator decides routing, sequencing, and queue order
- it should not become the manual fallback for every review iteration

### Proof-of-work is a lifecycle artifact, not optional formatting

- changed files, checks, review feedback addressed, and complexity should be kept current on the PR

### Current truth comes before target truth

- `docs/api-contract.md` should describe today's served or mocked contract
- forward-looking gaps belong in explicit notes or follow-up issues

## Implemented Consequence

DayFlow now uses one explicit `scripts/dayflow_runner.sh` invocation per issue. The command owns bounded execution, proof validation, review remediation, and deterministic reconciliation, then exits. Review remains required without a separate resident lane.
