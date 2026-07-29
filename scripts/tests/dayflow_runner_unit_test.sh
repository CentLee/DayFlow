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
assert_success 'primary prompt limits model to edit and test' grep -Fq 'Edit and test only' <<<"$primary_prompt"
assert_success 'primary prompt reserves Git publication for runner' grep -Fq 'Do not run git add, git commit, git push' <<<"$primary_prompt"
assert_success 'primary prompt prohibits repository dumps' grep -Fq 'Never print or request a full repository tree' <<<"$primary_prompt"
assert_success 'primary prompt contains narrow input reference' grep -Fq 'docs/automation-model.md' <<<"$primary_prompt"

assert_eq 'gpt-5.6-terra high' "$(dayflow_model_for_agent integration-agent)" 'integration routing'
assert_eq 'gpt-5.6-terra high' "$(dayflow_model_for_agent product-agent)" 'product routing'
assert_eq 'gpt-5.6-terra high' "$(dayflow_model_for_agent review-agent)" 'review routing'
assert_eq 'gpt-5.6-terra medium' "$(dayflow_model_for_agent backend-agent)" 'backend routing'
assert_eq 'gpt-5.6-terra medium' "$(dayflow_model_for_agent ios-agent)" 'ios routing'
assert_failure 'unknown agent must fail closed' dayflow_model_for_agent unknown-agent
assert_eq 'develop' "$(dayflow_integration_base_branch "$admissible")" 'missing Integration Base defaults to develop'
integration_description="$(jq -r '.description' "$TEST_DIR/fixtures/admissible-integration-base-issue.json")"
assert_eq 'integration/private-two-person-cutover' "$(dayflow_integration_base_branch "$integration_description")" 'exact Integration Base is accepted'
malformed_description="$(jq -r '.description' "$TEST_DIR/fixtures/malformed-integration-base-issue.json")"
assert_failure 'malformed Integration Base fails closed' dayflow_integration_base_branch "$malformed_description"
assert_success 'declared Integration Base passes admission' dayflow_validate_admission "$(<"$TEST_DIR/fixtures/admissible-integration-base-issue.json")"
assert_failure 'malformed Integration Base fails admission without fallback' dayflow_validate_admission "$(<"$TEST_DIR/fixtures/malformed-integration-base-issue.json")"
assert_eq 'feature/tasks-29-replace-symphony-with-dayflow-local-runner' \
  "$(dayflow_branch_name CEN-29 '[Integration] Replace Symphony with DayFlow local runner')" 'branch naming'

assert_success 'first lock acquisition' dayflow_acquire_lock CEN-29
assert_failure 'second lock acquisition must fail' dayflow_acquire_lock CEN-29
dayflow_release_lock

original_shared_lock_attempts="$DAYFLOW_SHARED_LOCK_ATTEMPTS"
DAYFLOW_SHARED_LOCK_ATTEMPTS=2
printf '%s\n' orphan >"$DAYFLOW_STATE_ROOT/merge-ready.lock.tmp"
assert_success 'orphan temp does not block shared lease acquisition' dayflow_acquire_merge_ready_lock
assert_failure 'locked transaction removes pre-existing orphan temp' test -e "$DAYFLOW_STATE_ROOT/merge-ready.lock.tmp"
assert_eq "$DAYFLOW_ACTIVE_MERGE_READY_LOCK_PID" "$(sed -n '2p' "$DAYFLOW_STATE_ROOT/merge-ready.lock")" 'lease records current Bash process PID'
assert_eq "$DAYFLOW_ACTIVE_MERGE_READY_LOCK_IDENTITY" "$(sed -n '3p' "$DAYFLOW_STATE_ROOT/merge-ready.lock")" 'lease records process-start identity'
assert_eq '3' "$(wc -l <"$DAYFLOW_STATE_ROOT/merge-ready.lock" | tr -d ' ')" 'lease metadata is complete'
assert_failure 'live shared lease is busy' dayflow_acquire_merge_ready_lock
dayflow_release_merge_ready_lock
assert_failure 'exact owner release removes shared lease' test -e "$DAYFLOW_STATE_ROOT/merge-ready.lock"
DAYFLOW_SHARED_LOCK_ATTEMPTS="$original_shared_lock_attempts"

