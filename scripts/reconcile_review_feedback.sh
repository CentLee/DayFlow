#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="/Users/kakao_ent/Documents/DayFlow"
PROJECT_ID="fdeb5f63-05f2-4ab2-bb9d-a12dc0084b9f"
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

extract_issue_key() {
  local branch="$1"
  if [[ "$branch" =~ ^codex/(CEN-[0-9]+)- ]]; then
    printf '%s\n' "${BASH_REMATCH[1]}"
    return 0
  fi
  return 1
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

review_requests_changes() {
  local body="$1"
  grep -Eqi 'Request changes|Do not merge yet|Not merged; changes requested' <<<"$body"
}

pr_list_json=$(GH_CONFIG_DIR="${GH_CONFIG_DIR:-$ROOT_DIR/.symphony/gh}" gh pr list --state open --limit 100 --json number,isDraft,headRefName,baseRefName)

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
  pr_detail=$(GH_CONFIG_DIR="${GH_CONFIG_DIR:-$ROOT_DIR/.symphony/gh}" gh pr view "$pr_number" --json comments,commits,isDraft)
  latest_commit_at=$(jq -r '.commits | last | .committedDate // ""' <<<"$pr_detail")
  latest_findings=$(jq -c '
    .comments
    | map(select((.body | test("Findings"; "i")) and (.body | test("Merge Decision"; "i"))))
    | sort_by(.createdAt)
    | last // empty
  ' <<<"$pr_detail")

  if [[ -z "$latest_findings" ]]; then
    continue
  fi

  findings_created_at=$(jq -r '.createdAt // ""' <<<"$latest_findings")
  findings_body=$(jq -r '.body // ""' <<<"$latest_findings")

  if [[ -n "$latest_commit_at" && "$findings_created_at" < "$latest_commit_at" ]]; then
    continue
  fi

  if ! review_requests_changes "$findings_body"; then
    continue
  fi

  if [[ "$(jq -r '.isDraft' <<<"$pr_detail")" != "true" ]]; then
    GH_CONFIG_DIR="${GH_CONFIG_DIR:-$ROOT_DIR/.symphony/gh}" gh pr ready --undo "$pr_number" >/dev/null
  fi

  if [[ "$current_state" != "Todo" ]]; then
    linear_mutation "$issue_id" "$STATE_TODO_ID"
  fi

  echo "returned ${issue_key} to Todo from review findings"
done < <(jq -c '.[]' <<<"$pr_list_json")
