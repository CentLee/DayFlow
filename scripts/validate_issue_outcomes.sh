#!/usr/bin/env bash
set -euo pipefail

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib/dayflow_harness.sh"

VALIDATION_STALE_MINUTES="${VALIDATION_STALE_MINUTES:-5}"

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

for workspace_dir in "$WORKSPACE_ROOT"/CEN-*; do
  [[ -d "$workspace_dir/.git" ]] || continue

  issue_key=$(basename "$workspace_dir")
  [[ "$issue_key" == *.stale.* ]] && continue
  issue_id=$(find_issue_id "$issue_key")
  current_state=$(find_issue_state_name "$issue_key")
  branch=$(git -C "$workspace_dir" branch --show-current 2>/dev/null || true)
  dirty=$(git -C "$workspace_dir" status --porcelain 2>/dev/null || true)
  age_minutes=$(minutes_since_change "$workspace_dir")

  [[ -n "$issue_id" && "$issue_id" != "null" ]] || continue
  [[ "$current_state" == "$DAYFLOW_STATE_IN_PROGRESS_NAME" ]] || continue
  [[ -n "$branch" ]] || continue
  issue_branch_matches "$branch" "$issue_key" || continue
  has_open_pr_for_branch "$branch" && continue

  if [[ -n "$dirty" ]]; then
    if (( age_minutes >= VALIDATION_STALE_MINUTES )); then
      echo "validator paused ${issue_key}: uncommitted changes still exist after completion window"
    fi
    continue
  fi

  ahead_count=$(git -C "$workspace_dir" rev-list --count origin/develop..HEAD 2>/dev/null || echo 0)

  if (( age_minutes < VALIDATION_STALE_MINUTES )); then
    continue
  fi

  if (( ahead_count == 0 )); then
    linear_mutation_state "$issue_id" "$DAYFLOW_STATE_TODO_ID"
    echo "validator reset ${issue_key} to Todo: no PR and no changes after completion window"
    continue
  fi

  echo "validator paused ${issue_key}: branch has commits but no PR after completion window"
done