flock_ready="$TEST_TMP/flock-ready"
"$DAYFLOW_PERL_BIN" -MFcntl=:flock -e '
  open my $fh, ">>", $ARGV[0] or die;
  flock($fh, LOCK_EX) or die;
  open my $ready, ">", $ARGV[1] or die;
  close $ready;
  kill "STOP", $$;
  pause;
' "$DAYFLOW_STATE_ROOT/merge-ready.lock.mutex" "$flock_ready" &
flock_holder_pid=$!
for _ in $(seq 1 100); do
  [[ -f "$flock_ready" ]] && break
  sleep 0.01
done
assert_success 'real Perl process holds kernel flock' test -f "$flock_ready"
DAYFLOW_SHARED_LOCK_ATTEMPTS=2
assert_failure 'nonblocking flock contention fails within bounded retries' dayflow_acquire_merge_ready_lock
kill -KILL "$flock_holder_pid"
wait "$flock_holder_pid" 2>/dev/null || true
assert_success 'SIGKILL releases kernel flock for next acquisition' dayflow_acquire_merge_ready_lock
dayflow_release_merge_ready_lock
DAYFLOW_SHARED_LOCK_ATTEMPTS="$original_shared_lock_attempts"

printf '%s\n%s\n%s\n' stale-owner 1 invalid >"$DAYFLOW_STATE_ROOT/merge-ready.lock"
race_hold="$TEST_TMP/race-hold"
for label in one two; do
  bash -c '
    source "$1"
    DAYFLOW_SHARED_LOCK_ATTEMPTS=3
    if dayflow_acquire_merge_ready_lock; then
      printf "acquired|%s\n" "$DAYFLOW_ACTIVE_MERGE_READY_LOCK_TOKEN" >"$2"
      while [[ ! -e "$3" ]]; do sleep 0.01; done
      dayflow_release_merge_ready_lock
    else
      printf "failed\n" >"$2"
    fi
  ' _ "$ROOT_DIR/scripts/lib/dayflow_runner.sh" "$TEST_TMP/reclaimer-$label" "$race_hold" &
  if [[ "$label" == one ]]; then
    reclaimer_one_pid=$!
  else
    reclaimer_two_pid=$!
  fi
done
for _ in $(seq 1 100); do
  [[ -f "$TEST_TMP/reclaimer-one" && -f "$TEST_TMP/reclaimer-two" ]] && break
  sleep 0.01
done
assert_success 'both concurrent stale reclaimers reach deterministic result' \
  test -f "$TEST_TMP/reclaimer-one" -a -f "$TEST_TMP/reclaimer-two"
reclaim_result_count="$(rg --no-filename '^(acquired|failed)' "$TEST_TMP/reclaimer-one" "$TEST_TMP/reclaimer-two" | sort | uniq -c | tr -s ' ')"
assert_success 'concurrent stale reclaim has one winner' grep -q ' 1 acquired' <<<"$reclaim_result_count"
assert_success 'concurrent stale reclaim has one bounded loser' grep -q ' 1 failed' <<<"$reclaim_result_count"
touch "$race_hold"
wait "$reclaimer_one_pid"
wait "$reclaimer_two_pid"

dayflow_capture_current_bash_pid
current_owner_pid="$DAYFLOW_CURRENT_BASH_PID"
current_owner_identity="$(dayflow_process_start_identity "$current_owner_pid")"
assert_success 'old owner lease fixture acquisition' \
  dayflow_shared_lock_transaction acquire old-owner "$current_owner_pid" "$current_owner_identity"
assert_success 'exact old owner release' \
  dayflow_shared_lock_transaction release old-owner "$current_owner_pid" "$current_owner_identity"
assert_success 'replacement lease acquisition' \
  dayflow_shared_lock_transaction acquire replacement-owner "$current_owner_pid" "$current_owner_identity"
