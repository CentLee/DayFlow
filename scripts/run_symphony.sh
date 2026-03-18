#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="/Users/kakao_ent/Documents/DayFlow"
SYMPHONY_DIR="$ROOT_DIR/vendor/symphony/elixir"
IMPLEMENTATION_WORKFLOW_FILE="$ROOT_DIR/WORKFLOW.md"
SYNC_SCRIPT="$ROOT_DIR/scripts/sync_linear_pr_states.sh"
OWNERSHIP_SCRIPT="$ROOT_DIR/scripts/reconcile_issue_ownership.sh"
REVIEW_FEEDBACK_SCRIPT="$ROOT_DIR/scripts/reconcile_review_feedback.sh"
PROOF_UPDATE_SCRIPT="$ROOT_DIR/scripts/update_pr_proof.sh"
SESSION_GUARD_SCRIPT="$ROOT_DIR/scripts/guard_issue_sessions.sh"
SYNC_INTERVAL_SECONDS="${SYNC_INTERVAL_SECONDS:-20}"

if [[ -z "${LINEAR_API_KEY:-}" ]]; then
  echo "LINEAR_API_KEY is required" >&2
  exit 1
fi

export GH_CONFIG_DIR="${GH_CONFIG_DIR:-$ROOT_DIR/.symphony/gh}"

preflight_cleanup() {
  pkill -f "$ROOT_DIR/WORKFLOW.review.md" >/dev/null 2>&1 || true
}

sync_loop() {
  while true; do
    local guard_output

    "$OWNERSHIP_SCRIPT" || true
    "$SYNC_SCRIPT" || true
    "$REVIEW_FEEDBACK_SCRIPT" || true
    "$PROOF_UPDATE_SCRIPT" || true
    guard_output=$("$SESSION_GUARD_SCRIPT" || true)
    if [[ -n "$guard_output" ]]; then
      printf '%s\n' "$guard_output"
      if [[ -n "${IMPLEMENTATION_SYMPHONY_PID:-}" ]]; then
        kill "$IMPLEMENTATION_SYMPHONY_PID" >/dev/null 2>&1 || true
      fi
      break
    fi
    sleep "$SYNC_INTERVAL_SECONDS"
  done
}

cleanup() {
  if [[ -n "${SYNC_LOOP_PID:-}" ]]; then
    kill "$SYNC_LOOP_PID" >/dev/null 2>&1 || true
  fi
  if [[ -n "${IMPLEMENTATION_SYMPHONY_PID:-}" ]]; then
    kill "$IMPLEMENTATION_SYMPHONY_PID" >/dev/null 2>&1 || true
  fi
}

trap cleanup EXIT INT TERM

preflight_cleanup
"$OWNERSHIP_SCRIPT" || true
"$SYNC_SCRIPT" || true
"$SESSION_GUARD_SCRIPT" || true
sync_loop &
SYNC_LOOP_PID=$!

cd "$SYMPHONY_DIR"
/opt/homebrew/bin/mise exec -- ./bin/symphony "$IMPLEMENTATION_WORKFLOW_FILE" --i-understand-that-this-will-be-running-without-the-usual-guardrails &
IMPLEMENTATION_SYMPHONY_PID=$!
wait "$IMPLEMENTATION_SYMPHONY_PID"
