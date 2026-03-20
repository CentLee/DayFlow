#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="/Users/kakao_ent/Documents/DayFlow"
WORKSPACE_ROOT="$ROOT_DIR/.symphony/workspaces"
PROJECT_ID="fdeb5f63-05f2-4ab2-bb9d-a12dc0084b9f"
VALIDATION_STALE_MINUTES="${VALIDATION_STALE_MINUTES:-5}"
STATE_TODO_ID="452888e8-7d81-4229-bf16-d0876c3098a3"

if [[ -z "${LINEAR_API_KEY:-}" ]]; then
  echo "LINEAR_API_KEY is required" >&2
  exit 1
fi

if ! command -v jq >/dev/null 2>&1; then
  echo "jq is required" >&2
  exit 1
fi

if ! command -v gh >/dev/null 2>&1; then
  echo "gh is required" >&2
  exit 1
fi

linear_query() {
  local query="$1"
  curl -s https://api.linear.app/graphql \
    -H "Content-Type: application/json" \
    -H "Authorization: ${LINEAR_API_KEY}" \
    --data "$(jq -n --arg query "$query" '{query: $query}')"
}

linear_mutation() {
  local issue_id="$1"
  local state_id="$2"
  local query

  query=$(cat <<EOF
mutation {
  issueUpdate(id: "${issue_id}", input: {stateId: "${state_id}"}) {
    success
  }
}
EOF
)

  linear_query "$query" >/dev/null
}

issue_table_json=$(
  linear_query "query { project(id: \"${PROJECT_ID}\") { issues(first: 100) { nodes { id identifier state { name } } } } }" |
    jq -c '.data.project.issues.nodes'
)

find_issue_id() {
  local identifier="$1"
  jq -r --arg identifier "$identifier" '.[] | select(.identifier == $identifier) | .id' <<<"$issue_table_json"
}

find_issue_state_name() {
  local identifier="$1"
  jq -r --arg identifier "$identifier" '.[] | select(.identifier == $identifier) | .state.name' <<<"$issue_table_json"
}

has_open_pr() {
  local branch="$1"
  GH_CONFIG_DIR="${GH_CONFIG_DIR:-$ROOT_DIR/.symphony/gh}" \
    gh pr list --state open --limit 100 --json headRefName |
    jq -e --arg branch "$branch" '.[] | select(.headRefName == $branch)' >/dev/null
}

minutes_since_change() {
  local path="$1"
  local now modified

  now=$(date +%s)
  modified=$(stat -f %m "$path" 2>/dev/null || echo "$now")
  echo $(((now - modified) / 60))
}

for workspace_dir in "$WORKSPACE_ROOT"/CEN-*; do
  [[ -d "$workspace_dir/.git" ]] || continue

  issue_key=$(basename "$workspace_dir")
  issue_id=$(find_issue_id "$issue_key")
  current_state=$(find_issue_state_name "$issue_key")
  branch=$(git -C "$workspace_dir" branch --show-current 2>/dev/null || true)
  dirty=$(git -C "$workspace_dir" status --porcelain 2>/dev/null || true)
  age_minutes=$(minutes_since_change "$workspace_dir")

  [[ -n "$issue_id" && "$issue_id" != "null" ]] || continue
  [[ "$current_state" == "In Progress" ]] || continue
  [[ -n "$branch" ]] || continue
  [[ "$branch" =~ ^codex/${issue_key}- ]] || continue
  has_open_pr "$branch" && continue

  if [[ -n "$dirty" ]]; then
    continue
  fi

  ahead_count=$(git -C "$workspace_dir" rev-list --count origin/develop..HEAD 2>/dev/null || echo 0)

  if (( age_minutes < VALIDATION_STALE_MINUTES )); then
    continue
  fi

  if (( ahead_count == 0 )); then
    linear_mutation "$issue_id" "$STATE_TODO_ID"
    echo "validator reset ${issue_key} to Todo: no PR and no changes after completion window"
    continue
  fi

  linear_mutation "$issue_id" "$STATE_TODO_ID"
  echo "validator reset ${issue_key} to Todo: branch has commits but no PR after completion window"
done