assert_success 'old release transaction returns safely' \
  dayflow_shared_lock_transaction release old-owner "$current_owner_pid" "$current_owner_identity"
assert_eq 'replacement-owner' "$(sed -n '1p' "$DAYFLOW_STATE_ROOT/merge-ready.lock")" 'old release cannot delete replacement lease'
assert_success 'replacement exact release' \
  dayflow_shared_lock_transaction release replacement-owner "$current_owner_pid" "$current_owner_identity"

dayflow_capture_current_bash_pid
parent_shell_pid="$DAYFLOW_CURRENT_BASH_PID"
bash32_owner_ready="$TEST_TMP/bash32-owner-ready"
(
  DAYFLOW_SHARED_LOCK_ATTEMPTS=2
  if dayflow_acquire_merge_ready_lock; then
    printf '%s|%s\n' \
      "$DAYFLOW_ACTIVE_MERGE_READY_LOCK_PID" \
      "$(sed -n '2p' "$DAYFLOW_STATE_ROOT/merge-ready.lock")" \
      >"$bash32_owner_ready"
    while true; do sleep 1; done
  fi
) &
bash32_owner_job=$!
for _ in $(seq 1 100); do
  [[ -f "$bash32_owner_ready" ]] && break
  sleep 0.01
done
assert_success 'background Bash subshell publishes its actual owner PID' test -f "$bash32_owner_ready"
bash32_owner_pid="$(cut -d '|' -f 1 "$bash32_owner_ready")"
bash32_lease_pid="$(cut -d '|' -f 2 "$bash32_owner_ready")"
assert_eq "$bash32_owner_job" "$bash32_owner_pid" 'captured PID is the background Bash subshell'
assert_eq "$bash32_owner_pid" "$bash32_lease_pid" 'lease records the background Bash subshell PID'
assert_failure 'background Bash subshell PID differs from live parent' test "$bash32_owner_pid" = "$parent_shell_pid"
kill -KILL "$bash32_owner_pid"
wait "$bash32_owner_job" 2>/dev/null || true
assert_success 'parent Bash remains live after subshell SIGKILL' kill -0 "$parent_shell_pid"
assert_success 'stale Bash 3.2 subshell lease is reclaimable' dayflow_acquire_merge_ready_lock
dayflow_release_merge_ready_lock

if (( BASH_VERSINFO[0] >= 4 )); then
  bash_pid_result="$TEST_TMP/bash-pid-result"
  (
    dayflow_acquire_merge_ready_lock
    printf '%s|%s|%s\n' "$$" "$BASHPID" "$(sed -n '2p' "$DAYFLOW_STATE_ROOT/merge-ready.lock")" >"$bash_pid_result"
    dayflow_release_merge_ready_lock
  )
  shell_dollar_pid="$(cut -d '|' -f 1 "$bash_pid_result")"
  shell_bash_pid="$(cut -d '|' -f 2 "$bash_pid_result")"
  lease_bash_pid="$(cut -d '|' -f 3 "$bash_pid_result")"
  assert_failure 'Bash 5 subshell BASHPID differs from inherited dollar PID' test "$shell_dollar_pid" = "$shell_bash_pid"
  assert_eq "$shell_bash_pid" "$lease_bash_pid" 'Bash 5 lease consistently records BASHPID'
fi

usage_log="$TEST_TMP/usage.jsonl"
cat >"$usage_log" <<'EOF'
{"usage":{"input_tokens":100,"cached_input_tokens":90,"output_tokens":10}}
{"usage":{"input_tokens":100,"cached_input_tokens":90,"output_tokens":10}}
{"event":{"usage":{"input_tokens":200,"cached_input_tokens":150,"output_tokens":20}}}
EOF
assert_eq '220' "$(dayflow_jsonl_usage "$usage_log" | jq -r '.raw_total_tokens')" 'repeated cumulative usage snapshots retain raw totals'
assert_eq '150' "$(dayflow_jsonl_usage "$usage_log" | jq -r '.cached_input_tokens')" 'cached cumulative usage'
assert_eq '50' "$(dayflow_jsonl_usage "$usage_log" | jq -r '.uncached_input_tokens')" 'uncached cumulative usage'
assert_eq '70' "$(dayflow_jsonl_billable_tokens "$usage_log")" 'billable usage excludes cached context'

