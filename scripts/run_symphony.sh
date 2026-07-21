#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="/Users/kakao_ent/Documents/DayFlow"
source "$ROOT_DIR/scripts/lib/dayflow_notifications.sh"

SYMPHONY_DIR="$ROOT_DIR/vendor/symphony/elixir"
IMPLEMENTATION_WORKFLOW_FILE="$ROOT_DIR/WORKFLOW.md"
ADMISSION_VALIDATOR_SCRIPT="$ROOT_DIR/scripts/validate_issue_admission.sh"
SYNC_SCRIPT="$ROOT_DIR/scripts/sync_linear_pr_states.sh"
OWNERSHIP_SCRIPT="$ROOT_DIR/scripts/reconcile_issue_ownership.sh"
REVIEW_FEEDBACK_SCRIPT="$ROOT_DIR/scripts/reconcile_review_feedback.sh"
PROOF_UPDATE_SCRIPT="$ROOT_DIR/scripts/update_pr_proof.sh"
MERGE_READY_NOTIFICATION_SCRIPT="$ROOT_DIR/scripts/notify_merge_ready_prs.sh"
BRANCH_BOOTSTRAP_SCRIPT="$ROOT_DIR/scripts/bootstrap_issue_branches.sh"
SESSION_GUARD_SCRIPT="$ROOT_DIR/scripts/guard_issue_sessions.sh"
OUTCOME_VALIDATOR_SCRIPT="$ROOT_DIR/scripts/validate_issue_outcomes.sh"
EMPTY_SPIN_GUARD_SCRIPT="$ROOT_DIR/scripts/guard_empty_workspace_spins.sh"
BRANCH_BOOTSTRAP_GUARD_SCRIPT="$ROOT_DIR/scripts/guard_branch_bootstrap_stalls.sh"
CODEX_RETRY_GUARD_SCRIPT="$ROOT_DIR/scripts/guard_codex_retry_failures.sh"
SYNC_INTERVAL_SECONDS="${SYNC_INTERVAL_SECONDS:-20}"
HARNESS_STOP_NOTIFIED=0
HARNESS_LOCK_DIR="${DAYFLOW_HARNESS_LOCK_DIR:-$ROOT_DIR/.symphony/run_symphony.lock}"

if [[ -z "${LINEAR_API_KEY:-}" ]]; then
  echo "LINEAR_API_KEY is required" >&2
  exit 1
fi

export GH_CONFIG_DIR="${GH_CONFIG_DIR:-$ROOT_DIR/.symphony/gh}"

preflight_cleanup() {
  pkill -f "$ROOT_DIR/WORKFLOW.review.md" >/dev/null 2>&1 || true
}

terminate_process_tree() {
  local pid="$1"
  local child_pid

  [[ -n "$pid" ]] || return 0
  kill -0 "$pid" >/dev/null 2>&1 || return 0

  while IFS= read -r child_pid; do
    [[ -n "$child_pid" ]] || continue
    terminate_process_tree "$child_pid"
  done < <(pgrep -P "$pid" 2>/dev/null || true)

  kill "$pid" >/dev/null 2>&1 || true
  sleep 1
  kill -0 "$pid" >/dev/null 2>&1 || return 0
  kill -9 "$pid" >/dev/null 2>&1 || true
}

stop_implementation_runtime() {
  if [[ -n "${IMPLEMENTATION_SYMPHONY_PID:-}" ]]; then
    terminate_process_tree "$IMPLEMENTATION_SYMPHONY_PID"
    IMPLEMENTATION_SYMPHONY_PID=""
    export IMPLEMENTATION_SYMPHONY_PID
  fi
}

acquire_lock() {
  local current_pid existing_pid

  current_pid="$$"
  if mkdir "$HARNESS_LOCK_DIR" >/dev/null 2>&1; then
    printf '%s\n' "$current_pid" >"$HARNESS_LOCK_DIR/pid"
    return 0
  fi

  existing_pid="$(cat "$HARNESS_LOCK_DIR/pid" 2>/dev/null || true)"
  if [[ -n "$existing_pid" ]] && kill -0 "$existing_pid" >/dev/null 2>&1; then
    echo "run_symphony.sh is already running with pid ${existing_pid}" >&2
    exit 1
  fi

  rm -rf "$HARNESS_LOCK_DIR"
  mkdir "$HARNESS_LOCK_DIR"
  printf '%s\n' "$current_pid" >"$HARNESS_LOCK_DIR/pid"
}

run_local_script() {
  local script_path="$1"
  shift || true
  bash "$script_path" "$@" || true
}

