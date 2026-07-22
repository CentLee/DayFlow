#!/usr/bin/env bash
set -euo pipefail

DAYFLOW_CURL_BIN="${DAYFLOW_CURL_BIN:-curl}"
DAYFLOW_LINEAR_API_URL="${DAYFLOW_LINEAR_API_URL:-https://api.linear.app/graphql}"
DAYFLOW_GITHUB_API_URL="${DAYFLOW_GITHUB_API_URL:-https://api.github.com}"
DAYFLOW_LINEAR_DONE_STATE="${DAYFLOW_LINEAR_DONE_STATE:-Done}"

dayflow_log() {
  printf 'dayflow-merge-reconcile: %s\n' "$*"
}

dayflow_error() {
  printf 'dayflow-merge-reconcile: %s\n' "$*" >&2
}

dayflow_noop() {
  dayflow_log "$1; no lifecycle changes made"
  exit 0
}

dayflow_require_command() {
  command -v "$1" >/dev/null 2>&1 || {
    dayflow_error "required command is unavailable: $1"
    exit 1
  }
}

dayflow_linear_request() {
  local query="$1"
  local variables="$2"
  local payload response
  payload="$(jq -cn --arg query "$query" --argjson variables "$variables" \
    '{query: $query, variables: $variables}')"
  response="$("$DAYFLOW_CURL_BIN" -fsS -X POST "$DAYFLOW_LINEAR_API_URL" \
    -H 'Content-Type: application/json' \
    -H "Authorization: ${LINEAR_API_KEY}" \
    --data "$payload")" || return 1
  if jq -e '(.errors // []) | length > 0' >/dev/null <<<"$response"; then
    jq -r '.errors[]?.message // "Linear returned an unknown GraphQL error"' <<<"$response" >&2
    return 1
  fi
  printf '%s\n' "$response"
}

dayflow_github_request() {
  local method="$1"
  local path="$2"
  local payload="${3:-}"
  local args=(-fsS -X "$method" \
    -H 'Accept: application/vnd.github+json' \
    -H "Authorization: Bearer ${GITHUB_TOKEN}" \
    -H 'X-GitHub-Api-Version: 2022-11-28')
  if [[ -n "$payload" ]]; then
    args+=(-H 'Content-Type: application/json' --data "$payload")
  fi
  "$DAYFLOW_CURL_BIN" "${args[@]}" "${DAYFLOW_GITHUB_API_URL}${path}"
}

dayflow_github_has_marker() {
  local repository="$1"
  local pr_number="$2"
  local marker="$3"
  local page=1 response count
  while true; do
    response="$(dayflow_github_request GET "/repos/${repository}/issues/${pr_number}/comments?per_page=100&page=${page}")" || return 2
    jq -e 'type == "array"' >/dev/null <<<"$response" || {
      dayflow_error 'GitHub returned a malformed PR comment list'
      return 2
    }
    if jq -e --arg marker "$marker" \
      'any(.[]; .user.login == "github-actions[bot]" and ((.body // "") | contains($marker)))' \
      >/dev/null <<<"$response"; then
      return 0
    fi
    count="$(jq 'length' <<<"$response")"
    (( count == 100 )) || return 1
    page=$((page + 1))
  done
}

dayflow_require_command jq
dayflow_require_command "$DAYFLOW_CURL_BIN"

event_path="${GITHUB_EVENT_PATH:-}"
[[ -n "$event_path" && -f "$event_path" ]] || {
  dayflow_error 'GITHUB_EVENT_PATH must point to the pull_request event payload'
  exit 1
}
jq -e 'type == "object"' "$event_path" >/dev/null 2>&1 || {
  dayflow_error 'GitHub event payload is not valid JSON'
  exit 1
}

action="$(jq -r '.action // ""' "$event_path")"
merged="$(jq -r '.pull_request.merged // false' "$event_path")"
[[ "$action" == "closed" && "$merged" == "true" ]] || dayflow_noop 'event is not a merged pull request'

base_branch="$(jq -r '.pull_request.base.ref // ""' "$event_path")"
head_branch="$(jq -r '.pull_request.head.ref // ""' "$event_path")"
repository="$(jq -r '.repository.full_name // ""' "$event_path")"
head_repository="$(jq -r '.pull_request.head.repo.full_name // ""' "$event_path")"
pr_number="$(jq -r '.pull_request.number // ""' "$event_path")"

[[ "$base_branch" == "develop" ]] || dayflow_noop 'merged pull request does not target develop'
[[ "$repository" =~ ^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$ ]] || dayflow_noop 'event repository is malformed'
[[ "$head_repository" == "$repository" ]] || dayflow_noop 'merged pull request head is not a repository-owned branch'
[[ -z "${GITHUB_REPOSITORY:-}" || "$repository" == "$GITHUB_REPOSITORY" ]] || dayflow_noop 'event repository does not match the workflow repository'
[[ "$pr_number" =~ ^[1-9][0-9]*$ ]] || dayflow_noop 'pull request number is malformed'
if [[ ! "$head_branch" =~ ^feature/tasks-([1-9][0-9]*)-[a-z0-9][a-z0-9-]*$ ]]; then
  dayflow_noop 'merged pull request branch does not match the DayFlow task contract'
