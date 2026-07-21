#!/usr/bin/env bash
set -euo pipefail

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib/dayflow_harness.sh"

MAX_SESSION_MINUTES="${MAX_SESSION_MINUTES:-15}"
MAX_UNTRACKED_MINUTES="${MAX_UNTRACKED_MINUTES:-8}"
MAX_BRANCH_ONLY_STALL_MINUTES="${MAX_BRANCH_ONLY_STALL_MINUTES:-3}"
MAX_TOKEN_TOTAL="${MAX_TOKEN_TOTAL:-120000}"

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

session_metadata_json() {
  local issue_key="$1"
  local log_file

  log_file=$(find /tmp -maxdepth 1 -type f -name "codex-cli-${issue_key}-*.jsonl" -print | sort | tail -n 1)
  if [[ -z "$log_file" ]]; then
    return 1
  fi

  jq -s '
    map(select(.msg?))
    | {
        token_total: (map(.msg.usage.total_tokens // empty) | last // 0),
        updated_at: (map(.msg.timestamp // empty) | last // "")
      }
  ' "$log_file"
}

should_reset_issue() {
  local workspace_dir="$1"
  local issue_key="$2"
  local dirty_minutes token_total branch head develop_head

  dirty_minutes=$(minutes_since_change "$workspace_dir")
  branch=$(git -C "$workspace_dir" branch --show-current 2>/dev/null || true)
  head=$(git -C "$workspace_dir" rev-parse HEAD 2>/dev/null || true)
  develop_head=$(git -C "$workspace_dir" rev-parse origin/develop 2>/dev/null || true)

  token_total=0
  if metadata=$(session_metadata_json "$issue_key" 2>/dev/null); then
    token_total=$(jq -r '.token_total // 0' <<<"$metadata")
  fi

  if (( token_total >= MAX_TOKEN_TOTAL )); then
    echo "token ceiling exceeded (${token_total})"
    return 0
  fi

  if (( dirty_minutes >= MAX_BRANCH_ONLY_STALL_MINUTES )) && [[ "$branch" =~ ^codex/${issue_key}- ]] && [[ -z "$(git -C "$workspace_dir" status --porcelain 2>/dev/null)" ]] && [[ "$head" == "$develop_head" ]] && ! has_open_pr_for_branch "$branch"; then
    stale_dir="${workspace_dir}.stale.$(date +%s)"
    mv "$workspace_dir" "$stale_dir"
    echo "branch-only stall recovered via $(basename "$stale_dir")"
    return 0
  fi

  if (( dirty_minutes >= MAX_SESSION_MINUTES )) && [[ -z "$(git -C "$workspace_dir" status --porcelain 2>/dev/null)" ]] && [[ "$head" == "$develop_head" ]]; then
    echo "session exceeded ${MAX_SESSION_MINUTES}m without changes"
    return 0
  fi

  if (( dirty_minutes >= MAX_UNTRACKED_MINUTES )) && [[ "$branch" =~ ^codex/${issue_key}- ]] && [[ -n "$(git -C "$workspace_dir" status --porcelain 2>/dev/null)" ]] && ! git -C "$workspace_dir" diff --quiet -- apps/ios/DayFlow.xcodeproj 2>/dev/null; then
    echo "workspace stalled with generated file churn"
    return 0
  fi

  if (( dirty_minutes >= MAX_UNTRACKED_MINUTES )) && [[ "$branch" =~ ^codex/${issue_key}- ]] && [[ -n "$(git -C "$workspace_dir" status --porcelain 2>/dev/null)" ]] && ! has_open_pr_for_branch "$branch"; then
    echo "workspace stalled with uncommitted changes and no PR"
    return 0
  fi

  return 1
}

for workspace_dir in "$WORKSPACE_ROOT"/CEN-*; do
  [[ -d "$workspace_dir/.git" ]] || continue

  issue_key=$(basename "$workspace_dir")
  [[ "$issue_key" == *.stale.* ]] && continue
  issue_id=$(find_issue_id "$issue_key")
  current_state=$(find_issue_state_name "$issue_key")

  if [[ -z "$issue_id" || "$issue_id" == "null" ]]; then
    continue
  fi

  if reason=$(should_reset_issue "$workspace_dir" "$issue_key"); then
    echo "guard flagged ${issue_key}: ${reason}"
  fi
done
