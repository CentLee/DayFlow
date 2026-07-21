#!/usr/bin/env bash
set -euo pipefail

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib/dayflow_harness.sh"

require_linear_api_key
require_cmds jq curl

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
    --arg team "$DAYFLOW_LINEAR_TEAM_ID" \
    --arg project "$DAYFLOW_LINEAR_PROJECT_ID" \
    --arg state "$DAYFLOW_STATE_TODO_ID" \
    --arg title "$title" \
    --arg description "$description" \
    '{query: $query, variables: {team: $team, project: $project, state: $state, title: $title, description: $description}}')

  curl -s https://api.linear.app/graphql \
    -H "Content-Type: application/json" \
    -H "Authorization: ${LINEAR_API_KEY}" \
    --data "$payload"

  printf '\n'
}

create_issue "[Backend] extend user, invite, and session schema" "$(cat <<'EOF'
Goal:
Extend the DayFlow backend schema for invite-based auth and session handling.

Primary Agent:
backend-agent

Secondary Agents:
product-agent

Inputs:
- docs/domain-model.md
- docs/api-contract.md
- docs/product-spec.md

Constraints:
- Keep MVP scope only
- Use PostgreSQL migrations
- Preserve personal-only budget privacy

Done When:
- users, invites, and sessions schema are defined
- a new migration is added under services/api/migrations
- backend tests cover the new schema assumptions

Out of Scope:
- HTTP handler implementation
- iOS UI changes

Test Notes:
- Run Go tests for schema/store packages

Follow-up Issues:
- [Backend] implement register/login/me endpoints
EOF
)"

create_issue "[Backend] implement register, login, and me endpoints" "$(cat <<'EOF'
Goal:
Implement POST /v1/auth/register, POST /v1/auth/login, and GET /v1/me.

Primary Agent:
backend-agent

Secondary Agents:
integration-agent

Inputs:
- docs/api-contract.md
- docs/domain-model.md
- services/api/migrations

Constraints:
- Invitation-based registration only
- Use password hashing and session issuance
- Keep implementation understandable for one developer

Done When:
- register endpoint is implemented
- login endpoint is implemented
- me endpoint returns the authenticated user
- backend tests cover success and access control cases

Out of Scope:
- iOS login UI
- calendar CRUD

Test Notes:
- Run Go endpoint tests

Follow-up Issues:
- [iOS] connect auth screens and session bootstrap
EOF
)"

create_issue "[Backend] implement calendar and event CRUD foundation" "$(cat <<'EOF'
Goal:
Implement the MVP calendar, calendar_members, and event persistence plus API foundation.

Primary Agent:
backend-agent

Secondary Agents:
integration-agent

Inputs:
- docs/domain-model.md
- docs/api-contract.md

Constraints:
- Calendar sharing is calendar-scoped only
- Budget data must stay private to the owner
- Keep to CRUD and permission basics

Done When:
- calendar and event schema/migrations are complete
- list/create/update/delete handlers exist for core calendar flow
- permission checks exist for owner and member access
- backend tests cover CRUD and access boundaries

Out of Scope:
- invite acceptance UI
- advanced recurrence

Test Notes:
- Run Go tests for calendar handlers and store logic

Follow-up Issues:
- [Integration] align auth and calendar payload mocks
EOF
)"

create_issue "[Integration] align auth and calendar payload mocks" "$(cat <<'EOF'
Goal:
Align auth and calendar payloads, mock data, and sync assumptions across backend and iOS.

Primary Agent:
integration-agent

Secondary Agents:
backend-agent, ios-agent

Inputs:
- docs/api-contract.md
- docs/sync-model.md
- docs/ios-architecture.md

Constraints:
- Keep payloads minimal for MVP
- Prefer one-call bootstrap where already specified

Done When:
- auth mock payloads are documented
- calendar mock payloads are documented
- sync assumptions and contract gaps are updated in docs

Out of Scope:
- full offline support
- design changes

Test Notes:
- Validate example payloads against current API contract

Follow-up Issues:
- [iOS] connect auth screens and session bootstrap
EOF
)"

create_issue "[iOS] connect auth screens and session bootstrap" "$(cat <<'EOF'
Goal:
Implement the SwiftUI login/register flow and app session bootstrap.

Primary Agent:
ios-agent

Secondary Agents:
integration-agent

Inputs:
- docs/ios-architecture.md
- docs/api-contract.md
- apps/ios/DayFlow

Constraints:
- Keep the UX fast and simple
- Use the current SwiftUI app skeleton
- Do not add extra tabs or non-MVP flows

Done When:
- login screen is connected to the auth API layer
- register flow matches invite-based assumptions
- successful auth bootstraps user session and root app state
- UI state covers loading and error cases

Out of Scope:
- calendar month UI
- budget board API integration

Test Notes:
- Verify state transitions in app store/view models

Follow-up Issues:
- [iOS] connect calendar list and month view
EOF
)"