fi

issue_key="CEN-${BASH_REMATCH[1]}"
pr_url="https://github.com/${repository}/pull/${pr_number}"

[[ -n "${LINEAR_API_KEY:-}" ]] || {
  dayflow_error 'LINEAR_API_KEY is required for eligible merge events'
  exit 1
}
[[ -n "${GITHUB_TOKEN:-}" ]] || {
  dayflow_error 'GITHUB_TOKEN is required for eligible merge events'
  exit 1
}
[[ -n "${DAYFLOW_DISCORD_WEBHOOK_URL:-}" ]] || {
  dayflow_error 'DAYFLOW_DISCORD_WEBHOOK_URL is required for eligible merge events'
  exit 1
}

marker="<!-- dayflow-merge-reconcile:v1 issue=${issue_key} pr=${pr_number} discord=delivered -->"
if dayflow_github_has_marker "$repository" "$pr_number" "$marker"; then
  dayflow_log "completion notification already recorded for ${issue_key}"
  exit 0
else
  marker_status=$?
  if (( marker_status != 1 )); then
    dayflow_error "unable to verify completion dedupe state for ${issue_key}"
    exit 1
  fi
fi

issue_query='query MergeReconcileIssue($issueId: String!) { issue(id: $issueId) { id identifier state { name } team { states { nodes { id name } } } } }'
issue_variables="$(jq -cn --arg issue_id "$issue_key" '{issueId: $issue_id}')"
issue_response="$(dayflow_linear_request "$issue_query" "$issue_variables")" || {
  dayflow_error "unable to read ${issue_key} from Linear"
  exit 1
}
linear_issue_id="$(jq -r '.data.issue.id // ""' <<<"$issue_response")"
linear_identifier="$(jq -r '.data.issue.identifier // ""' <<<"$issue_response")"
linear_state="$(jq -r '.data.issue.state.name // ""' <<<"$issue_response")"
done_state_id="$(jq -r --arg name "$DAYFLOW_LINEAR_DONE_STATE" \
  '.data.issue.team.states.nodes[]? | select(.name == $name) | .id' <<<"$issue_response" | head -n 1)"
[[ -n "$linear_issue_id" && "$linear_identifier" == "$issue_key" && -n "$done_state_id" ]] || {
  dayflow_error "Linear issue or ${DAYFLOW_LINEAR_DONE_STATE} state did not match ${issue_key}"
  exit 1
}

if [[ "$linear_state" != "$DAYFLOW_LINEAR_DONE_STATE" ]]; then
  mutation='mutation UpdateIssueState($issueId: String!, $stateId: String!) { issueUpdate(id: $issueId, input: { stateId: $stateId }) { success issue { id state { name } } } }'
  mutation_variables="$(jq -cn --arg issue_id "$linear_issue_id" --arg state_id "$done_state_id" \
    '{issueId: $issue_id, stateId: $state_id}')"
  mutation_response="$(dayflow_linear_request "$mutation" "$mutation_variables")" || {
    dayflow_error "Linear rejected the ${issue_key} Done transition"
    exit 1
  }
  jq -e --arg name "$DAYFLOW_LINEAR_DONE_STATE" \
    '.data.issueUpdate.success == true and .data.issueUpdate.issue.state.name == $name' \
    >/dev/null <<<"$mutation_response" || {
      dayflow_error "Linear did not confirm the ${issue_key} Done transition"
      exit 1
    }
  dayflow_log "moved ${issue_key} to ${DAYFLOW_LINEAR_DONE_STATE}"
else
  dayflow_log "${issue_key} is already ${DAYFLOW_LINEAR_DONE_STATE}"
fi

notification_body="$(printf 'PR #%s merged into develop.\n%s' "$pr_number" "$pr_url")"
discord_payload="$(jq -cn --arg title "DayFlow ${issue_key} -> Done" --arg description "$notification_body" \
  '{embeds: [{title: $title, description: $description, color: 5763719}], allowed_mentions: {parse: []}}')"
if ! "$DAYFLOW_CURL_BIN" -fsS -X POST "$DAYFLOW_DISCORD_WEBHOOK_URL" \
  -H 'Content-Type: application/json' --data "$discord_payload" >/dev/null; then
  dayflow_error "Discord completion delivery failed for ${issue_key}; rerun this workflow to retry"
  exit 1
fi

comment_body="$(printf '%s\n\nDayFlow merge lifecycle reconciled: `%s` is Done and completion delivery succeeded.' "$marker" "$issue_key")"
comment_payload="$(jq -cn --arg body "$comment_body" '{body: $body}')"
if ! dayflow_github_request POST "/repos/${repository}/issues/${pr_number}/comments" "$comment_payload" >/dev/null; then
  dayflow_error "Discord delivered, but GitHub could not persist the ${issue_key} dedupe marker"
  exit 1
fi

dayflow_log "recorded completion delivery for ${issue_key} on PR #${pr_number}"
