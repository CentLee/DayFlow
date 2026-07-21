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

sync_pr_group() {
  local pr_state="$1"
  local prs_json issue_key issue_id current_state target_state branch

  prs_json=$(GH_CONFIG_DIR="$GH_CONFIG_DIR" gh pr list --state "$pr_state" --limit 100 --json number,state,isDraft,headRefName,baseRefName)

  while IFS= read -r pr_row; do
    branch=$(jq -r '.headRefName' <<<"$pr_row")
    if [[ "$(jq -r '.baseRefName' <<<"$pr_row")" != "develop" ]]; then
      continue
    fi
    if ! issue_key=$(extract_issue_key "$branch"); then
      continue
    fi

    issue_id=$(find_issue_id "$issue_key")
    current_state=$(find_issue_state_name "$issue_key")

    if [[ -z "$issue_id" || "$issue_id" == "null" ]]; then
      continue
    fi

    case "$pr_state" in
      open)
        if [[ "$(jq -r '.isDraft' <<<"$pr_row")" == "true" ]]; then
          target_state="$DAYFLOW_STATE_IN_PROGRESS_ID"
          [[ "$current_state" == "$DAYFLOW_STATE_IN_PROGRESS_NAME" ]] && continue
        else
          target_state="$DAYFLOW_STATE_IN_REVIEW_ID"
          [[ "$current_state" == "$DAYFLOW_STATE_IN_REVIEW_NAME" ]] && continue
        fi
        ;;
      merged)
        target_state="$DAYFLOW_STATE_DONE_ID"
        [[ "$current_state" == "$DAYFLOW_STATE_DONE_NAME" ]] && continue
        ;;
      *)
        continue
        ;;
    esac

    linear_mutation_state "$issue_id" "$target_state"
    case "$target_state" in
      "$DAYFLOW_STATE_IN_REVIEW_ID")
        notify_issue_state_change "$issue_key" "$DAYFLOW_STATE_IN_REVIEW_NAME" "PR is ready for review on develop."
        ;;
      "$DAYFLOW_STATE_DONE_ID")
        notify_issue_state_change "$issue_key" "$DAYFLOW_STATE_DONE_NAME" "PR was merged into develop."
        ;;
    esac
    echo "synced ${issue_key} from ${current_state} via PR ${pr_state}"
  done < <(jq -c '.[]' <<<"$prs_json")
}

sync_pr_group open
sync_pr_group merged
