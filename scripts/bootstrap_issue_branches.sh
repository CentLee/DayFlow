#!/usr/bin/env bash
set -euo pipefail

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib/dayflow_harness.sh"

require_linear_api_key
require_cmds jq

issue_table_json=$(
  project_issues_json
)

find_issue_title() {
  local identifier="$1"
  find_issue_field "$issue_table_json" "$identifier" '.title'
}

find_issue_state_name() {
  local identifier="$1"
  find_issue_field "$issue_table_json" "$identifier" '.state.name'
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
  [[ "$current_state" == "$DAYFLOW_STATE_TODO_NAME" ]] || continue

  branch=$(git -C "$workspace_dir" branch --show-current 2>/dev/null || true)
  [[ "$branch" == "develop" ]] || continue

  dirty=$(git -C "$workspace_dir" status --porcelain 2>/dev/null || true)
  [[ -z "$dirty" ]] || continue

  title=$(find_issue_title "$issue_key")
  [[ -n "$title" && "$title" != "null" ]] || continue

  slug=$(slugify_title "$title")
  [[ -n "$slug" ]] || continue

  branch_key="$(branch_issue_slug "$issue_key")"
  target_branch="feature/tasks-${branch_key}-${slug}"
  git -C "$workspace_dir" switch -c "$target_branch" >/dev/null 2>&1 || true
  touch "$workspace_dir"
  echo "bootstrapped ${issue_key} branch ${target_branch}"
done
