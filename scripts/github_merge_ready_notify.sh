#!/usr/bin/env bash
set -euo pipefail

DAYFLOW_CURL_BIN="${DAYFLOW_CURL_BIN:-curl}"
DAYFLOW_GITHUB_API_URL="${DAYFLOW_GITHUB_API_URL:-https://api.github.com}"

dayflow_log() {
  printf 'dayflow-merge-ready: %s\n' "$*"
}

dayflow_error() {
  printf 'dayflow-merge-ready: %s\n' "$*" >&2
}

dayflow_noop() {
  dayflow_log "$1; no notification sent"
  exit 0
}

dayflow_require_command() {
  command -v "$1" >/dev/null 2>&1 || {
    dayflow_error "required command is unavailable: $1"
    exit 1
  }
}

dayflow_github_request() {
  local method="$1"
  local path="$2"
  local payload="${3:-}"
  local args=(-fsS -X "$method"
    -H 'Accept: application/vnd.github+json'
    -H "Authorization: Bearer ${GITHUB_TOKEN}"
    -H 'X-GitHub-Api-Version: 2022-11-28')
  if [[ -n "$payload" ]]; then
    args+=(-H 'Content-Type: application/json' --data "$payload")
  fi
  "$DAYFLOW_CURL_BIN" "${args[@]}" "${DAYFLOW_GITHUB_API_URL}${path}"
}

dayflow_notification_marker() {
  local issue_key="$1"
  local pr_number="$2"
  local head_sha="$3"
  local state="$4"
  printf '<!-- dayflow-merge-ready:v1 issue=%s pr=%s sha=%s state=%s -->' \
    "$issue_key" "$pr_number" "$head_sha" "$state"
}

