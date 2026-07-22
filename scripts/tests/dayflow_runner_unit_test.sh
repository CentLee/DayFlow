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
export FAKE_CURL_LOG="$TEST_TMP/curl.log"
# shellcheck source=scripts/lib/dayflow_runner.sh
source "$ROOT_DIR/scripts/lib/dayflow_runner.sh"

mkdir -p "$DAYFLOW_LEGACY_RUNTIME_DIR/gh" "$DAYFLOW_LEGACY_RUNTIME_DIR/artifacts"
printf '%s\n' 'legacy-auth' >"$DAYFLOW_LEGACY_RUNTIME_DIR/gh/hosts.yml"
printf '%s\n' 'DAYFLOW_DISCORD_WEBHOOK_URL=https://legacy.test/webhook' >"$DAYFLOW_LEGACY_RUNTIME_DIR/notifications.env"
printf '%s\n' '{"29":{"issue_key":"CEN-29","branch":"feature/tasks-29-runner","head_sha":"legacy-sha"},"30":{"identifier":"CEN-30","head_sha":"identifier-sha"},"metadata":"preserve-me"}' \
  >"$DAYFLOW_LEGACY_RUNTIME_DIR/artifacts/merge_ready_notifications.json"
dayflow_initialize_runtime
assert_eq 'legacy-sha' "$(jq -r '.["CEN-29"].head_sha' "$DAYFLOW_MERGE_READY_STORE")" 'legacy dedupe migration'
assert_eq '29' "$(jq -r '.["CEN-29"].pr_number' "$DAYFLOW_MERGE_READY_STORE")" 'legacy PR key migration'
assert_eq 'identifier-sha' "$(jq -r '.["CEN-30"].head_sha' "$DAYFLOW_MERGE_READY_STORE")" 'identifier dedupe migration'
assert_eq 'preserve-me' "$(jq -r '.metadata' "$DAYFLOW_MERGE_READY_STORE")" 'legacy metadata preservation'
assert_success 'legacy dedupe source preserved' test -f "$DAYFLOW_LEGACY_RUNTIME_DIR/artifacts/merge_ready_notifications.json"

admissible="$(<"$TEST_DIR/fixtures/admissible-issue.json")"
invalid="$(<"$TEST_DIR/fixtures/invalid-issue.json")"
assert_success 'admissible fixture should pass' dayflow_validate_admission "$admissible"
assert_failure 'invalid fixture should fail admission' dayflow_validate_admission "$invalid"
primary_prompt="$(dayflow_issue_prompt "$admissible" integration-agent)"
assert_success 'primary prompt requires a draft PR' grep -Fq 'a draft PR targeting develop' <<<"$primary_prompt"
assert_success 'primary prompt reserves ready transition for runner' grep -Fq 'Do not mark the PR ready' <<<"$primary_prompt"

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

usage_log="$TEST_TMP/usage.jsonl"
cat >"$usage_log" <<'EOF'
{"usage":{"input_tokens":2,"output_tokens":3}}
{"event":{"usage":{"totalTokens":7}}}
{"item":{"usage":{"prompt_tokens":5,"completion_tokens":6}}}
EOF
assert_eq '23' "$(dayflow_jsonl_tokens "$usage_log")" 'live token usage shapes'

current_branch="$(git -C "$ROOT_DIR" branch --show-current)"
printf '%s\n' "{\"worktree\":\"$ROOT_DIR\",\"session_id\":\"session\",\"primary_agent\":\"integration-agent\",\"model\":\"gpt-5.6-sol\",\"reasoning\":\"high\"}" \
  >"$DAYFLOW_STATE_ROOT/CEN-40.json"
assert_success 'matching resume ownership' dayflow_validate_resume_state CEN-40 "$current_branch" integration-agent gpt-5.6-sol high
assert_failure 'resume ownership drift must fail' dayflow_validate_resume_state CEN-40 "$current_branch" backend-agent gpt-5.6-terra medium
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

