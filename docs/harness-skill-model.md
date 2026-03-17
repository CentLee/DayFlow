# Harness Skill Model

DayFlow uses a two-layer skill model.

## Global Layer

The reusable harness layer lives outside this repository in the operator's global Codex home:

- `~/.codex/skills`

This layer is expected to contain:

- orchestration patterns
- agent-design conventions
- task decomposition rules
- review and proof-of-work patterns
- any reusable company or personal harness logic

## Project Layer

The DayFlow repository keeps only the project-specific layer:

- `.codex/agents`
- `.codex/skills`

This layer should stay thin and contain only:

- DayFlow domain rules
- DayFlow routing hints
- DayFlow-specific implementation constraints
- DayFlow UX and privacy boundaries

## Rule for New Skills and Agents

When a new skill or agent is needed, use this split:

- if the pattern is reusable across projects, add or evolve it in the global harness layer
- if the pattern only exists because of DayFlow domain requirements, keep it in this repository

## Why This Split Exists

- avoids copying private or evolving harness internals into public repositories
- keeps DayFlow reproducible without forcing the repo to contain every global skill
- lets the harness improve over time without rewriting each project repository
