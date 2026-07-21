#!/usr/bin/env bash

ROOT_DIR="${DAYFLOW_ROOT_DIR:-/Users/kakao_ent/Documents/DayFlow}"
WORKSPACE_ROOT="${DAYFLOW_WORKSPACE_ROOT:-$ROOT_DIR/.symphony/workspaces}"
GH_CONFIG_DIR="${GH_CONFIG_DIR:-$ROOT_DIR/.symphony/gh}"

DAYFLOW_LINEAR_TEAM_ID="${DAYFLOW_LINEAR_TEAM_ID:-6f6e5287-d893-439d-981f-94d73ccd720a}"
DAYFLOW_LINEAR_PROJECT_ID="${DAYFLOW_LINEAR_PROJECT_ID:-fdeb5f63-05f2-4ab2-bb9d-a12dc0084b9f}"

DAYFLOW_STATE_TODO_NAME="${DAYFLOW_STATE_TODO_NAME:-Todo}"
DAYFLOW_STATE_IN_PROGRESS_NAME="${DAYFLOW_STATE_IN_PROGRESS_NAME:-In Progress}"
DAYFLOW_STATE_IN_REVIEW_NAME="${DAYFLOW_STATE_IN_REVIEW_NAME:-In Review}"
DAYFLOW_STATE_DONE_NAME="${DAYFLOW_STATE_DONE_NAME:-Done}"
DAYFLOW_STATE_BLOCKED_NAME="${DAYFLOW_STATE_BLOCKED_NAME:-Blocked}"

DAYFLOW_STATE_TODO_ID="${DAYFLOW_STATE_TODO_ID:-452888e8-7d81-4229-bf16-d0876c3098a3}"
DAYFLOW_STATE_IN_PROGRESS_ID="${DAYFLOW_STATE_IN_PROGRESS_ID:-b88769c5-551d-4248-b834-c2e3975ef7df}"
DAYFLOW_STATE_IN_REVIEW_ID="${DAYFLOW_STATE_IN_REVIEW_ID:-236d69db-9e92-476a-8106-7c62264d244c}"
DAYFLOW_STATE_DONE_ID="${DAYFLOW_STATE_DONE_ID:-43be38bf-b6b1-4d4d-a6c3-1c09978b25fd}"
DAYFLOW_STATE_BLOCKED_ID="${DAYFLOW_STATE_BLOCKED_ID:-}"

require_linear_api_key() {
  if [[ -z "${LINEAR_API_KEY:-}" ]]; then
    echo "LINEAR_API_KEY is required" >&2
    exit 1
  fi
}

require_cmds() {
  local cmd
  for cmd in "$@"; do
    if ! command -v "$cmd" >/dev/null 2>&1; then
      echo "${cmd} is required" >&2
      exit 1
    fi
  done
}

linear_query() {
  local query="$1"
  curl -s https://api.linear.app/graphql \
    -H "Content-Type: application/json" \
    -H "Authorization: ${LINEAR_API_KEY}" \
    --data "$(jq -n --arg query "$query" '{query: $query}')"
}

linear_mutation_state() {
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

project_issues_json() {
  linear_query "query { project(id: \"${DAYFLOW_LINEAR_PROJECT_ID}\") { issues(first: 100) { nodes { id identifier title description state { id name } } } } }" |
    jq -c '.data.project.issues.nodes'
}

find_issue_field() {
  local issue_table_json="$1"
  local identifier="$2"
  local field_expr="$3"

  jq -r --arg identifier "$identifier" ".[] | select(.identifier == \$identifier) | ${field_expr}" <<<"$issue_table_json"
}

state_id_for_name() {
  local state_name="$1"

  case "$state_name" in
    "$DAYFLOW_STATE_TODO_NAME") printf '%s\n' "$DAYFLOW_STATE_TODO_ID" ;;
    "$DAYFLOW_STATE_IN_PROGRESS_NAME") printf '%s\n' "$DAYFLOW_STATE_IN_PROGRESS_ID" ;;
    "$DAYFLOW_STATE_IN_REVIEW_NAME") printf '%s\n' "$DAYFLOW_STATE_IN_REVIEW_ID" ;;
    "$DAYFLOW_STATE_DONE_NAME") printf '%s\n' "$DAYFLOW_STATE_DONE_ID" ;;
    "$DAYFLOW_STATE_BLOCKED_NAME") printf '%s\n' "$DAYFLOW_STATE_BLOCKED_ID" ;;
    *) return 1 ;;
  esac
}

move_issue_to_named_state() {
  local issue_id="$1"
  local state_name="$2"
  local state_id

  if ! state_id=$(state_id_for_name "$state_name"); then
    return 1
  fi

  if [[ -z "$state_id" ]]; then
    return 1
  fi

  linear_mutation_state "$issue_id" "$state_id"
}

extract_issue_key() {
  local branch="$1"
  if [[ "$branch" =~ ^codex/(CEN-[0-9]+)- ]]; then
    printf '%s\n' "${BASH_REMATCH[1]}"
    return 0
  fi
  return 1
}

has_open_pr_for_branch() {
  local branch="$1"
  GH_CONFIG_DIR="$GH_CONFIG_DIR" gh pr list --state open --limit 100 --json headRefName |
    jq -e --arg branch "$branch" '.[] | select(.headRefName == $branch)' >/dev/null
}

minutes_since_change() {
  local path="$1"
  local now modified

  now=$(date +%s)
  modified=$(stat -f %m "$path" 2>/dev/null || echo "$now")
  echo $(((now - modified) / 60))
}

runtime_elapsed_seconds() {
  local pid="${IMPLEMENTATION_SYMPHONY_PID:-}"

  if [[ -z "$pid" ]] || ! kill -0 "$pid" >/dev/null 2>&1; then
    echo 0
    return 0
  fi

  ps -o etimes= -p "$pid" 2>/dev/null | tr -d ' ' || echo 0
}
