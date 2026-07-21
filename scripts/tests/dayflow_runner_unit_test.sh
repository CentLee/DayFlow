#!/usr/bin/env bash
set -euo pipefail

TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$TEST_DIR/../.." && pwd)"
# shellcheck source=scripts/tests/testlib.sh
source "$TEST_DIR/testlib.sh"

TEST_TMP="$(mktemp -d)"
trap 'rm -rf "$TEST_TMP"' EXIT
export DAYFLOW_ROOT_DIR="$ROOT_DIR"
export DAYFLOW_RUNTIME_DIR="$TEST_TMP/runtime"
export DAYFLOW_WORKTREE_ROOT="$DAYFLOW_RUNTIME_DIR/worktrees"
export DAYFLOW_STATE_ROOT="$DAYFLOW_RUNTIME_DIR/state"
export DAYFLOW_LOG_ROOT="$DAYFLOW_RUNTIME_DIR/logs"
export DAYFLOW_LEGACY_RUNTIME_DIR="$TEST_TMP/legacy"
export DAYFLOW_CODEX_BIN="$TEST_DIR/fakes/codex"
export FAKE_CODEX_LOG="$TEST_TMP/codex.log"
export FAKE_CODEX_REVIEW_COUNT_FILE="$TEST_TMP/review-count"
# shellcheck source=scripts/lib/dayflow_runner.sh
source "$ROOT_DIR/scripts/lib/dayflow_runner.sh"

dayflow_initialize_runtime

admissible="$(<"$TEST_DIR/fixtures/admissible-issue.json")"
invalid="$(<"$TEST_DIR/fixtures/invalid-issue.json")"
assert_success 'admissible fixture should pass' dayflow_validate_admission "$admissible"
assert_failure 'invalid fixture should fail admission' dayflow_validate_admission "$invalid"

assert_eq 'gpt-5.6-sol high' "$(dayflow_model_for_agent integration-agent)" 'integration routing'
assert_eq 'gpt-5.6-sol high' "$(dayflow_model_for_agent product-agent)" 'product routing'
assert_eq 'gpt-5.6-sol high' "$(dayflow_model_for_agent review-agent)" 'review routing'
assert_eq 'gpt-5.6-terra medium' "$(dayflow_model_for_agent backend-agent)" 'backend routing'
assert_eq 'gpt-5.6-terra medium' "$(dayflow_model_for_agent ios-agent)" 'ios routing'
assert_failure 'unknown agent must fail closed' dayflow_model_for_agent unknown-agent
assert_eq 'feature/tasks-29-replace-symphony-with-dayflow-local-runner' \
  "$(dayflow_branch_name CEN-29 '[Integration] Replace Symphony with DayFlow local runner')" 'branch naming'

assert_success 'first lock acquisition' dayflow_acquire_lock CEN-29
assert_failure 'second lock acquisition must fail' dayflow_acquire_lock CEN-29
dayflow_release_lock
mkdir "$DAYFLOW_STATE_ROOT/CEN-29.lock"
printf '%s\n' '999999' >"$DAYFLOW_STATE_ROOT/CEN-29.lock/pid"
assert_success 'stale lock recovery' dayflow_acquire_lock CEN-29
dayflow_release_lock

printf '%s\n' '{"tokens_used":0}' >"$DAYFLOW_STATE_ROOT/CEN-29.json"
prompt="$TEST_TMP/prompt"
output="$TEST_TMP/output"
printf '%s\n' 'test' >"$prompt"

export FAKE_CODEX_MODE=token-limit
DAYFLOW_TOKEN_LIMIT=10
DAYFLOW_STALL_LIMIT_SECONDS=10
DAYFLOW_EXECUTION_LIMIT_SECONDS=10
DAYFLOW_MONITOR_INTERVAL_SECONDS=0.1
if dayflow_execute_bounded CEN-29 primary-new "$ROOT_DIR" fake-model medium '' "$prompt" "$TEST_TMP/token.jsonl" "$output"; then
  test_fail 'token limit execution should fail'
fi
assert_eq 'token limit exceeded (10)' "$DAYFLOW_EXECUTION_ERROR" 'token limit reason'

printf '%s\n' '{"tokens_used":0}' >"$DAYFLOW_STATE_ROOT/CEN-30.json"
export FAKE_CODEX_MODE=stall
DAYFLOW_TOKEN_LIMIT=1000
DAYFLOW_STALL_LIMIT_SECONDS=1
DAYFLOW_EXECUTION_LIMIT_SECONDS=10
if dayflow_execute_bounded CEN-30 primary-new "$ROOT_DIR" fake-model medium '' "$prompt" "$TEST_TMP/stall.jsonl" "$output"; then
  test_fail 'stall execution should fail'
fi
assert_eq 'no progress for 1s' "$DAYFLOW_EXECUTION_ERROR" 'stall limit reason'

printf '%s\n' '{"tokens_used":0}' >"$DAYFLOW_STATE_ROOT/CEN-31.json"
export FAKE_CODEX_MODE=execution-limit
DAYFLOW_STALL_LIMIT_SECONDS=10
DAYFLOW_EXECUTION_LIMIT_SECONDS=1
if dayflow_execute_bounded CEN-31 primary-new "$ROOT_DIR" fake-model medium '' "$prompt" "$TEST_TMP/execution.jsonl" "$output"; then
  test_fail 'execution limit should fail'
fi
assert_eq 'execution limit exceeded (1s)' "$DAYFLOW_EXECUTION_ERROR" 'execution limit reason'

finish_tests 'dayflow_runner_unit_test'
