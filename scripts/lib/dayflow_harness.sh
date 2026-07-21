#!/usr/bin/env bash

ROOT_DIR="${DAYFLOW_ROOT_DIR:-/Users/kakao_ent/Documents/DayFlow}"
WORKSPACE_ROOT="${DAYFLOW_WORKSPACE_ROOT:-$ROOT_DIR/.symphony/workspaces}"
GH_CONFIG_DIR="${GH_CONFIG_DIR:-$ROOT_DIR/.symphony/gh}"
export PATH="/usr/local/bin:/opt/homebrew/bin:/usr/bin:/bin:/usr/sbin:/sbin:${PATH:-}"

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
DAYFLOW_PAUSED_ISSUES_FILE="${DAYFLOW_PAUSED_ISSUES_FILE:-$ROOT_DIR/.symphony/artifacts/paused_issues.json}"

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
  local configured_id=""

  case "$state_name" in
    "$DAYFLOW_STATE_TODO_NAME") configured_id="$DAYFLOW_STATE_TODO_ID" ;;
    "$DAYFLOW_STATE_IN_PROGRESS_NAME") configured_id="$DAYFLOW_STATE_IN_PROGRESS_ID" ;;
    "$DAYFLOW_STATE_IN_REVIEW_NAME") configured_id="$DAYFLOW_STATE_IN_REVIEW_ID" ;;
    "$DAYFLOW_STATE_DONE_NAME") configured_id="$DAYFLOW_STATE_DONE_ID" ;;
    "$DAYFLOW_STATE_BLOCKED_NAME") configured_id="$DAYFLOW_STATE_BLOCKED_ID" ;;
    *) return 1 ;;
  esac

  if [[ -n "$configured_id" ]]; then
    printf '%s\n' "$configured_id"
    return 0
  fi

  linear_query "query { project(id: \"${DAYFLOW_LINEAR_PROJECT_ID}\") { states { nodes { id name } } } }" |
    jq -r --arg state_name "$state_name" '.data.project.states.nodes[]? | select(.name == $state_name) | .id' |
    head -n 1
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
  if [[ "$branch" =~ ^feature/tasks-([0-9]+)- ]]; then
    printf 'CEN-%s\n' "${BASH_REMATCH[1]}"
    return 0
  fi
  if [[ "$branch" =~ ^codex/(CEN-[0-9]+)- ]]; then
    printf '%s\n' "${BASH_REMATCH[1]}"
    return 0
  fi
  if [[ "$branch" =~ ^codex/([0-9]+)- ]]; then
    printf 'CEN-%s\n' "${BASH_REMATCH[1]}"
    return 0
  fi
  return 1
}

branch_issue_slug() {
  local issue_key="$1"
  if [[ "$issue_key" =~ ^CEN-([0-9]+)$ ]]; then
    printf '%s\n' "${BASH_REMATCH[1]}"
    return 0
  fi
  printf '%s\n' "$issue_key"
}

issue_branch_matches() {
  local branch="$1"
  local issue_key="$2"
  local branch_key

  branch_key="$(branch_issue_slug "$issue_key")"
  [[ "$branch" =~ ^feature/tasks-${branch_key}- ]] ||
    [[ "$branch" =~ ^codex/${issue_key}- ]] ||
    [[ "$branch" =~ ^codex/${branch_key}- ]]
}

has_open_pr_for_branch() {
  local branch="$1"
  GH_CONFIG_DIR="$GH_CONFIG_DIR" gh pr list --state open --limit 100 --json headRefName |
    jq -e --arg branch "$branch" '.[] | select(.headRefName == $branch)' >/dev/null
}

minutes_since_change() {
  local path="$1"
  local now modified latest
  local candidate
  local candidates=("$path")

  now=$(date +%s)
  latest=$(stat -f %m "$path" 2>/dev/null || echo 0)

  if [[ -d "$path/.git" ]]; then
    candidates+=("$path/.git" "$path/.git/HEAD" "$path/.git/index" "$path/.git/logs/HEAD")

    while IFS= read -r candidate; do
      [[ -n "$candidate" ]] || continue
      candidates+=("$candidate")
    done < <(find "$path/.git/refs/heads" -type f 2>/dev/null)
  fi

  for candidate in "${candidates[@]}"; do
    modified=$(stat -f %m "$candidate" 2>/dev/null || echo 0)
    if (( modified > latest )); then
      latest="$modified"
    fi
  done

  if (( latest <= 0 )); then
    latest="$now"
  fi

  echo $(((now - latest) / 60))
}

runtime_elapsed_seconds() {
  local pid="${IMPLEMENTATION_SYMPHONY_PID:-}"

  if [[ -z "$pid" ]] || ! kill -0 "$pid" >/dev/null 2>&1; then
    echo 0
    return 0
  fi

  ps -o etimes= -p "$pid" 2>/dev/null | tr -d ' ' || echo 0
}

ensure_paused_issues_store() {
  mkdir -p "$(dirname "$DAYFLOW_PAUSED_ISSUES_FILE")"
  if [[ ! -f "$DAYFLOW_PAUSED_ISSUES_FILE" ]]; then
    printf '{}\n' >"$DAYFLOW_PAUSED_ISSUES_FILE"
  fi
}

pause_issue_locally() {
  local issue_key="$1"
  local reason="${2:-}"

  ensure_paused_issues_store
  jq \
    --arg issue_key "$issue_key" \
    --arg reason "$reason" \
    --arg paused_at "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
    '.[$issue_key] = {reason: $reason, paused_at: $paused_at}' \
    "$DAYFLOW_PAUSED_ISSUES_FILE" >"${DAYFLOW_PAUSED_ISSUES_FILE}.tmp"
  mv "${DAYFLOW_PAUSED_ISSUES_FILE}.tmp" "$DAYFLOW_PAUSED_ISSUES_FILE"
}

resume_issue_locally() {
  local issue_key="$1"

  [[ -f "$DAYFLOW_PAUSED_ISSUES_FILE" ]] || return 0
  jq --arg issue_key "$issue_key" 'del(.[$issue_key])' "$DAYFLOW_PAUSED_ISSUES_FILE" >"${DAYFLOW_PAUSED_ISSUES_FILE}.tmp"
  mv "${DAYFLOW_PAUSED_ISSUES_FILE}.tmp" "$DAYFLOW_PAUSED_ISSUES_FILE"
}

issue_paused_locally() {
  local issue_key="$1"

  [[ -f "$DAYFLOW_PAUSED_ISSUES_FILE" ]] || return 1
  jq -e --arg issue_key "$issue_key" 'has($issue_key)' "$DAYFLOW_PAUSED_ISSUES_FILE" >/dev/null 2>&1
}

paused_issue_reason() {
  local issue_key="$1"

  [[ -f "$DAYFLOW_PAUSED_ISSUES_FILE" ]] || return 1
  jq -r --arg issue_key "$issue_key" '.[$issue_key].reason // ""' "$DAYFLOW_PAUSED_ISSUES_FILE"
}