prelaunch_checks() {
  local guard_output outcome_output

  run_local_script "$ADMISSION_VALIDATOR_SCRIPT"
  run_local_script "$OWNERSHIP_SCRIPT"
  run_local_script "$SYNC_SCRIPT"
  run_local_script "$REVIEW_FEEDBACK_SCRIPT"
  run_local_script "$BRANCH_BOOTSTRAP_SCRIPT"
  run_local_script "$PROOF_UPDATE_SCRIPT"
  run_local_script "$MERGE_READY_NOTIFICATION_SCRIPT"

  outcome_output="$(bash "$OUTCOME_VALIDATOR_SCRIPT" 2>/dev/null || true)"
  if [[ -n "$outcome_output" ]]; then
    printf '%s\n' "$outcome_output"
    return 1
  fi

  guard_output="$(bash "$SESSION_GUARD_SCRIPT" 2>/dev/null || true)"
  if [[ -n "$guard_output" ]]; then
    printf '%s\n' "$guard_output"
    return 1
  fi

  guard_output="$(bash "$EMPTY_SPIN_GUARD_SCRIPT" 2>/dev/null || true)"
  if [[ -n "$guard_output" ]]; then
    printf '%s\n' "$guard_output"
    return 1
  fi

  guard_output="$(bash "$BRANCH_BOOTSTRAP_GUARD_SCRIPT" 2>/dev/null || true)"
  if [[ -n "$guard_output" ]]; then
    printf '%s\n' "$guard_output"
    return 1
  fi

  guard_output="$(bash "$CODEX_RETRY_GUARD_SCRIPT" 2>/dev/null || true)"
  if [[ -n "$guard_output" ]]; then
    printf '%s\n' "$guard_output"
    return 1
  fi

  return 0
}

sync_loop() {
  while true; do
    local guard_output outcome_output

    run_local_script "$ADMISSION_VALIDATOR_SCRIPT"
    run_local_script "$OWNERSHIP_SCRIPT"
    run_local_script "$SYNC_SCRIPT"
    run_local_script "$REVIEW_FEEDBACK_SCRIPT"
    run_local_script "$BRANCH_BOOTSTRAP_SCRIPT"
    run_local_script "$PROOF_UPDATE_SCRIPT"
    run_local_script "$MERGE_READY_NOTIFICATION_SCRIPT"
    outcome_output="$(bash "$OUTCOME_VALIDATOR_SCRIPT" 2>/dev/null || true)"
    if [[ -n "$outcome_output" ]]; then
      printf '%s\n' "$outcome_output"
      stop_implementation_runtime
      break
    fi
    guard_output="$(bash "$SESSION_GUARD_SCRIPT" 2>/dev/null || true)"
    if [[ -n "$guard_output" ]]; then
      printf '%s\n' "$guard_output"
      stop_implementation_runtime
      break
    fi
    guard_output="$(bash "$EMPTY_SPIN_GUARD_SCRIPT" 2>/dev/null || true)"
    if [[ -n "$guard_output" ]]; then
      printf '%s\n' "$guard_output"
      stop_implementation_runtime
      break
    fi
    guard_output="$(bash "$BRANCH_BOOTSTRAP_GUARD_SCRIPT" 2>/dev/null || true)"
    if [[ -n "$guard_output" ]]; then
      printf '%s\n' "$guard_output"
      stop_implementation_runtime
      break
    fi
    guard_output="$(bash "$CODEX_RETRY_GUARD_SCRIPT" 2>/dev/null || true)"
    if [[ -n "$guard_output" ]]; then
      printf '%s\n' "$guard_output"
      stop_implementation_runtime
      break
    fi
    sleep "$SYNC_INTERVAL_SECONDS"
  done
}

cleanup() {
  if [[ -n "${SYNC_LOOP_PID:-}" ]]; then
    kill "$SYNC_LOOP_PID" >/dev/null 2>&1 || true
  fi
  stop_implementation_runtime
  if [[ "$HARNESS_STOP_NOTIFIED" -eq 0 ]]; then
    HARNESS_STOP_NOTIFIED=1
    notify_harness_runtime "stopped" "run_symphony.sh exited or was interrupted."
  fi
  rm -rf "$HARNESS_LOCK_DIR"
}

trap cleanup EXIT INT TERM

acquire_lock
preflight_cleanup
cd "$SYMPHONY_DIR"
notify_harness_runtime "started" "Workflow: WORKFLOW.md, sync interval: ${SYNC_INTERVAL_SECONDS}s"
while true; do
  if ! prelaunch_checks; then
    sleep 2
    continue
  fi

  sync_loop &
  SYNC_LOOP_PID=$!

  /opt/homebrew/bin/mise exec -- ./bin/symphony "$IMPLEMENTATION_WORKFLOW_FILE" --i-understand-that-this-will-be-running-without-the-usual-guardrails &
  IMPLEMENTATION_SYMPHONY_PID=$!
  export IMPLEMENTATION_SYMPHONY_PID
  wait "$IMPLEMENTATION_SYMPHONY_PID" || true

  if [[ -n "${SYNC_LOOP_PID:-}" ]]; then
    kill "$SYNC_LOOP_PID" >/dev/null 2>&1 || true
    wait "$SYNC_LOOP_PID" 2>/dev/null || true
    SYNC_LOOP_PID=""
  fi

  stop_implementation_runtime
  prelaunch_checks >/dev/null || true
  sleep 2
done
