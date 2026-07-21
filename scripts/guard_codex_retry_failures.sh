#!/usr/bin/env bash
set -euo pipefail

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib/dayflow_harness.sh"

STATE_API_URL="${DAYFLOW_STATE_API_URL:-http://127.0.0.1:4100/api/v1/state}"
GUARD_STATE_FILE="${DAYFLOW_RETRY_GUARD_STATE_FILE:-$ROOT_DIR/.symphony/artifacts/codex_retry_guard_state.json}"
MAX_CONSECUTIVE_AGENT_EXIT_RETRIES="${MAX_CONSECUTIVE_AGENT_EXIT_RETRIES:-2}"
MAX_RUNNING_TOTAL_TOKENS="${MAX_RUNNING_TOTAL_TOKENS:-120000}"

require_linear_api_key
require_cmds curl jq

mkdir -p "$(dirname "$GUARD_STATE_FILE")"

issue_table_json="$(
  project_issues_json
)"

reset_guard_state() {
  rm -f "$GUARD_STATE_FILE"
}

block_issue_if_possible() {
  local issue_key="$1"
  local reason="$2"
  local issue_id

  issue_id="$(
    jq -r --arg issue_key "$issue_key" '.[] | select(.identifier == $issue_key) | .id' <<<"$issue_table_json" |
      head -n 1
  )"

  pause_issue_locally "$issue_key" "$reason"

  if [[ -n "$issue_id" && "$issue_id" != "null" ]] && move_issue_to_named_state "$issue_id" "$DAYFLOW_STATE_BLOCKED_NAME"; then
    echo "guard blocked ${issue_key}: ${reason}"
    return 0
  fi

  if [[ -n "$issue_id" && "$issue_id" != "null" ]] && move_issue_to_named_state "$issue_id" "$DAYFLOW_STATE_IN_PROGRESS_NAME"; then
    echo "guard paused ${issue_key}: ${reason} (moved to In Progress to stop rerun)"
    return 0
  fi

  echo "guard paused ${issue_key}: ${reason}"
}

reconcile_paused_runnable_issues() {
  local paused_rows paused_row issue_key reason current_state

  ensure_paused_issues_store
  paused_rows="$(jq -c 'to_entries[]?' "$DAYFLOW_PAUSED_ISSUES_FILE" 2>/dev/null || true)"
  [[ -n "$paused_rows" ]] || return 1

  while IFS= read -r paused_row; do
    [[ -n "$paused_row" ]] || continue

    issue_key="$(jq -r '.key' <<<"$paused_row")"
    reason="$(jq -r '.value.reason // "paused locally"' <<<"$paused_row")"
    current_state="$(
      jq -r --arg issue_key "$issue_key" '.[] | select(.identifier == $issue_key) | .state.name' <<<"$issue_table_json" |
        head -n 1
    )"

    if [[ "$current_state" == "$DAYFLOW_STATE_TODO_NAME" ]]; then
      block_issue_if_possible "$issue_key" "$reason"
      return 0
    fi
  done <<<"$paused_rows"

  return 1
}

if reconcile_paused_runnable_issues; then
  reset_guard_state
  exit 0
fi

state_json="$(curl -fsS "$STATE_API_URL" 2>/dev/null || true)"
if [[ -z "$state_json" ]]; then
  reset_guard_state
  exit 0
fi

running_count="$(jq -r '.counts.running // 0' <<<"$state_json")"
retry_count="$(jq -r '.counts.retrying // 0' <<<"$state_json")"

if (( running_count > 0 )); then
  first_running="$(jq -c '.running[0] // empty' <<<"$state_json")"
  if [[ -n "$first_running" ]]; then
    running_issue="$(jq -r '.issue_identifier // ""' <<<"$first_running")"
    running_tokens="$(jq -r '.tokens.total_tokens // 0' <<<"$first_running")"

    if [[ -n "$running_issue" ]] && issue_paused_locally "$running_issue"; then
      reset_guard_state
      echo "guard stopping ${running_issue}: $(paused_issue_reason "$running_issue")"
      exit 0
    fi

    if [[ -n "$running_issue" ]] && (( running_tokens >= MAX_RUNNING_TOTAL_TOKENS )); then
      reset_guard_state
      block_issue_if_possible "$running_issue" "token ceiling exceeded at ${running_tokens} total tokens"
      exit 0
    fi
  fi

  reset_guard_state
  exit 0
fi

if (( retry_count == 0 )); then
  reset_guard_state
  exit 0
fi

first_retry="$(jq -c '.retrying[0] // empty' <<<"$state_json")"
if [[ -z "$first_retry" ]]; then
  reset_guard_state
  exit 0
fi

issue_key="$(jq -r '.issue_identifier // ""' <<<"$first_retry")"
attempt="$(jq -r '.attempt // 0' <<<"$first_retry")"
error_text="$(jq -r '.error // ""' <<<"$first_retry")"

if [[ "$error_text" != agent\ exited:* ]]; then
  reset_guard_state
  exit 0
fi

previous_issue=""
previous_error=""
previous_count=0
if [[ -f "$GUARD_STATE_FILE" ]]; then
  previous_issue="$(jq -r '.issue_identifier // ""' "$GUARD_STATE_FILE" 2>/dev/null || true)"
  previous_error="$(jq -r '.error // ""' "$GUARD_STATE_FILE" 2>/dev/null || true)"
  previous_count="$(jq -r '.consecutive_count // 0' "$GUARD_STATE_FILE" 2>/dev/null || true)"
fi

consecutive_count=1
if [[ "$issue_key" == "$previous_issue" && "$error_text" == "$previous_error" ]]; then
  consecutive_count=$((previous_count + 1))
fi

jq -n \
  --arg issue_identifier "$issue_key" \
  --arg error "$error_text" \
  --argjson consecutive_count "$consecutive_count" \
  --argjson attempt "$attempt" \
  '{
    issue_identifier: $issue_identifier,
    error: $error,
    consecutive_count: $consecutive_count,
    attempt: $attempt
  }' >"$GUARD_STATE_FILE"

if (( consecutive_count >= MAX_CONSECUTIVE_AGENT_EXIT_RETRIES )) && (( attempt >= MAX_CONSECUTIVE_AGENT_EXIT_RETRIES )); then
  reset_guard_state
  block_issue_if_possible "$issue_key" "repeated codex agent exits after ${attempt} retry attempts"
fi
