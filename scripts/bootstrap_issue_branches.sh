#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="/Users/kakao_ent/Documents/DayFlow"
WORKSPACE_ROOT="$ROOT_DIR/.symphony/workspaces"
PROJECT_ID="fdeb5f63-05f2-4ab2-bb9d-a12dc0084b9f"

if [[ -z "${LINEAR_API_KEY:-}" ]]; then
  echo "LINEAR_API_KEY is required" >&2
  exit 1
fi

if ! command -v jq >/dev/null 2>&1; then
  echo "jq is required" >&2
  exit 1
fi

linear_query() {
  local query="$1"
  curl -s https://api.linear.app/graphql \
    -H "Content-Type: application/json" \
    -H "Authorization: ${LINEAR_API_KEY}" \
    --data "$(jq -n --arg query "$query" '{query: $query}')"
}

issue_table_json=$(
  linear_query "query { project(id: \"${PROJECT_ID}\") { issues(first: 100) { nodes { identifier title state { name } } } } }" |
    jq -c '.data.project.issues.nodes'
)

find_issue_title() {
  local identifier="$1"
  jq -r --arg identifier "$identifier" '.[] | select(.identifier == $identifier) | .title' <<<"$issue_table_json"
}

find_issue_state_name() {
  local identifier="$1"
  jq -r --arg identifier "$identifier" '.[] | select(.identifier == $identifier) | .state.name' <<<"$issue_table_json"
}

slugify_title() {
  local raw="$1"
  printf '%s' "$raw" |
    tr '[:upper:]' '[:lower:]' |
    sed -E 's/^\[[^]]+\][[:space:]]*//; s/[^a-z0-9]+/-/g; s/^-+//; s/-+$//; s/-{2,}/-/g'
}

for workspace_dir in "$WORKSPACE_ROOT"/CEN-*; do
  [[ -d "$workspace_dir/.git" ]] || continue

  issue_key=$(basename "$workspace_dir")
  [[ "$issue_key" == *.stale.* ]] && continue

  current_state=$(find_issue_state_name "$issue_key")
  [[ "$current_state" == "Todo" ]] || continue

  branch=$(git -C "$workspace_dir" branch --show-current 2>/dev/null || true)
  [[ "$branch" == "develop" ]] || continue

  dirty=$(git -C "$workspace_dir" status --porcelain 2>/dev/null || true)
  [[ -z "$dirty" ]] || continue

  title=$(find_issue_title "$issue_key")
  [[ -n "$title" && "$title" != "null" ]] || continue

  slug=$(slugify_title "$title")
  [[ -n "$slug" ]] || continue

  target_branch="codex/${issue_key}-${slug}"
  git -C "$workspace_dir" switch -c "$target_branch" >/dev/null 2>&1 || true
  echo "bootstrapped ${issue_key} branch ${target_branch}"
done