printf '%s\n' '{"tokens_used":10}' >"$DAYFLOW_STATE_ROOT/CEN-32.json"
export FAKE_CODEX_INVOCATION_COUNT_FILE="$TEST_TMP/prelaunch-count"
export FAKE_CODEX_MODE=success
DAYFLOW_TOKEN_LIMIT=10
if dayflow_execute_bounded CEN-32 primary-new "$ROOT_DIR" fake-model medium '' "$prompt" "$TEST_TMP/prelaunch.jsonl" "$output"; then
  test_fail 'exact prelaunch token cap should fail'
fi
assert_eq 'token limit reached before launch (10)' "$DAYFLOW_EXECUTION_ERROR" 'prelaunch token boundary'
assert_failure 'prelaunch rejection must not invoke Codex' test -e "$FAKE_CODEX_INVOCATION_COUNT_FILE"

printf '%s\n' '{"tokens_used":0}' >"$DAYFLOW_STATE_ROOT/CEN-33.json"
unset FAKE_CODEX_INVOCATION_COUNT_FILE
export FAKE_CODEX_MODE=fast-overflow
if dayflow_execute_bounded CEN-33 primary-new "$ROOT_DIR" fake-model medium '' "$prompt" "$TEST_TMP/fast-overflow.jsonl" "$output"; then
  test_fail 'successful fast exit at token cap should fail'
fi
assert_eq 'token limit exceeded after process exit (10)' "$DAYFLOW_EXECUTION_ERROR" 'post-wait token boundary'

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

printf '%s\n' '{"tokens_used":0}' >"$DAYFLOW_STATE_ROOT/CEN-34.json"
export FAKE_CODEX_MODE=spawn-child
export FAKE_CODEX_PARENT_PID_FILE="$TEST_TMP/codex-parent.pid"
export FAKE_CODEX_CHILD_PID_FILE="$TEST_TMP/codex-child.pid"
DAYFLOW_TOKEN_LIMIT=1000
DAYFLOW_STALL_LIMIT_SECONDS=30
DAYFLOW_EXECUTION_LIMIT_SECONDS=30
(
  dayflow_acquire_lock CEN-34
  dayflow_install_cleanup_traps
  dayflow_execute_bounded CEN-34 primary-new "$ROOT_DIR" fake-model medium '' "$prompt" "$TEST_TMP/cleanup.jsonl" "$output"
) &
cleanup_runner_pid=$!
for _ in $(seq 1 50); do
  [[ -f "$FAKE_CODEX_CHILD_PID_FILE" ]] && break
  sleep 0.1
done
assert_success 'cleanup fixture started' test -f "$FAKE_CODEX_CHILD_PID_FILE"
cleanup_child_pid="$(<"$FAKE_CODEX_CHILD_PID_FILE")"
sleep 30 &
unrelated_pid=$!
kill -TERM "$cleanup_runner_pid"
wait "$cleanup_runner_pid" 2>/dev/null || true
sleep 0.3
assert_failure 'active Codex descendant must be terminated' kill -0 "$cleanup_child_pid"
assert_success 'unrelated process must remain alive' kill -0 "$unrelated_pid"
kill -TERM "$unrelated_pid" 2>/dev/null || true

status_runtime="$TEST_TMP/status-only"
DAYFLOW_RUNTIME_DIR="$status_runtime" \
DAYFLOW_WORKTREE_ROOT="$status_runtime/worktrees" \
DAYFLOW_STATE_ROOT="$status_runtime/state" \
DAYFLOW_LOG_ROOT="$status_runtime/logs" \
DAYFLOW_CURL_BIN="$TEST_DIR/fakes/curl" \
  "$ROOT_DIR/scripts/dayflow_runner.sh" status CEN-999 >/dev/null
assert_failure 'status must not create runtime directories' test -e "$status_runtime"

finish_tests 'dayflow_runner_unit_test'