resume_repo="$TEST_TMP/resume-repo"
mkdir -p "$resume_repo"
git -C "$resume_repo" init -b test >/dev/null
git -C "$resume_repo" config user.name 'DayFlow Tests'
git -C "$resume_repo" config user.email 'dayflow@example.invalid'
printf '%s\n' clean >"$resume_repo/README.md"
git -C "$resume_repo" add README.md
git -C "$resume_repo" commit -m seed >/dev/null
current_branch="$(git -C "$resume_repo" branch --show-current)"
printf '%s\n' "{\"worktree\":\"$resume_repo\",\"session_id\":\"session\",\"primary_agent\":\"integration-agent\",\"model\":\"gpt-5.6-terra\",\"reasoning\":\"high\"}" \
  >"$DAYFLOW_STATE_ROOT/CEN-40.json"
assert_success 'matching resume ownership' dayflow_validate_resume_state CEN-40 "$current_branch" integration-agent gpt-5.6-terra high
assert_failure 'resume ownership drift must fail' dayflow_validate_resume_state CEN-40 "$current_branch" backend-agent gpt-5.6-terra medium
printf '%s\n' dirty >>"$resume_repo/README.md"
assert_failure 'dirty resume worktree fails closed' dayflow_validate_resume_state CEN-40 "$current_branch" integration-agent gpt-5.6-terra high
mkdir "$DAYFLOW_STATE_ROOT/CEN-29.lock"
printf '%s\n' '999999' >"$DAYFLOW_STATE_ROOT/CEN-29.lock/pid"
assert_success 'stale lock recovery' dayflow_acquire_lock CEN-29
dayflow_release_lock

printf '%s\n' '{"billable_tokens":0}' >"$DAYFLOW_STATE_ROOT/CEN-29.json"
prompt="$TEST_TMP/prompt"
output="$TEST_TMP/output"
execution_worktree="$TEST_TMP/execution-worktree"
mkdir -p "$execution_worktree"
printf '%s\n' 'test' >"$prompt"

export FAKE_CODEX_MODE=token-limit
DAYFLOW_TOKEN_LIMIT=10
DAYFLOW_STALL_LIMIT_SECONDS=10
DAYFLOW_EXECUTION_LIMIT_SECONDS=10
DAYFLOW_MONITOR_INTERVAL_SECONDS=0.1
if dayflow_execute_bounded CEN-29 primary-new "$execution_worktree" fake-model medium '' "$prompt" "$TEST_TMP/token.jsonl" "$output"; then
  test_fail 'token limit execution should fail'
fi
assert_eq 'token limit exceeded (10)' "$DAYFLOW_EXECUTION_ERROR" 'token limit reason'

printf '%s\n' '{"billable_tokens":10}' >"$DAYFLOW_STATE_ROOT/CEN-32.json"
export FAKE_CODEX_INVOCATION_COUNT_FILE="$TEST_TMP/prelaunch-count"
export FAKE_CODEX_MODE=success
DAYFLOW_TOKEN_LIMIT=10
if dayflow_execute_bounded CEN-32 primary-new "$execution_worktree" fake-model medium '' "$prompt" "$TEST_TMP/prelaunch.jsonl" "$output"; then
  test_fail 'exact prelaunch token cap should fail'
fi
assert_eq 'token limit reached before launch (10)' "$DAYFLOW_EXECUTION_ERROR" 'prelaunch token boundary'
assert_failure 'prelaunch rejection must not invoke Codex' test -e "$FAKE_CODEX_INVOCATION_COUNT_FILE"

printf '%s\n' '{"billable_tokens":0}' >"$DAYFLOW_STATE_ROOT/CEN-33.json"
unset FAKE_CODEX_INVOCATION_COUNT_FILE
export FAKE_CODEX_MODE=fast-overflow
if dayflow_execute_bounded CEN-33 primary-new "$execution_worktree" fake-model medium '' "$prompt" "$TEST_TMP/fast-overflow.jsonl" "$output"; then
  test_fail 'successful fast exit at token cap should fail'
