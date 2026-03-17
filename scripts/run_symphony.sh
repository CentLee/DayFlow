#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="/Users/kakao_ent/Documents/DayFlow"
SYMPHONY_DIR="$ROOT_DIR/vendor/symphony/elixir"
IMPLEMENTATION_WORKFLOW_FILE="$ROOT_DIR/WORKFLOW.md"
REVIEW_WORKFLOW_FILE="$ROOT_DIR/WORKFLOW.review.md"
SYNC_SCRIPT="$ROOT_DIR/scripts/sync_linear_pr_states.sh"
SYNC_INTERVAL_SECONDS="${SYNC_INTERVAL_SECONDS:-20}"

if [[ -z "${LINEAR_API_KEY:-}" ]]; then
  echo "LINEAR_API_KEY is required" >&2
  exit 1
fi

export GH_CONFIG_DIR="${GH_CONFIG_DIR:-$ROOT_DIR/.symphony/gh}"

sync_loop() {
  while true; do
    "$SYNC_SCRIPT" || true
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
  if [[ -n "${REVIEW_SYMPHONY_PID:-}" ]]; then
    kill "$REVIEW_SYMPHONY_PID" >/dev/null 2>&1 || true
  fi
}

trap cleanup EXIT INT TERM

"$SYNC_SCRIPT"
sync_loop &
SYNC_LOOP_PID=$!

cd "$SYMPHONY_DIR"
/opt/homebrew/bin/mise exec -- ./bin/symphony "$IMPLEMENTATION_WORKFLOW_FILE" --i-understand-that-this-will-be-running-without-the-usual-guardrails &
IMPLEMENTATION_SYMPHONY_PID=$!

/opt/homebrew/bin/mise exec -- ./bin/symphony "$REVIEW_WORKFLOW_FILE" --i-understand-that-this-will-be-running-without-the-usual-guardrails &
REVIEW_SYMPHONY_PID=$!

wait "$IMPLEMENTATION_SYMPHONY_PID" "$REVIEW_SYMPHONY_PID"
