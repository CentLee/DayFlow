---
tracker:
  kind: linear
  api_key: $LINEAR_API_KEY
  project_slug: "fe259ecd9833"
  active_states:
    - Todo
    - In Progress
    - In Review
  terminal_states:
    - Done
    - Canceled
    - Duplicate
polling:
  interval_ms: 5000
workspace:
  root: /Users/kakao_ent/Documents/DayFlow/.symphony/workspaces
hooks:
  after_create: |
    git clone --branch codex/bootstrap-symphony-automation --single-branch https://github.com/CentLee/DayFlow.git .
  before_remove: |
    rm -rf .git
agent:
  max_concurrent_agents: 1
  max_turns: 20
codex:
  command: env GH_CONFIG_DIR=/Users/kakao_ent/Documents/DayFlow/.symphony/gh codex app-server
  approval_policy: never
  thread_sandbox: dangerFullAccess
  turn_sandbox_policy:
    mode: dangerFullAccess
server:
  port: 4100
---

You are working on a Linear issue for the DayFlow repository.

Repository context:

- Product and domain truth lives in `docs/`.
- Agent routing and skills live in `.codex/agents/` and `.codex/skills/`.
- DayFlow uses a semi-automated workflow. Implement, open or update a PR, collect proof of work, and stop at review boundaries rather than merging autonomously.

Issue context:

- Identifier: `{{ issue.identifier }}`
- Title: `{{ issue.title }}`
- State: `{{ issue.state }}`
- URL: `{{ issue.url }}`

Description:
{% if issue.description %}
{{ issue.description }}
{% else %}
No description provided.
{% endif %}

Execution rules:

1. Start with `WORKFLOW.md`, `docs/automation-model.md`, and the most relevant files under `docs/`.
2. Read the relevant project skill before changing code.
3. Before any file edit or commit, create or switch to an issue branch named `codex/<issue-id>-<short-slug>`.
4. Never implement directly on `main` or `develop`.
5. `main` is the release branch, `develop` is the integration branch, and all issue work starts from `develop`.
6. Issue PRs target `develop` and should normally be squash-merged.
7. Only stabilized `develop` changes move to `main`, using a human-reviewed merge flow.
8. Prefer one primary agent per issue.
9. A small vertical slice is allowed only when backend, iOS, and integration handoff can stay sequential.
10. Keep budget data private to the owner and never mix it with calendar sharing.
11. Every PR must satisfy the review checklist in `docs/review-checklist.md`.
12. Final reporting should contain completed work, tests run, blockers, and proof-of-work only.

Routing guide:

- product or scope changes: `product-agent`
- Go API, schema, migrations: `backend-agent`
- SwiftUI screens, state, Figma implementation: `ios-agent`
- mocks, sync, contract alignment: `integration-agent`
- review, simplicity, and risk checks: `review-agent`

State handling:

- `Todo`: runnable queue state, move to `In Progress` when active work starts
- `In Progress`: implementation phase
- `In Review`: PR is open and waiting on review or review follow-up
- `Done`: terminal
- `Canceled` and `Duplicate`: terminal

Proof-of-work sections required in PR or final report:

- Changed files
- Behavior implemented
- Tests run
- Risks or follow-ups
- Next suggested issue
