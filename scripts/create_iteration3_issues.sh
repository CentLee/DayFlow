#!/usr/bin/env bash
set -euo pipefail

if [[ -z "${LINEAR_API_KEY:-}" ]]; then
  echo "LINEAR_API_KEY is required" >&2
  exit 1
fi

TEAM_ID="6f6e5287-d893-439d-981f-94d73ccd720a"
PROJECT_ID="fdeb5f63-05f2-4ab2-bb9d-a12dc0084b9f"
TODO_STATE_ID="452888e8-7d81-4229-bf16-d0876c3098a3"

QUERY=$(cat <<'EOF'
mutation CreateIssue($team: String!, $project: String!, $state: String!, $title: String!, $description: String!) {
  issueCreate(input: {
    teamId: $team,
    projectId: $project,
    stateId: $state,
    title: $title,
    description: $description
  }) {
    success
    issue {
      identifier
      title
    }
  }
}
EOF
)

create_issue() {
  local title="$1"
  local description="$2"
  local payload

  payload=$(jq -n \
    --arg query "$QUERY" \
    --arg team "$TEAM_ID" \
    --arg project "$PROJECT_ID" \
    --arg state "$TODO_STATE_ID" \
    --arg title "$title" \
    --arg description "$description" \
    '{query: $query, variables: {team: $team, project: $project, state: $state, title: $title, description: $description}}')

  curl -s https://api.linear.app/graphql \
    -H "Content-Type: application/json" \
    -H "Authorization: ${LINEAR_API_KEY}" \
    --data "$payload"

  printf '\n'
}

create_issue "[Product] finalize monthly budget board edit rules" "$(cat <<'EOF'
Goal:
Lock the MVP edit rules for the monthly budget board based on the Excel-driven behavior.

Primary Agent:
product-agent

Secondary Agents:
integration-agent

Inputs:
- docs/product-spec.md
- docs/domain-model.md
- docs/api-contract.md
- docs/ios-architecture.md

Constraints:
- Preserve the Excel-inspired monthly board interaction model
- Keep the MVP focused on fixed items, variable buckets, reminders, and KPI summary
- Separate current behavior from future enhancements

Done When:
- fixed item, variable bucket, and reminder edit rules are explicit
- KPI assumptions are documented as current product truth
- forward-looking gaps are moved to follow-up notes

Out of Scope:
- backend schema changes

Test Notes:
- Document-only issue

Follow-up Issues:
- [Backend] connect budget storage to PostgreSQL
EOF
)"

create_issue "[Backend] connect budget storage to PostgreSQL" "$(cat <<'EOF'
Goal:
Back the budget domain with PostgreSQL storage for months, items, buckets, and reminders.

Primary Agent:
backend-agent

Secondary Agents:
integration-agent

Inputs:
- docs/domain-model.md
- docs/api-contract.md
- services/api/migrations

Constraints:
- Owner-only budget data access
- Keep the schema understandable for a single developer
- Preserve month snapshot semantics

Done When:
- budget storage tables exist in migrations
- storage layer reads and writes budget entities from PostgreSQL
- tests cover storage behavior and ownership boundaries

Out of Scope:
- iOS UI changes

Test Notes:
- Run Go tests for storage and migration logic

Follow-up Issues:
- [Backend] implement budget month read and write endpoints
EOF
)"

create_issue "[Backend] implement budget month read and write endpoints" "$(cat <<'EOF'
Goal:
Implement the budget month read/write API for the monthly board.

Primary Agent:
backend-agent

Secondary Agents:
integration-agent

Inputs:
- docs/api-contract.md
- services/api/internal

Constraints:
- Return the full board payload in one read call
- Enforce owner-only access
- Keep update semantics simple for MVP

Done When:
- GET /v1/budget/months/{yyyy-mm} works
- PUT /v1/budget/months/{yyyy-mm} works
- tests cover summary and write behavior
- access control is enforced

Out of Scope:
- template editing endpoints

Test Notes:
- Run Go endpoint tests

Follow-up Issues:
- [iOS] connect budget board to live API
EOF
)"

create_issue "[Backend] implement budget template endpoints" "$(cat <<'EOF'
Goal:
Implement budget template endpoints for fixed/default monthly items.

