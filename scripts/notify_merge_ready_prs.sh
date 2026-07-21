#!/usr/bin/env bash
set -euo pipefail

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib/dayflow_harness.sh"
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib/dayflow_notifications.sh"

require_cmds jq gh

repo_slug="$(github_repo_slug)"
ensure_merge_ready_notifications_store

all_checks_green() {
  local pr_detail="$1"

  jq -e '
    (.statusCheckRollup // []) as $checks
    | if ($checks | length) == 0 then false
      else all(
        $checks[];
        if .__typename == "CheckRun" then
          .status == "COMPLETED" and .conclusion == "SUCCESS"
        elif .__typename == "StatusContext" then
          .state == "SUCCESS"
        else
          false
        end
      )
      end
  ' <<<"$pr_detail" >/dev/null
}

is_merge_ready() {
  local pr_detail="$1"
  local review_decision

  [[ "$(jq -r '.isDraft' <<<"$pr_detail")" == "false" ]] || return 1
  [[ "$(jq -r '.mergeStateStatus' <<<"$pr_detail")" == "CLEAN" ]] || return 1

  review_decision="$(jq -r '.reviewDecision // ""' <<<"$pr_detail")"
  [[ "$review_decision" != "CHANGES_REQUESTED" ]] || return 1

  all_checks_green "$pr_detail"
}

already_notified_for_head() {
  local pr_number="$1"
  local head_sha="$2"

  jq -e --arg pr_number "$pr_number" --arg head_sha "$head_sha" '.[$pr_number].head_sha == $head_sha' \
    "$DAYFLOW_MERGE_READY_NOTIFICATIONS_FILE" >/dev/null 2>&1
}

record_merge_ready_notification() {
  local pr_number="$1"
  local issue_key="$2"
  local branch="$3"
  local head_sha="$4"

  jq \
    --arg pr_number "$pr_number" \
    --arg issue_key "$issue_key" \
    --arg branch "$branch" \
    --arg head_sha "$head_sha" \
    --arg notified_at "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
    '.[$pr_number] = {
      issue_key: $issue_key,
      branch: $branch,
      head_sha: $head_sha,
      notified_at: $notified_at
    }' \
    "$DAYFLOW_MERGE_READY_NOTIFICATIONS_FILE" >"${DAYFLOW_MERGE_READY_NOTIFICATIONS_FILE}.tmp"
  mv "${DAYFLOW_MERGE_READY_NOTIFICATIONS_FILE}.tmp" "$DAYFLOW_MERGE_READY_NOTIFICATIONS_FILE"
}

clear_stale_notification() {
  local pr_number="$1"

  jq --arg pr_number "$pr_number" 'del(.[$pr_number])' \
    "$DAYFLOW_MERGE_READY_NOTIFICATIONS_FILE" >"${DAYFLOW_MERGE_READY_NOTIFICATIONS_FILE}.tmp"
  mv "${DAYFLOW_MERGE_READY_NOTIFICATIONS_FILE}.tmp" "$DAYFLOW_MERGE_READY_NOTIFICATIONS_FILE"
}

pr_list_json="$(GH_CONFIG_DIR="$GH_CONFIG_DIR" gh pr list -R "$repo_slug" --state open --limit 100 --json number,headRefName)"

while IFS= read -r pr_row; do
  local_branch="$(jq -r '.headRefName' <<<"$pr_row")"
  pr_number="$(jq -r '.number' <<<"$pr_row")"

  if ! issue_key="$(extract_issue_key "$local_branch")"; then
    continue
  fi

  pr_detail="$(
    GH_CONFIG_DIR="$GH_CONFIG_DIR" gh pr view -R "$repo_slug" "$pr_number" \
      --json number,title,isDraft,reviewDecision,mergeStateStatus,statusCheckRollup,headRefOid,headRefName,baseRefName,url
  )"

  if ! is_merge_ready "$pr_detail"; then
    clear_stale_notification "$pr_number"
    continue
  fi

  head_sha="$(jq -r '.headRefOid' <<<"$pr_detail")"
  if already_notified_for_head "$pr_number" "$head_sha"; then
    continue
  fi

  base_branch="$(jq -r '.baseRefName' <<<"$pr_detail")"
  pr_url="$(jq -r '.url' <<<"$pr_detail")"
  notify_merge_ready \
    "$issue_key" \
    "$pr_number" \
    "$pr_url" \
    "Branch: \`${local_branch}\`\nBase: \`${base_branch}\`\nHead: \`${head_sha:0:12}\`"
  record_merge_ready_notification "$pr_number" "$issue_key" "$local_branch" "$head_sha"
  echo "sent merge-ready notification for ${issue_key} PR #${pr_number}"
done < <(jq -c '.[]' <<<"$pr_list_json")
