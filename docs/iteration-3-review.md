# Iteration 3 Review

## Scope Reviewed

Reviewed Iteration 3 budget-board work across these merged PRs:

- `#13` finalize monthly budget board rules
- `#15` connect budget storage to PostgreSQL
- `#17` add budget month endpoints
- `#28` connect budget board to live API
- `#29` add fixed item toggle and amount editing
- `#30` add variable bucket editing and save status

## Excel-Derived Behavior Check

Checked against the Excel-derived MVP rules in `docs/product-spec.md` and the iOS sync assumptions in
`docs/sync-model.md`.

Confirmed behavior:

- monthly budget editing stays centered on one month-board screen
- KPI values remain derived rather than directly overridden on the board
- fixed items support inline `enabled` and `amount` edits for the current month snapshot
- variable buckets remain bucket-based instead of expanding into transaction rows
- budget edits stay private to the owner and do not inherit calendar sharing
- optimistic save, rollback, dirty state, and retry state are now wired through the iOS budget flow

## Findings

- no blocking findings found in the merged Iteration 3 changes

## Open Questions Or Assumptions

- assume the current KPI formulas in backend and iOS match the documented contract because the served payload shape and sync rules now align
- assume template-driven structure limits remain acceptable for MVP because inline add/delete/reorder is still intentionally out of scope

## Residual Risks

- simulator-backed iOS verification is still a manual Xcode step because the current Codex runtime cannot rely on `CoreSimulatorService`
- real device or local Xcode verification is still needed for keyboard/input feel, retry affordances, and end-to-end save latency against the local API
- a future regression test pass should add broader end-to-end budget flow coverage once simulator execution is reliable in automation

## Manual Verification Focus

When running the app locally in Xcode, verify:

- budget board loads the current month from the live API
- fixed item toggle and amount edits update KPI cards immediately
- variable bucket planned and actual edits update visible save state correctly
- failed saves surface retry state without losing the last confirmed server snapshot
- budget privacy remains separate from shared calendar membership
