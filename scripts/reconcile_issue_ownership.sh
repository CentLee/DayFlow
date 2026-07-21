#!/usr/bin/env bash
set -euo pipefail

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib/dayflow_harness.sh"
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib/dayflow_notifications.sh"

require_linear_api_key
require_cmds jq gh

issue_table_json=$(
  project_issues_json
)

find_issue_id() {
  local identifier="$1"
  find_issue_field "$issue_table_json" "$identifier" '.id'
}

find_issue_state_name() {
  local identifier="$1"
  find_issue_field "$issue_table_json" "$identifier" '.state.name'
}

workspace_is_owned() {
  local workspace_dir="$1"
  local issue_key="$2"
  local branch head develop_head status

  branch=$(git -C "$workspace_dir" branch --show-current 2>/dev/null || true)
  status=$(git -C "$workspace_dir" status --porcelain 2>/dev/null || true)
  head=$(git -C "$workspace_dir" rev-parse HEAD 2>/dev/null || true)
  develop_head=$(git -C "$workspace_dir" rev-parse origin/develop 2>/dev/null || true)

  [[ -n "$status" ]] && return 0
  [[ -n "$head" && -n "$develop_head" && "$head" != "$develop_head" ]] && return 0
  return 1
}

for workspace_dir in "$WORKSPACE_ROOT"/CEN-*; do
  [[ -d "$workspace_dir/.git" ]] || continue

  issue_key=$(basename "$workspace_dir")
  [[ "$issue_key" == *.stale.* ]] && continue
  issue_id=$(find_issue_id "$issue_key")
  current_state=$(find_issue_state_name "$issue_key")
  branch=$(git -C "$workspace_dir" branch --show-current 2>/dev/null || true)

  if [[ -z "$issue_id" || "$issue_id" == "null" ]]; then
    continue
  fi

  if ! workspace_is_owned "$workspace_dir" "$issue_key"; then
    continue
  fi

  if [[ "$current_state" == "$DAYFLOW_STATE_TODO_NAME" ]]; then
    linear_mutation_state "$issue_id" "$DAYFLOW_STATE_IN_PROGRESS_ID"
    notify_issue_state_change "$issue_key" "$DAYFLOW_STATE_IN_PROGRESS_NAME" "Workspace ownership became active."
    echo "promoted ${issue_key} to In Progress from active workspace ownership"
    continue
  fi

  if [[ "$current_state" == "$DAYFLOW_STATE_IN_REVIEW_NAME" ]] && [[ -n "$branch" ]] && ! has_open_pr_for_branch "$branch"; then
    linear_mutation_state "$issue_id" "$DAYFLOW_STATE_TODO_ID"
    echo "returned ${issue_key} to Todo because review state had no open PR"
  fi
done
