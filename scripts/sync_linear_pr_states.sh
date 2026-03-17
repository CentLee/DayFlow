#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="/Users/kakao_ent/Documents/DayFlow"
PROJECT_ID="fdeb5f63-05f2-4ab2-bb9d-a12dc0084b9f"
STATE_TODO_ID="452888e8-7d81-4229-bf16-d0876c3098a3"
STATE_IN_PROGRESS_ID="b88769c5-551d-4248-b834-c2e3975ef7df"
STATE_IN_REVIEW_ID="236d69db-9e92-476a-8106-7c62264d244c"
STATE_DONE_ID="43be38bf-b6b1-4d4d-a6c3-1c09978b25fd"

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
    issue {
      identifier
      state { name }
    }
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
  linear_query "query { project(id: \"${PROJECT_ID}\") { issues(first: 100) { nodes { id identifier state { id name } } } } }" |
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

sync_pr_group() {
  local pr_state="$1"
  local prs_json issue_key issue_id current_state target_state branch

  prs_json=$(GH_CONFIG_DIR="${GH_CONFIG_DIR:-$ROOT_DIR/.symphony/gh}" gh pr list --state "$pr_state" --limit 100 --json number,state,isDraft,headRefName,baseRefName)

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
          target_state="$STATE_IN_PROGRESS_ID"
          [[ "$current_state" == "In Progress" ]] && continue
        else
          target_state="$STATE_IN_REVIEW_ID"
          [[ "$current_state" == "In Review" ]] && continue
        fi
        ;;
      merged)
        target_state="$STATE_DONE_ID"
        [[ "$current_state" == "Done" ]] && continue
        ;;
      *)
        continue
        ;;
    esac

    linear_mutation "$issue_id" "$target_state"
    echo "synced ${issue_key} from ${current_state} via PR ${pr_state}"
  done < <(jq -c '.[]' <<<"$prs_json")
}

sync_pr_group open
sync_pr_group merged