fi
assert_eq 'token limit exceeded after process exit (10)' "$DAYFLOW_EXECUTION_ERROR" 'post-wait token boundary'

printf '%s\n' '{"billable_tokens":0}' >"$DAYFLOW_STATE_ROOT/CEN-35.json"
export FAKE_CODEX_MODE=late-usage
DAYFLOW_TOKEN_LIMIT=1000
if ! dayflow_execute_bounded CEN-35 primary-new "$execution_worktree" fake-model medium '' "$prompt" "$TEST_TMP/late.jsonl" "$output"; then
  test_fail 'late final usage should remain within the test limit'
fi
assert_eq '70' "$(jq -r '.billable_tokens' "$DAYFLOW_STATE_ROOT/CEN-35.json")" 'late billable usage persisted after process exit'
assert_eq '150' "$(jq -r '.usage.cached_input_tokens' "$DAYFLOW_STATE_ROOT/CEN-35.json")" 'late cached usage persisted'
assert_eq '50' "$(jq -r '.usage.uncached_input_tokens' "$DAYFLOW_STATE_ROOT/CEN-35.json")" 'late uncached usage persisted'
assert_eq '220' "$(jq -r '.usage.raw_total_tokens' "$DAYFLOW_STATE_ROOT/CEN-35.json")" 'late raw usage persisted separately'
assert_eq '70' "$(jq -r '.usage.billable_tokens' "$DAYFLOW_STATE_ROOT/CEN-35.json")" 'late billable usage persisted separately'

printf '%s\n' '{"billable_tokens":0}' >"$DAYFLOW_STATE_ROOT/CEN-38.json"
export FAKE_CODEX_MODE=cached-live-under-cap
DAYFLOW_TOKEN_LIMIT=120000
if ! dayflow_execute_bounded CEN-38 primary-new "$execution_worktree" fake-model medium '' "$prompt" "$TEST_TMP/cached-under-cap.jsonl" "$output"; then
  test_fail 'large cached context below the billable cap should complete'
fi
assert_eq '87595' "$(jq -r '.billable_tokens' "$DAYFLOW_STATE_ROOT/CEN-38.json")" 'large cached context persists billable usage only'
assert_eq '1117483' "$(jq -r '.usage.raw_total_tokens' "$DAYFLOW_STATE_ROOT/CEN-38.json")" 'large cached context remains observable as raw usage'
assert_eq '1029888' "$(jq -r '.usage.cached_input_tokens' "$DAYFLOW_STATE_ROOT/CEN-38.json")" 'large cached context remains separately observable'

printf '%s\n' '{"billable_tokens":0}' >"$DAYFLOW_STATE_ROOT/CEN-39.json"
export FAKE_CODEX_MODE=billable-live-over-cap
if dayflow_execute_bounded CEN-39 primary-new "$execution_worktree" fake-model medium '' "$prompt" "$TEST_TMP/billable-live-over-cap.jsonl" "$output"; then
  test_fail 'live billable over-cap usage should stop Codex'
fi
assert_eq 'token limit exceeded (120000)' "$DAYFLOW_EXECUTION_ERROR" 'live cap uses billable usage'
assert_eq '139000' "$(jq -r '.billable_tokens' "$DAYFLOW_STATE_ROOT/CEN-39.json")" 'live over-cap persists billable usage'

printf '%s\n' '{"billable_tokens":0}' >"$DAYFLOW_STATE_ROOT/CEN-41.json"
export FAKE_CODEX_MODE=billable-post-exit-over-cap
if dayflow_execute_bounded CEN-41 primary-new "$execution_worktree" fake-model medium '' "$prompt" "$TEST_TMP/billable-post-exit-over-cap.jsonl" "$output"; then
  test_fail 'post-exit billable over-cap usage should fail'