Primary Agent:
backend-agent

Secondary Agents:
integration-agent

Inputs:
- docs/api-contract.md
- docs/domain-model.md

Constraints:
- MVP only
- Keep templates owner-specific

Done When:
- GET /v1/budget/templates works
- PUT /v1/budget/templates works
- tests cover template persistence

Out of Scope:
- month board UI

Test Notes:
- Run Go tests for template persistence

Follow-up Issues:
- [iOS] add fixed item toggle and amount editing
EOF
)"

create_issue "[Integration] validate KPI formulas and budget payloads" "$(cat <<'EOF'
Goal:
Validate Excel-derived KPI formulas and budget payload consistency across docs and backend.

Primary Agent:
integration-agent

Secondary Agents:
product-agent, backend-agent

Inputs:
- docs/api-contract.md
- docs/sync-model.md
- docs/product-spec.md

Constraints:
- Current contract first
- Explicitly call out any current vs target gaps

Done When:
- KPI payload examples match backend responses
- Excel-derived formula assumptions are explicit
- mismatch list is empty or clearly documented

Out of Scope:
- SwiftUI layout changes

Test Notes:
- Compare payload examples and formula expectations

Follow-up Issues:
- [iOS] connect budget board to live API
EOF
)"

create_issue "[iOS] connect budget board to live API" "$(cat <<'EOF'
Goal:
Connect the budget board screen to the live API instead of local-only sample data.

Primary Agent:
ios-agent

Secondary Agents:
integration-agent

Inputs:
- docs/ios-architecture.md
- docs/api-contract.md
- apps/ios/DayFlow

Constraints:
- Keep session bootstrap and budget load aligned
- Preserve loading and error visibility

Done When:
- budget board loads from live API
- loading and API error states are visible
- session bootstrap keeps calendar and budget loading in sync

Out of Scope:
- inline editing polish

Test Notes:
- Run available Xcode project generation checks

Follow-up Issues:
- [iOS] add fixed item toggle and amount editing
EOF
)"

create_issue "[iOS] add fixed item toggle and amount editing" "$(cat <<'EOF'
Goal:
Add inline fixed item toggles and amount editing to the monthly budget board.

Primary Agent:
ios-agent

Secondary Agents:
integration-agent

Inputs:
- docs/ios-architecture.md
- budget month endpoints

Constraints:
- Fast input first
- One-screen monthly editing flow

Done When:
- fixed items can be toggled inline
- fixed item amounts can be edited inline
- dirty/save state is visible

Out of Scope:
- variable bucket editing

Test Notes:
- Add focused store/view-model tests where possible

Follow-up Issues:
- [iOS] add variable bucket editing and save status
EOF
)"

create_issue "[iOS] add variable bucket editing and save status" "$(cat <<'EOF'
Goal:
Add variable bucket editing and visible save/retry state to the budget board.

Primary Agent:
ios-agent

Secondary Agents:
integration-agent

Inputs:
- docs/ios-architecture.md
- budget month endpoints
- docs/sync-model.md

Constraints:
- Keep optimistic update behavior simple
- Roll back cleanly on API failure

Done When:
- variable buckets can be edited inline
- save or retry state is visible
- rollback behavior matches sync assumptions

Out of Scope:
- sharing UI

Test Notes:
- Add focused store/view-model tests where possible

Follow-up Issues:
- [Review] verify Excel-derived budget behavior
EOF
)"

create_issue "[Review] verify Excel-derived budget behavior" "$(cat <<'EOF'
Goal:
Review Iteration 3 budget PRs against the Excel-derived behavior and MVP constraints.

Primary Agent:
review-agent

Secondary Agents:
product-agent

Inputs:
- Iteration 3 PRs
- docs/review-checklist.md
- docs/product-spec.md

Constraints:
- Findings should prioritize behavior drift, privacy issues, and missing tests

Done When:
- budget PRs are reviewed against Excel-derived behavior
- blocking findings are documented
- residual manual Xcode verification risks are summarized

Out of Scope:
- new feature implementation

Test Notes:
- Review-only issue

Follow-up Issues:
- iteration 4 planning
EOF
)"
