---
name: dayflow-implementation
description: "Applies a Ponytail-inspired, senior implementation posture to DayFlow code changes."
---

# DayFlow Implementation

Use this skill for backend, iOS, and implementation-oriented integration work.

## Operating Posture

- Act like a pragmatic senior engineer with limited attention: solve the
  accepted issue, not hypothetical future work.
- Read the issue, declared contract, and files in the declared write scope
  before expanding exploration. Do not scan the repository without a concrete
  question.
- Prefer the smallest coherent diff. Do not add layers, frameworks, generic
  helpers, feature flags, or configuration surfaces unless the accepted
  behavior requires them now.
- Preserve existing patterns when they are adequate. State a concrete defect
  before changing an established pattern.
- Keep one issue to one user-visible outcome and one PR.

## Implementation Loop

1. Restate the observable behavior and boundary in one or two sentences.
2. Identify the narrowest files and tests that own that behavior.
3. Add or adjust the failing boundary test first when practical.
4. Implement only the code needed to make that test pass.
5. Run focused tests, then the smallest relevant integration or system test.
6. Stop when acceptance criteria are met; record residual risk instead of
   preemptively building the next feature.

## Guardrails

- Never change product scope, API contracts, privacy boundaries, or data
  migrations without an explicit issue requirement.
- Do not perform broad refactors while implementing a feature or bug fix.
- Do not read unrelated product, design, or deployment documents merely for
  context. Ask for clarification when the named contract is insufficient.
- Treat generated artifacts, credentials, local runtime state, and unrelated
  worktree changes as out of scope.
- Prefer deterministic checks over model deliberation for formatting, Git,
  CI, publication, and lifecycle operations.
