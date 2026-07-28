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

dayflow_notification_marker() {
  local issue_key="$1"
  local pr_number="$2"
  local state="$3"
  printf '<!-- dayflow-merge-reconcile:v2 issue=%s pr=%s state=%s -->' \
    "$issue_key" "$pr_number" "$state"
}

dayflow_declared_base_branch() {
  local description="$1"
  local values count value
  values="$(printf '%s\n' "$description" | sed -nE 's/^[[:space:]]*[-*]?[[:space:]]*Integration Base:[[:space:]]*(.*[^[:space:]])[[:space:]]*$/\1/p')"
  count="$(printf '%s\n' "$description" | sed -nE '/^[[:space:]]*[-*]?[[:space:]]*Integration Base([[:space:]]*:|[[:space:]]*$)/p' | wc -l | tr -d ' ')"
  if [[ "$count" == "0" ]]; then
    printf 'develop\n'
    return 0
  fi
  [[ "$count" == "1" && "$(printf '%s\n' "$values" | wc -l | tr -d ' ')" == "1" ]] || return 1
  value="$values"
  [[ "$value" == "integration/private-two-person-cutover" ]] || return 1
  printf '%s\n' "$value"
}

dayflow_github_notification_state() {
  local repository="$1"
  local pr_number="$2"
  local issue_key="$3"
  local legacy_marker claimed_marker retryable_marker superseded_marker delivered_marker
  local page=1 response count page_state
  local state='{"legacy_delivered":false,"entries":[]}'
  legacy_marker="<!-- dayflow-merge-reconcile:v1 issue=${issue_key} pr=${pr_number} discord=delivered -->"
  claimed_marker="$(dayflow_notification_marker "$issue_key" "$pr_number" claimed)"
  retryable_marker="$(dayflow_notification_marker "$issue_key" "$pr_number" retryable)"
  superseded_marker="$(dayflow_notification_marker "$issue_key" "$pr_number" superseded)"
  delivered_marker="$(dayflow_notification_marker "$issue_key" "$pr_number" delivered)"

  while true; do
    response="$(dayflow_github_request GET "/repos/${repository}/issues/${pr_number}/comments?per_page=100&page=${page}")" || return 1
    jq -e 'type == "array"' >/dev/null <<<"$response" || {
      dayflow_error 'GitHub returned a malformed PR comment list'
      return 1
    }
    page_state="$(jq -c \
      --arg legacy "$legacy_marker" \
      --arg claimed "$claimed_marker" \
      --arg retryable "$retryable_marker" \
      --arg superseded "$superseded_marker" \
      --arg delivered "$delivered_marker" '
        def bot_comment:
          type == "object" and .user.login == "github-actions[bot]" and
          ((.body // "") | type) == "string";
        {
          legacy_delivered: any(.[]; bot_comment and (.body | contains($legacy))),
          entries: [
            .[] |
            select(bot_comment and (.id | type) == "number" and .id > 0 and (.id | floor) == .id) |
            if (.body | contains($claimed)) then {id, state: "claimed"}
            elif (.body | contains($retryable)) then {id, state: "retryable"}
            elif (.body | contains($superseded)) then {id, state: "superseded"}
            elif (.body | contains($delivered)) then {id, state: "delivered"}
            else empty
            end
          ]
        }
      ' <<<"$response")" || {
      dayflow_error 'GitHub returned malformed PR comment data'
      return 1
    }
    state="$(jq -cn --argjson current "$state" --argjson page "$page_state" '
      {
        legacy_delivered: ($current.legacy_delivered or $page.legacy_delivered),
        entries: ($current.entries + $page.entries)
      }
    ')"
    count="$(jq 'length' <<<"$response")"
    if (( count != 100 )); then
      printf '%s\n' "$state"
      return 0
    fi
    page=$((page + 1))
  done
}

dayflow_github_set_notification_state() {
  local repository="$1"
  local comment_id="$2"
  local issue_key="$3"
  local pr_number="$4"
  local state="$5"
  local detail="$6"
  local marker body payload response
  marker="$(dayflow_notification_marker "$issue_key" "$pr_number" "$state")"
  body="$(printf '%s\n\n%s' "$marker" "$detail")"
  payload="$(jq -cn --arg body "$body" '{body: $body}')"
  response="$(dayflow_github_request PATCH "/repos/${repository}/issues/comments/${comment_id}" "$payload")" || return 1
  jq -e --argjson id "$comment_id" --arg marker "$marker" '
    .id == $id and ((.body // "") | type) == "string" and (.body | contains($marker))
  ' >/dev/null <<<"$response"
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

action="$(jq -r 'if (.action | type) == "string" then .action else "" end' "$event_path")"
merged="$(jq -r '
  if ((.pull_request | type) == "object" and (.pull_request.merged | type) == "boolean")
  then .pull_request.merged
  else false
  end
' "$event_path")"
[[ "$action" == "closed" && "$merged" == "true" ]] || dayflow_noop 'event is not a merged pull request'

base_branch="$(jq -r 'try (.pull_request.base.ref) catch "" | if type == "string" then . else "" end' "$event_path")"
head_branch="$(jq -r 'try (.pull_request.head.ref) catch "" | if type == "string" then . else "" end' "$event_path")"
repository="$(jq -r 'try (.repository.full_name) catch "" | if type == "string" then . else "" end' "$event_path")"
head_repository="$(jq -r 'try (.pull_request.head.repo.full_name) catch "" | if type == "string" then . else "" end' "$event_path")"
pr_number="$(jq -r '
  try (.pull_request.number) catch null |
  if type == "number" and . > 0 and floor == . then tostring else "" end
' "$event_path")"

case "$base_branch" in
  develop|integration/private-two-person-cutover) ;;
  *) dayflow_noop 'merged pull request does not target an allowed DayFlow base branch' ;;
esac
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

notification_state="$(dayflow_github_notification_state "$repository" "$pr_number" "$issue_key")" || {
  dayflow_error "unable to verify completion notification state for ${issue_key}"
  exit 1
}
if jq -e '.legacy_delivered or any(.entries[]; .state == "delivered")' >/dev/null <<<"$notification_state"; then
  dayflow_log "completion notification already recorded for ${issue_key}"
  exit 0
fi
if jq -e 'any(.entries[]; .state == "claimed")' >/dev/null <<<"$notification_state"; then
  dayflow_error "completion notification for ${issue_key} has an unresolved claim; operator reconciliation is required"
  exit 1
fi

claim_marker="$(dayflow_notification_marker "$issue_key" "$pr_number" claimed)"
claim_body="$(printf '%s\n\nDayFlow completion delivery is claimed. An unresolved claim must be reconciled before retrying Discord.' "$claim_marker")"
claim_payload="$(jq -cn --arg body "$claim_body" '{body: $body}')"
claim_response="$(dayflow_github_request POST "/repos/${repository}/issues/${pr_number}/comments" "$claim_payload")" || {
  dayflow_error "unable to create the ${issue_key} completion delivery claim; Linear and Discord were not mutated"
  exit 1
}
claim_id="$(jq -er 'select((.id | type) == "number" and .id > 0 and (.id | floor) == .id) | .id' <<<"$claim_response")" || {
  dayflow_error "GitHub did not confirm the ${issue_key} completion delivery claim; operator reconciliation is required"
  exit 1
}

notification_state="$(dayflow_github_notification_state "$repository" "$pr_number" "$issue_key")" || {
  dayflow_error "unable to verify the ${issue_key} completion delivery claim; operator reconciliation is required"
  exit 1
}
if jq -e '.legacy_delivered or any(.entries[]; .state == "delivered")' >/dev/null <<<"$notification_state"; then
  dayflow_log "completion notification already recorded for ${issue_key}"
  exit 0
fi
if ! jq -e --argjson id "$claim_id" 'any(.entries[]; .id == $id and .state == "claimed")' \
  >/dev/null <<<"$notification_state"; then
  dayflow_error "the ${issue_key} completion delivery claim could not be verified; operator reconciliation is required"
  exit 1
fi
winning_claim_id="$(jq -r '[.entries[] | select(.state == "claimed") | .id] | min // empty' <<<"$notification_state")"
if [[ "$winning_claim_id" != "$claim_id" ]]; then
  if ! dayflow_github_set_notification_state "$repository" "$claim_id" "$issue_key" "$pr_number" superseded \
    'Another durable claim won delivery ownership; this claim must not send Discord.'; then
    dayflow_error "unable to supersede the losing ${issue_key} claim; operator reconciliation is required"
    exit 1
  fi
  dayflow_log "another completion delivery claim owns ${issue_key}; Discord was not called"
  exit 0
fi

dayflow_fail_before_discord() {
  local message="$1"
  local detail="$2"
  if ! dayflow_github_set_notification_state "$repository" "$claim_id" "$issue_key" "$pr_number" retryable "$detail"; then
    dayflow_error "${message}; claim ${claim_id} could not be released and requires operator reconciliation"
    exit 1
  fi
  dayflow_error "${message}; claim ${claim_id} was released for rerun"
  exit 1
}

issue_query='query MergeReconcileIssue($issueId: String!) { issue(id: $issueId) { id identifier description state { name } team { states { nodes { id name } } } } }'
issue_variables="$(jq -cn --arg issue_id "$issue_key" '{issueId: $issue_id}')"
issue_response="$(dayflow_linear_request "$issue_query" "$issue_variables")" || {
  dayflow_fail_before_discord "unable to read ${issue_key} from Linear" \
    'Linear could not be read before Discord delivery; this claim is safe to retry.'
}
if ! linear_fields="$(jq -er --arg issue_key "$issue_key" --arg done_name "$DAYFLOW_LINEAR_DONE_STATE" '
  .data.issue as $issue |
  select(($issue | type) == "object") |
  select(($issue.id | type) == "string" and ($issue.id | length) > 0) |
  select(($issue.identifier | type) == "string" and $issue.identifier == $issue_key) |
  select(($issue.state.name | type) == "string" and ($issue.state.name | length) > 0) |
  select(($issue.team.states.nodes | type) == "array") |
  [$issue.team.states.nodes[] |
    select(type == "object" and (.name | type) == "string" and .name == $done_name and
      (.id | type) == "string" and (.id | length) > 0) |
    .id
  ] as $done_state_ids |
  select(($done_state_ids | length) > 0) |
  [$issue.id, $issue.identifier, $issue.state.name, $done_state_ids[0]] |
  select(all(.[]; test("[\\t\\r\\n]") | not)) |
  @tsv
' <<<"$issue_response")"; then
  dayflow_fail_before_discord "Linear issue or ${DAYFLOW_LINEAR_DONE_STATE} state did not match ${issue_key}" \
    'Linear validation failed before Discord delivery; this claim is safe to retry.'
fi
IFS=$'\t' read -r linear_issue_id linear_identifier linear_state done_state_id <<<"$linear_fields"
linear_description="$(jq -er '.data.issue.description // "" | select(type == "string")' <<<"$issue_response")" || {
  dayflow_fail_before_discord "Linear issue description did not match ${issue_key}" \
    'Linear validation failed before Discord delivery; this claim is safe to retry.'
}
declared_base="$(dayflow_declared_base_branch "$linear_description")" || {
  dayflow_fail_before_discord "Linear Integration Base metadata is invalid for ${issue_key}" \
    'Linear validation failed before Discord delivery; this claim is safe to retry.'
}
[[ "$declared_base" == "$base_branch" ]] || {
  dayflow_fail_before_discord "Linear Integration Base does not match the merged PR for ${issue_key}" \
    'Linear validation failed before Discord delivery; this claim is safe to retry.'
}

if [[ "$linear_state" != "$DAYFLOW_LINEAR_DONE_STATE" ]]; then
  mutation='mutation UpdateIssueState($issueId: String!, $stateId: String!) { issueUpdate(id: $issueId, input: { stateId: $stateId }) { success issue { id state { name } } } }'
  mutation_variables="$(jq -cn --arg issue_id "$linear_issue_id" --arg state_id "$done_state_id" \
    '{issueId: $issue_id, stateId: $state_id}')"
  mutation_response="$(dayflow_linear_request "$mutation" "$mutation_variables")" || {
    dayflow_fail_before_discord "Linear rejected the ${issue_key} Done transition" \
      'Linear did not accept the Done transition before Discord delivery; this claim is safe to retry.'
  }
  jq -e --arg name "$DAYFLOW_LINEAR_DONE_STATE" \
    '.data.issueUpdate.success == true and .data.issueUpdate.issue.state.name == $name' \
    >/dev/null <<<"$mutation_response" || {
      dayflow_fail_before_discord "Linear did not confirm the ${issue_key} Done transition" \
        'Linear did not confirm Done before Discord delivery; this claim is safe to retry.'
    }
  dayflow_log "moved ${issue_key} to ${DAYFLOW_LINEAR_DONE_STATE}"
else
  dayflow_log "${issue_key} is already ${DAYFLOW_LINEAR_DONE_STATE}"
fi

notification_body="$(printf 'PR #%s merged into %s.\n%s' "$pr_number" "$base_branch" "$pr_url")"
discord_payload="$(jq -cn --arg title "DayFlow ${issue_key} -> Done" --arg description "$notification_body" \
  '{embeds: [{title: $title, description: $description, color: 5763719}], allowed_mentions: {parse: []}}')"
if discord_http_status="$("$DAYFLOW_CURL_BIN" -sS --output /dev/null --write-out '%{http_code}' \
  -X POST "$DAYFLOW_DISCORD_WEBHOOK_URL" \
  -H 'Content-Type: application/json' --data "$discord_payload")"; then
  discord_transport_status=0
else
  discord_transport_status=$?
fi

if (( discord_transport_status != 0 )); then
  dayflow_error "Discord transport outcome is ambiguous for ${issue_key}; claim ${claim_id} requires operator reconciliation"
  exit 1
fi
if [[ "$discord_http_status" =~ ^[1-5][0-9][0-9]$ && ! "$discord_http_status" =~ ^2[0-9][0-9]$ ]]; then
  if ! dayflow_github_set_notification_state "$repository" "$claim_id" "$issue_key" "$pr_number" retryable \
    "Discord definitively rejected delivery with HTTP ${discord_http_status}; a later run may create a new claim."; then
    dayflow_error "Discord rejected ${issue_key}, but the claim could not be made retryable; operator reconciliation is required"
    exit 1
  fi
  dayflow_error "Discord rejected ${issue_key} with HTTP ${discord_http_status}; rerun this workflow to retry"
  exit 1
fi
if [[ ! "$discord_http_status" =~ ^2[0-9][0-9]$ ]]; then
  dayflow_error "Discord returned ambiguous HTTP status ${discord_http_status:-unknown} for ${issue_key}; claim ${claim_id} requires operator reconciliation"
  exit 1
fi

if ! dayflow_github_set_notification_state "$repository" "$claim_id" "$issue_key" "$pr_number" delivered \
  "DayFlow merge lifecycle reconciled: ${issue_key} is Done and Discord accepted the completion delivery."; then
  dayflow_error "Discord accepted ${issue_key}, but claim ${claim_id} could not be marked delivered; do not retry automatically"
  exit 1
fi

dayflow_log "recorded completion delivery for ${issue_key} on PR #${pr_number} claim ${claim_id}"
