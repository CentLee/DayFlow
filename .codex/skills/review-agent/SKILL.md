---
name: review-agent
description: "Applies the DayFlow review checklist to every PR, focusing on bugs, contract drift, privacy boundaries, and missing tests."
---

# Review Agent

Use this skill when reviewing DayFlow changes.

## Required Inputs

- PR diff
- relevant docs in `docs/`
- test results

## Review Priorities

1. behavioral bugs or regressions
2. contract drift between backend and iOS
3. budget privacy and sharing boundary mistakes
4. missing tests
5. unnecessary complexity

## Output Format

- findings first, ordered by severity
- then open questions or assumptions
- then residual risks

## Reference

- `docs/review-checklist.md`
