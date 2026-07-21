#!/usr/bin/env bash

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/dayflow_harness.sh"

DAYFLOW_NOTIFICATIONS_ENV_FILE="${DAYFLOW_NOTIFICATIONS_ENV_FILE:-$ROOT_DIR/.symphony/notifications.env}"

load_dayflow_notifications_env() {
  if [[ -f "$DAYFLOW_NOTIFICATIONS_ENV_FILE" ]]; then
    # shellcheck disable=SC1090
    source "$DAYFLOW_NOTIFICATIONS_ENV_FILE"
  fi
}

discord_webhook_enabled() {
  load_dayflow_notifications_env
  [[ -n "${DAYFLOW_DISCORD_WEBHOOK_URL:-}" ]]
}

send_discord_notification() {
  local title="$1"
  local body="$2"
  local color="${3:-3447003}"
  local webhook_url payload

  if ! discord_webhook_enabled; then
    return 0
  fi

  webhook_url="$DAYFLOW_DISCORD_WEBHOOK_URL"
  payload=$(jq -n \
    --arg title "$title" \
    --arg description "$body" \
    --argjson color "$color" \
    '{
      embeds: [
        {
          title: $title,
          description: $description,
          color: $color
        }
      ]
    }')

  curl -sS -X POST "$webhook_url" \
    -H "Content-Type: application/json" \
    --data "$payload" >/dev/null || true
}

notify_issue_state_change() {
  local issue_key="$1"
  local state_name="$2"
  local detail="${3:-}"
  local color

  case "$state_name" in
    "$DAYFLOW_STATE_IN_PROGRESS_NAME") color=16753920 ;;
    "$DAYFLOW_STATE_IN_REVIEW_NAME") color=5814783 ;;
    "$DAYFLOW_STATE_DONE_NAME") color=5763719 ;;
    "$DAYFLOW_STATE_BLOCKED_NAME") color=15158332 ;;
    *) color=3447003 ;;
  esac

  send_discord_notification \
    "DayFlow ${issue_key} -> ${state_name}" \
    "${detail}" \
    "$color"
}

notify_harness_runtime() {
  local phase="$1"
  local detail="$2"
  local color=3447003

  if [[ "$phase" == "stopped" ]]; then
    color=15105570
  fi

  send_discord_notification \
    "DayFlow harness ${phase}" \
    "$detail" \
    "$color"
}

notify_merge_ready() {
  local issue_key="$1"
  local pr_number="$2"
  local pr_url="$3"
  local detail="${4:-}"

  send_discord_notification \
    "DayFlow ${issue_key} merge-ready" \
    "PR #${pr_number} is merge-ready.\n${detail}\n${pr_url}" \
    5763719
}