fi
assert_eq 'token limit exceeded after process exit (120000)' "$DAYFLOW_EXECUTION_ERROR" 'post-exit cap uses billable usage'
assert_eq '120001' "$(jq -r '.billable_tokens' "$DAYFLOW_STATE_ROOT/CEN-41.json")" 'post-exit over-cap persists billable usage'

printf '%s\n' '{"billable_tokens":0}' >"$DAYFLOW_STATE_ROOT/CEN-36.json"
oversized_prompt="$TEST_TMP/oversized-prompt"
printf '%040d\n' 0 >"$oversized_prompt"
DAYFLOW_PROMPT_LIMIT_BYTES=16
export FAKE_CODEX_INVOCATION_COUNT_FILE="$TEST_TMP/prompt-limit-count"
if dayflow_execute_bounded CEN-36 primary-new "$execution_worktree" fake-model medium '' "$oversized_prompt" "$TEST_TMP/prompt-limit.jsonl" "$output"; then
  test_fail 'oversized prompt should fail before Codex launch'
fi
assert_failure 'prompt limit must not invoke Codex' test -e "$FAKE_CODEX_INVOCATION_COUNT_FILE"
DAYFLOW_PROMPT_LIMIT_BYTES=32768
unset FAKE_CODEX_INVOCATION_COUNT_FILE

printf '%s\n' '{"billable_tokens":0}' >"$DAYFLOW_STATE_ROOT/CEN-37.json"
export FAKE_CODEX_MODE=output-limit
DAYFLOW_LOG_LIMIT_BYTES=512
if dayflow_execute_bounded CEN-37 primary-new "$execution_worktree" fake-model medium '' "$prompt" "$TEST_TMP/output-limit.jsonl" "$output"; then
  test_fail 'command output limit should stop Codex'
fi
assert_eq 'command output limit exceeded (512 bytes)' "$DAYFLOW_EXECUTION_ERROR" 'command output bound reason'
DAYFLOW_LOG_LIMIT_BYTES=5242880

printf '%s\n' '{"billable_tokens":0}' >"$DAYFLOW_STATE_ROOT/CEN-30.json"
export FAKE_CODEX_MODE=stall
DAYFLOW_TOKEN_LIMIT=1000
DAYFLOW_STALL_LIMIT_SECONDS=1
DAYFLOW_EXECUTION_LIMIT_SECONDS=10
if dayflow_execute_bounded CEN-30 primary-new "$execution_worktree" fake-model medium '' "$prompt" "$TEST_TMP/stall.jsonl" "$output"; then
  test_fail 'stall execution should fail'
fi
assert_eq 'no progress for 1s' "$DAYFLOW_EXECUTION_ERROR" 'stall limit reason'

printf '%s\n' '{"billable_tokens":0}' >"$DAYFLOW_STATE_ROOT/CEN-31.json"
export FAKE_CODEX_MODE=execution-limit
DAYFLOW_STALL_LIMIT_SECONDS=10
DAYFLOW_EXECUTION_LIMIT_SECONDS=1
if dayflow_execute_bounded CEN-31 primary-new "$execution_worktree" fake-model medium '' "$prompt" "$TEST_TMP/execution.jsonl" "$output"; then
  test_fail 'execution limit should fail'
fi
assert_eq 'execution limit exceeded (1s)' "$DAYFLOW_EXECUTION_ERROR" 'execution limit reason'

printf '%s\n' '{"billable_tokens":0}' >"$DAYFLOW_STATE_ROOT/CEN-34.json"
export FAKE_CODEX_MODE=spawn-child
export FAKE_CODEX_PARENT_PID_FILE="$TEST_TMP/codex-parent.pid"
export FAKE_CODEX_CHILD_PID_FILE="$TEST_TMP/codex-child.pid"
DAYFLOW_TOKEN_LIMIT=1000
DAYFLOW_STALL_LIMIT_SECONDS=30
DAYFLOW_EXECUTION_LIMIT_SECONDS=30
(
  dayflow_acquire_lock CEN-34
  dayflow_install_cleanup_traps
  dayflow_execute_bounded CEN-34 primary-new "$execution_worktree" fake-model medium '' "$prompt" "$TEST_TMP/cleanup.jsonl" "$output"
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