dayflow_comment_states() {
  local repository="$1"
  local pr_number="$2"
  local issue_key="$3"
  local head_sha="$4"
  local page=1 response count state page_state
  local state='[]'

  while true; do
    response="$(dayflow_github_request GET "/repos/${repository}/issues/${pr_number}/comments?per_page=100&page=${page}")" || return 1
    jq -e 'type == "array"' >/dev/null <<<"$response" || return 1
    page_state="$(jq -c \
      --arg claimed "$(dayflow_notification_marker "$issue_key" "$pr_number" "$head_sha" claimed)" \
      --arg retryable "$(dayflow_notification_marker "$issue_key" "$pr_number" "$head_sha" retryable)" \
      --arg delivered "$(dayflow_notification_marker "$issue_key" "$pr_number" "$head_sha" delivered)" '
        [ .[] |
          select((.user.login? // "") == "github-actions[bot]") |
          if ((.body // "") | contains($claimed)) then {id, state: "claimed"}
          elif ((.body // "") | contains($retryable)) then {id, state: "retryable"}
          elif ((.body // "") | contains($delivered)) then {id, state: "delivered"}
          else empty end
        ]
      ' <<<"$response")" || return 1
    state="$(jq -cn --argjson current "$state" --argjson page "$page_state" '$current + $page')"
    count="$(jq 'length' <<<"$response")"
    if (( count != 100 )); then
      printf '%s\n' "$state"
      return 0
    fi
    page=$((page + 1))
  done
}

dayflow_update_comment() {
  local repository="$1"
  local comment_id="$2"
  local issue_key="$3"
  local pr_number="$4"
  local head_sha="$5"
  local state="$6"
  local detail="$7"
  local body payload response
  body="$(printf '%s\n\n%s' "$(dayflow_notification_marker "$issue_key" "$pr_number" "$head_sha" "$state")" "$detail")"
  payload="$(jq -cn --arg body "$body" '{body: $body}')"
  response="$(dayflow_github_request PATCH "/repos/${repository}/issues/comments/${comment_id}" "$payload")" || return 1
  jq -e --argjson id "$comment_id" --arg body "$body" '.id == $id and .body == $body' >/dev/null <<<"$response"
}

dayflow_require_command jq
dayflow_require_command "$DAYFLOW_CURL_BIN"

event_path="${GITHUB_EVENT_PATH:-}"
[[ -n "$event_path" && -f "$event_path" ]] || {
  dayflow_error 'GITHUB_EVENT_PATH must point to the workflow_run event payload'
  exit 1
}

event_fields="$(jq -er '
  select(type == "object") |
  select(.action == "completed") |
  .repository.full_name as $repository |
  .workflow_run as $run |
  select(($repository | type) == "string" and ($repository | test("^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$"))) |
  select(($run | type) == "object") |
  select($run.event == "pull_request" and $run.status == "completed" and $run.conclusion == "success") |
  select(($run.head_sha | type) == "string" and ($run.head_sha | test("^[0-9a-f]{40}$"))) |
  select(($run.pull_requests | type) == "array" and ($run.pull_requests | length) == 1) |
  ($run.pull_requests[0].number) as $pr |
  select(($pr | type) == "number" and $pr > 0 and ($pr | floor) == $pr) |
  [$repository, ($pr | tostring), $run.head_sha] | @tsv
' "$event_path")" || dayflow_noop 'event is not an eligible completed pull-request CI run'
IFS=$'\t' read -r repository pr_number head_sha <<<"$event_fields"
[[ -z "${GITHUB_REPOSITORY:-}" || "$repository" == "$GITHUB_REPOSITORY" ]] || dayflow_noop 'event repository does not match this workflow repository'

[[ -n "${GITHUB_TOKEN:-}" ]] || {
  dayflow_error 'GITHUB_TOKEN is required to inspect an eligible pull request'
  exit 1
}
pr_response="$(dayflow_github_request GET "/repos/${repository}/pulls/${pr_number}")" || {
  dayflow_error "unable to read PR #${pr_number}"
  exit 1
}
branch="$(jq -er --arg repository "$repository" --arg sha "$head_sha" '
  select(.state == "open" and .draft == false) |
  select(.base.ref == "develop") |
  select(.head.sha == $sha and .head.repo.full_name == $repository) |
  select((.head.ref | type) == "string") |
  .head.ref
' <<<"$pr_response")" || dayflow_noop 'pull request is not an open repository-owned develop task PR at this head'
if [[ ! "$branch" =~ ^feature/tasks-([1-9][0-9]*)-[a-z0-9][a-z0-9-]*$ ]]; then
  dayflow_noop 'pull request branch does not match the DayFlow task contract'
fi
issue_key="CEN-${BASH_REMATCH[1]}"

runs_response="$(dayflow_github_request GET "/repos/${repository}/actions/runs?event=pull_request&head_sha=${head_sha}&per_page=100")" || {
  dayflow_error "unable to inspect CI runs for PR #${pr_number}"
  exit 1
}
ci_ready="$(jq -er --arg sha "$head_sha" '
  select((.workflow_runs | type) == "array") |
  [ .workflow_runs[] |
    select(.head_sha == $sha and .event == "pull_request" and (.name == "API CI" or .name == "Harness CI")) |
    {name, status, conclusion, run_attempt: (.run_attempt // 0), created_at: (.created_at // "")}
  ] |
  group_by(.name) |
  map(sort_by(.run_attempt, .created_at) | last) as $latest |
  select(($latest | length) > 0) |
  if all($latest[]; .status == "completed" and .conclusion == "success") then "ready" else "waiting" end
' <<<"$runs_response")" || {
  dayflow_error "GitHub returned malformed CI run data for PR #${pr_number}"
  exit 1
}
[[ "$ci_ready" == 'ready' ]] || dayflow_noop 'at least one applicable CI workflow is incomplete or unsuccessful'

[[ -n "${DAYFLOW_DISCORD_WEBHOOK_URL:-}" ]] || {
  dayflow_error 'DAYFLOW_DISCORD_WEBHOOK_URL is required for an eligible merge-ready notification'
  exit 1
}
comment_states="$(dayflow_comment_states "$repository" "$pr_number" "$issue_key" "$head_sha")" || {
  dayflow_error "unable to inspect merge-ready delivery state for ${issue_key}"
  exit 1
}
if jq -e 'any(.[]; .state == "delivered")' >/dev/null <<<"$comment_states"; then
  dayflow_noop "merge-ready notification already recorded for ${issue_key}"
fi
if jq -e 'any(.[]; .state == "claimed")' >/dev/null <<<"$comment_states"; then
  dayflow_error "merge-ready notification for ${issue_key} has an unresolved claim; operator reconciliation is required"
  exit 1
fi

claim_body="$(printf '%s\n\nDayFlow merge-ready delivery is claimed. Do not rerun after an ambiguous transport failure.' \
  "$(dayflow_notification_marker "$issue_key" "$pr_number" "$head_sha" claimed)")"
claim_payload="$(jq -cn --arg body "$claim_body" '{body: $body}')"
claim_response="$(dayflow_github_request POST "/repos/${repository}/issues/${pr_number}/comments" "$claim_payload")" || {
  dayflow_error "unable to claim merge-ready notification for ${issue_key}"
  exit 1
}
claim_id="$(jq -er '.id | select(type == "number" and . > 0 and floor == .)' <<<"$claim_response")" || {
  dayflow_error "GitHub did not confirm the merge-ready claim for ${issue_key}"
  exit 1
}

pr_url="https://github.com/${repository}/pull/${pr_number}"
discord_payload="$(jq -cn --arg title "DayFlow ${issue_key} merge-ready" --arg description "PR #${pr_number} passed CI and is ready to merge.\n${pr_url}" \
  '{embeds: [{title: $title, description: $description, color: 5763719}], allowed_mentions: {parse: []}}')"
if discord_http_status="$("$DAYFLOW_CURL_BIN" -sS --output /dev/null --write-out '%{http_code}' \
  -X POST "$DAYFLOW_DISCORD_WEBHOOK_URL" -H 'Content-Type: application/json' --data "$discord_payload")"; then
  discord_transport_status=0
else
  discord_transport_status=$?
fi
if (( discord_transport_status != 0 )); then
  dayflow_error "Discord transport outcome is ambiguous for ${issue_key}; claim ${claim_id} requires operator reconciliation"
  exit 1
fi
if [[ ! "$discord_http_status" =~ ^2[0-9][0-9]$ ]]; then
  if ! dayflow_update_comment "$repository" "$claim_id" "$issue_key" "$pr_number" "$head_sha" retryable \
    "Discord rejected merge-ready delivery with HTTP ${discord_http_status}; a later CI completion may retry."; then
    dayflow_error "Discord rejected ${issue_key}, but the claim could not be released"
    exit 1
  fi
  dayflow_error "Discord rejected merge-ready delivery for ${issue_key} with HTTP ${discord_http_status}"
  exit 1
fi
if ! dayflow_update_comment "$repository" "$claim_id" "$issue_key" "$pr_number" "$head_sha" delivered \
  "DayFlow merge-ready notification delivered after CI passed."; then
  dayflow_error "Discord accepted ${issue_key}, but the claim could not be marked delivered; do not retry automatically"
  exit 1
fi

dayflow_log "recorded merge-ready notification for ${issue_key} on PR #${pr_number}"
