#!/usr/bin/env bash
set -euo pipefail

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib/dayflow_harness.sh"

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

has_fresh_requested_changes() {
  local pr_detail="$1"

  jq -e '
    . as $root
    | (($root.commits | last | .committedDate) // "") as $latest_commit_at
    | $root.reviews
    | map(select(.submittedAt != null and .author.login != null and .state != "COMMENTED"))
    | sort_by(.submittedAt)
    | group_by(.author.login)
    | map(last)
    | map(select(.submittedAt >= $latest_commit_at))
    | any(.state == "CHANGES_REQUESTED")
  ' <<<"$pr_detail" >/dev/null
}

repo_slug="$(github_repo_slug)"
pr_list_json=$(GH_CONFIG_DIR="$GH_CONFIG_DIR" gh pr list -R "$repo_slug" --state open --limit 100 --json number,isDraft,headRefName,baseRefName)

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

  pr_number=$(jq -r '.number' <<<"$pr_row")
  pr_detail=$(GH_CONFIG_DIR="$GH_CONFIG_DIR" gh pr view -R "$repo_slug" "$pr_number" --json reviews,commits,isDraft)

  if ! has_fresh_requested_changes "$pr_detail"; then
    continue
  fi

  if [[ "$(jq -r '.isDraft' <<<"$pr_detail")" != "true" ]]; then
    GH_CONFIG_DIR="$GH_CONFIG_DIR" gh pr ready -R "$repo_slug" --undo "$pr_number" >/dev/null
  fi

  if [[ "$current_state" != "$DAYFLOW_STATE_TODO_NAME" ]]; then
    linear_mutation_state "$issue_id" "$DAYFLOW_STATE_TODO_ID"
  fi

  echo "returned ${issue_key} to Todo from requested changes review state"
done < <(jq -c '.[]' <<<"$pr_list_json")
