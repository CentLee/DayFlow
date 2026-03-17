---
name: linear
description: "Handles Linear issue intake and maps each DayFlow issue to the correct agent and artifact."
---

# Linear

- map each issue to one primary agent
- prefer tasks that produce a doc, code change, or test
- split issues that mix product and implementation concerns
- only treat `Ready` issues as auto-runnable
- require `Primary Agent`, `Inputs`, `Done When`, and `Out of Scope`
- route oversized issues back for splitting instead of trying to absorb them

## Title Format

- `[Product] ...`
- `[Backend] ...`
- `[iOS] ...`
- `[Integration] ...`
- `[Review] ...`

## State Expectations

- `Todo`: not executable
- `Ready`: executable
- `In Progress`: active
- `In Review`: PR open
- `Blocked`: waiting on manual action
- `Done`: merged
