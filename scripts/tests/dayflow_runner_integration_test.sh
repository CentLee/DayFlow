#!/usr/bin/env bash
set -euo pipefail

TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SOURCE_ROOT="$(cd "$TEST_DIR/../.." && pwd)"
# shellcheck source=scripts/tests/testlib.sh
source "$TEST_DIR/testlib.sh"
# shellcheck source=scripts/tests/system_test_helpers.sh
source "$TEST_DIR/system_test_helpers.sh"

run_review_remediation_test() {
  local test_root seed
  test_root="$(mktemp -d)"
  seed="$(dayflow_create_test_repo "$test_root" "$SOURCE_ROOT")"
  dayflow_export_fake_environment "$test_root" "$SOURCE_ROOT" "$seed"
  dayflow_prepare_notification_fixture
  export FAKE_CODEX_MODE=success
  export FAKE_REVIEW_MODE=remediate
  : >"$FAKE_GH_READY_FILE"

  "$SOURCE_ROOT/scripts/dayflow_runner.sh" run CEN-29 >/dev/null
  assert_eq 'merge-ready' "$(jq -r '.status' "$DAYFLOW_STATE_ROOT/CEN-29.json")" 'remediation path status'
  assert_eq '2' "$(<"$FAKE_CODEX_REVIEW_COUNT_FILE")" 'review rerun count'
  assert_file_contains "$FAKE_CODEX_LOG" 'resume' 'same primary session was resumed'
  assert_file_contains "$FAKE_GH_LOG" 'ready.*--undo' 'blocking review returned PR to draft'
  assert_file_contains "$FAKE_GH_COMMENTS_LOG" 'Proof needs refresh' 'blocking review was published'
  assert_file_contains "$FAKE_GH_COMMENTS_LOG" 'Outcome:.*passed' 'clean rereview was published'
  assert_success 'clean rereview returned PR to ready' test -f "$FAKE_GH_READY_FILE"
  rm -rf "$test_root"
}

run_delivery_integrity_test() {
  local test_root seed
  test_root="$(mktemp -d)"
  seed="$(dayflow_create_test_repo "$test_root" "$SOURCE_ROOT")"
  dayflow_export_fake_environment "$test_root" "$SOURCE_ROOT" "$seed"
  dayflow_prepare_notification_fixture
  export FAKE_CODEX_MODE=success FAKE_REVIEW_MODE=clean FAKE_GH_HEAD_SHA_OVERRIDE=stale-pr-head

  if "$SOURCE_ROOT/scripts/dayflow_runner.sh" run CEN-29 >/dev/null 2>&1; then
    test_fail 'delivery with mismatched PR head should fail'
  fi
  assert_eq 'blocked' "$(jq -r '.status' "$DAYFLOW_STATE_ROOT/CEN-29.json")" 'delivery mismatch blocked'
  assert_failure 'review must not run on mismatched delivery' test -e "$FAKE_CODEX_REVIEW_COUNT_FILE"
  rm -rf "$test_root"
}

run_review_execution_failure_draft_test() {
  local test_root seed
  test_root="$(mktemp -d)"
  seed="$(dayflow_create_test_repo "$test_root" "$SOURCE_ROOT")"
  dayflow_export_fake_environment "$test_root" "$SOURCE_ROOT" "$seed"
  dayflow_prepare_notification_fixture
  export FAKE_CODEX_MODE=success FAKE_REVIEW_MODE=execution-fail FAKE_REQUIRE_DRAFT_REVIEW=true
  export FAKE_REVIEW_DRAFT_MARKER="$test_root/review-started-draft"
  : >"$FAKE_GH_READY_FILE"

  if "$SOURCE_ROOT/scripts/dayflow_runner.sh" run CEN-29 >/dev/null 2>&1; then
    test_fail 'review execution failure should block the run'
  fi
  assert_success 'first review started only after PR became draft' test -f "$FAKE_REVIEW_DRAFT_MARKER"
  assert_failure 'review execution failure leaves PR draft' test -f "$FAKE_GH_READY_FILE"
  assert_file_contains "$FAKE_GH_LOG" 'ready.*--undo' 'delivery was forced to draft before review'
  assert_eq 'blocked' "$(jq -r '.status' "$DAYFLOW_STATE_ROOT/CEN-29.json")" 'review execution failure state'
  assert_eq '' "$(jq -r '.reviewed_head_sha // ""' "$DAYFLOW_STATE_ROOT/CEN-29.json")" 'failed review does not persist reviewed head'
  rm -rf "$test_root"
}

run_start_transition_failure_test() {
  local test_root seed worktree
  test_root="$(mktemp -d)"
  seed="$(dayflow_create_test_repo "$test_root" "$SOURCE_ROOT")"
  dayflow_export_fake_environment "$test_root" "$SOURCE_ROOT" "$seed"
  dayflow_prepare_notification_fixture
  export FAKE_CODEX_MODE=success FAKE_REVIEW_MODE=clean FAKE_LINEAR_FAIL_STATE=state-in-progress

  if "$SOURCE_ROOT/scripts/dayflow_runner.sh" run CEN-29 >/dev/null 2>&1; then
    test_fail 'failed In Progress transition should stop before Codex'
  fi
  assert_eq 'pre-session-blocked' "$(jq -r '.status' "$DAYFLOW_STATE_ROOT/CEN-29.json")" 'pre-session recovery state'
  assert_success 'worktree preserved after transition failure' test -e "$DAYFLOW_WORKTREE_ROOT/CEN-29/.git"
  assert_failure 'Codex not launched after transition failure' test -e "$FAKE_CODEX_LOG"
  worktree="$(jq -r '.worktree' "$DAYFLOW_STATE_ROOT/CEN-29.json")"

  unset FAKE_LINEAR_FAIL_STATE
  "$SOURCE_ROOT/scripts/dayflow_runner.sh" run CEN-29 >/dev/null
  assert_eq "$worktree" "$(jq -r '.worktree' "$DAYFLOW_STATE_ROOT/CEN-29.json")" 'pre-session retry reuses owned worktree'
  assert_eq 'fake-primary-session' "$(jq -r '.session_id' "$DAYFLOW_STATE_ROOT/CEN-29.json")" 'pre-session retry starts a new primary session'
  assert_eq 'merge-ready' "$(jq -r '.status' "$DAYFLOW_STATE_ROOT/CEN-29.json")" 'pre-session retry completes lifecycle'
  assert_failure 'pre-session retry must not use resume mode' rg -q -- 'resume' "$FAKE_CODEX_LOG"
  rm -rf "$test_root"
}

run_review_visibility_test() {
  local test_root seed
  test_root="$(mktemp -d)"
  seed="$(dayflow_create_test_repo "$test_root" "$SOURCE_ROOT")"
  dayflow_export_fake_environment "$test_root" "$SOURCE_ROOT" "$seed"
  dayflow_prepare_notification_fixture
  export FAKE_CODEX_MODE=success FAKE_REVIEW_MODE=p3

  "$SOURCE_ROOT/scripts/dayflow_runner.sh" run CEN-29 >/dev/null
  assert_file_contains "$FAKE_GH_COMMENTS_LOG" '\[P3\] Minor follow-up' 'P3 review visibility'
  assert_file_contains "$FAKE_GH_COMMENTS_LOG" 'Manual verification remains' 'residual risk visibility'
  rm -rf "$test_root"
}

run_final_blocker_visibility_test() {
  local test_root seed blocker_count
  test_root="$(mktemp -d)"
  seed="$(dayflow_create_test_repo "$test_root" "$SOURCE_ROOT")"
  dayflow_export_fake_environment "$test_root" "$SOURCE_ROOT" "$seed"
  dayflow_prepare_notification_fixture
  export FAKE_CODEX_MODE=success FAKE_REVIEW_MODE=always-block

  if "$SOURCE_ROOT/scripts/dayflow_runner.sh" run CEN-29 >/dev/null 2>&1; then
    test_fail 'unresolved second review must block'
  fi
  blocker_count="$(rg -c 'Unresolved blocker' "$FAKE_GH_COMMENTS_LOG")"
  assert_eq '2' "$blocker_count" 'every unresolved review result published'
  assert_eq 'blocked' "$(jq -r '.status' "$DAYFLOW_STATE_ROOT/CEN-29.json")" 'final blocker state'
  assert_failure 'final blocker PR remains draft' test -f "$FAKE_GH_READY_FILE"
  rm -rf "$test_root"
}

run_ci_timeout_test() {
  local test_root seed invocation_count
  test_root="$(mktemp -d)"
  seed="$(dayflow_create_test_repo "$test_root" "$SOURCE_ROOT")"
  dayflow_export_fake_environment "$test_root" "$SOURCE_ROOT" "$seed"
  dayflow_prepare_notification_fixture
  export FAKE_CODEX_MODE=success FAKE_REVIEW_MODE=clean FAKE_GH_CHECK_MODE=pending
  export DAYFLOW_CI_WAIT_TIMEOUT_SECONDS=1
  export FAKE_CODEX_INVOCATION_COUNT_FILE="$test_root/invocations"

  "$SOURCE_ROOT/scripts/dayflow_runner.sh" run CEN-29 >/dev/null
  assert_eq 'in-review-ci-timeout' "$(jq -r '.status' "$DAYFLOW_STATE_ROOT/CEN-29.json")" 'bounded CI timeout state'
  invocation_count="$(<"$FAKE_CODEX_INVOCATION_COUNT_FILE")"
  assert_eq '2' "$invocation_count" 'CI polling consumed no Codex turns'
  assert_success 'timed-out PR remains ready for later reconcile' test -f "$FAKE_GH_READY_FILE"
  rm -rf "$test_root"
}

run_webhook_retry_and_lock_test() {
  local test_root seed first_rc=0 second_rc=0 merge_ready_count
  test_root="$(mktemp -d)"
  seed="$(dayflow_create_test_repo "$test_root" "$SOURCE_ROOT")"
  dayflow_export_fake_environment "$test_root" "$SOURCE_ROOT" "$seed"
  dayflow_prepare_notification_fixture
  export FAKE_CODEX_MODE=success FAKE_REVIEW_MODE=clean
  export FAKE_WEBHOOK_FAILURES_FILE="$test_root/webhook-failures"
  printf '%s\n' '1' >"$FAKE_WEBHOOK_FAILURES_FILE"

  if "$SOURCE_ROOT/scripts/dayflow_runner.sh" run CEN-29 >/dev/null 2>&1; then
    test_fail 'failed merge-ready webhook should surface failure'
  fi
  assert_eq 'merge-ready-notification-failed' "$(jq -r '.status' "$DAYFLOW_STATE_ROOT/CEN-29.json")" 'failed webhook state'
  assert_eq '' "$(jq -r '.["CEN-29"].head_sha // ""' "$DAYFLOW_MERGE_READY_STORE")" 'failed webhook not deduped'
  "$SOURCE_ROOT/scripts/dayflow_runner.sh" reconcile CEN-29 >/dev/null
  assert_eq 'merge-ready' "$(jq -r '.status' "$DAYFLOW_STATE_ROOT/CEN-29.json")" 'webhook retry succeeds'

  printf '%s\n' '{}' >"$DAYFLOW_MERGE_READY_STORE"
  : >"$FAKE_CURL_LOG"
  export FAKE_WEBHOOK_DELAY_SECONDS=0.5
  "$SOURCE_ROOT/scripts/dayflow_runner.sh" reconcile CEN-29 >/dev/null &
  first_pid=$!
  "$SOURCE_ROOT/scripts/dayflow_runner.sh" reconcile CEN-29 >/dev/null 2>&1 &
  second_pid=$!
  wait "$first_pid" || first_rc=$?
  wait "$second_pid" || second_rc=$?
  [[ "$first_rc" == "0" || "$second_rc" == "0" ]] || test_fail 'one concurrent reconcile must succeed'
  merge_ready_count="$(rg -c 'merge-ready' "$FAKE_CURL_LOG")"
  assert_eq '1' "$merge_ready_count" 'concurrent reconcile sends one merge-ready webhook'
  rm -rf "$test_root"
}

run_merged_base_integrity_test() {
  local test_root seed state_file branch worktree head
  test_root="$(mktemp -d)"
  seed="$(dayflow_create_test_repo "$test_root" "$SOURCE_ROOT")"
  dayflow_export_fake_environment "$test_root" "$SOURCE_ROOT" "$seed"
  dayflow_prepare_notification_fixture
  export FAKE_CODEX_MODE=success FAKE_REVIEW_MODE=clean
  "$SOURCE_ROOT/scripts/dayflow_runner.sh" run CEN-29 >/dev/null
  export FAKE_GH_PR_STATE=MERGED FAKE_GH_BASE_BRANCH=main
  if "$SOURCE_ROOT/scripts/dayflow_runner.sh" reconcile CEN-29 >/dev/null 2>&1; then
    test_fail 'merged non-develop PR must not close the issue'
  fi
  state_file="$DAYFLOW_STATE_ROOT/CEN-29.json"
  assert_failure 'non-develop merge must not mark Done' test "$(jq -r '.status' "$state_file")" = done
  rm -rf "$test_root"
}

run_merged_reviewed_head_integrity_test() {
  local test_root seed state_file reviewed_head tmp_file
  test_root="$(mktemp -d)"
  seed="$(dayflow_create_test_repo "$test_root" "$SOURCE_ROOT")"
  dayflow_export_fake_environment "$test_root" "$SOURCE_ROOT" "$seed"
  dayflow_prepare_notification_fixture
  export FAKE_CODEX_MODE=success FAKE_REVIEW_MODE=clean
  "$SOURCE_ROOT/scripts/dayflow_runner.sh" run CEN-29 >/dev/null
  state_file="$DAYFLOW_STATE_ROOT/CEN-29.json"
  reviewed_head="$(jq -r '.reviewed_head_sha' "$state_file")"
  tmp_file="$state_file.tmp"

  jq 'del(.reviewed_head_sha)' "$state_file" >"$tmp_file"
  mv "$tmp_file" "$state_file"
  export FAKE_GH_PR_STATE=MERGED
  if "$SOURCE_ROOT/scripts/dayflow_runner.sh" reconcile CEN-29 >/dev/null 2>&1; then
    test_fail 'merged PR without a reviewed head must fail closed'
  fi
  assert_eq 'merged-review-mismatch' "$(jq -r '.status' "$state_file")" 'missing merged reviewed head state'

  jq --arg reviewed "$reviewed_head" '.reviewed_head_sha = $reviewed' "$state_file" >"$tmp_file"
  mv "$tmp_file" "$state_file"
  export FAKE_GH_HEAD_SHA_OVERRIDE=unreviewed-merged-head
  if "$SOURCE_ROOT/scripts/dayflow_runner.sh" reconcile CEN-29 >/dev/null 2>&1; then
    test_fail 'merged PR with an unreviewed head must fail closed'
  fi
  assert_eq 'merged-review-mismatch' "$(jq -r '.status' "$state_file")" 'merged head mismatch state'
  assert_failure 'merged head mismatch must not mark Done' rg -q -- 'state-done' "$FAKE_CURL_LOG"
  rm -rf "$test_root"
}

run_merged_linear_done_rejection_test() {
  local test_root seed state_file state_before
  test_root="$(mktemp -d)"
  seed="$(dayflow_create_test_repo "$test_root" "$SOURCE_ROOT")"
  dayflow_export_fake_environment "$test_root" "$SOURCE_ROOT" "$seed"
  dayflow_prepare_notification_fixture
  export FAKE_CODEX_MODE=success FAKE_REVIEW_MODE=clean
  "$SOURCE_ROOT/scripts/dayflow_runner.sh" run CEN-29 >/dev/null
  state_file="$DAYFLOW_STATE_ROOT/CEN-29.json"
  state_before="$(<"$state_file")"
  : >"$FAKE_CURL_LOG"
  export FAKE_GH_PR_STATE=MERGED FAKE_LINEAR_FAIL_STATE=state-done

  if "$SOURCE_ROOT/scripts/dayflow_runner.sh" reconcile CEN-29 >/dev/null 2>&1; then
    test_fail 'Linear Done rejection must fail merged reconciliation'
  fi
  assert_file_contains "$FAKE_CURL_LOG" 'state-done' 'Linear Done transition was attempted'
  assert_eq "$state_before" "$(<"$state_file")" 'Linear Done rejection preserves pre-Done local state'
  assert_failure 'Linear Done rejection must not send Done webhook' rg -q -- 'discord.test/webhook' "$FAKE_CURL_LOG"
  rm -rf "$test_root"
}

run_cross_issue_merge_ready_store_lock_test() {
  local test_root seed first_rc=0 second_rc=0 merge_ready_count
  test_root="$(mktemp -d)"
  seed="$(dayflow_create_test_repo "$test_root" "$SOURCE_ROOT")"
  dayflow_export_fake_environment "$test_root" "$SOURCE_ROOT" "$seed"
  dayflow_prepare_notification_fixture
  mkdir -p "$DAYFLOW_STATE_ROOT"
  printf '%s\n' '{}' >"$DAYFLOW_MERGE_READY_STORE"
  printf '%s\n' '{"issue":"CEN-29","issue_id":"issue-29","branch":"feature/tasks-29-first","reviewed_head_sha":"shared-reviewed-head"}' >"$DAYFLOW_STATE_ROOT/CEN-29.json"
  printf '%s\n' '{"issue":"CEN-30","issue_id":"issue-30","branch":"feature/tasks-30-second","reviewed_head_sha":"shared-reviewed-head"}' >"$DAYFLOW_STATE_ROOT/CEN-30.json"
  export FAKE_GH_HEAD_SHA_OVERRIDE=shared-reviewed-head FAKE_WEBHOOK_DELAY_SECONDS=0.5
  : >"$FAKE_GH_READY_FILE"
  : >"$FAKE_CURL_LOG"

  "$SOURCE_ROOT/scripts/dayflow_runner.sh" reconcile CEN-29 >/dev/null &
  first_pid=$!
  "$SOURCE_ROOT/scripts/dayflow_runner.sh" reconcile CEN-30 >/dev/null &
  second_pid=$!
  wait "$first_pid" || first_rc=$?
  wait "$second_pid" || second_rc=$?
  assert_eq '0' "$first_rc" 'first issue reconcile succeeds'
  assert_eq '0' "$second_rc" 'second issue reconcile succeeds'
  assert_eq 'shared-reviewed-head' "$(jq -r '.["CEN-29"].head_sha' "$DAYFLOW_MERGE_READY_STORE")" 'first issue dedupe record preserved'
  assert_eq 'shared-reviewed-head' "$(jq -r '.["CEN-30"].head_sha' "$DAYFLOW_MERGE_READY_STORE")" 'second issue dedupe record preserved'
  merge_ready_count="$(rg -c 'merge-ready' "$FAKE_CURL_LOG")"
  assert_eq '2' "$merge_ready_count" 'both issue webhooks delivered exactly once'
  rm -rf "$test_root"
}

run_model_rejection_test() {
  local test_root seed
  test_root="$(mktemp -d)"
  seed="$(dayflow_create_test_repo "$test_root" "$SOURCE_ROOT")"
  dayflow_export_fake_environment "$test_root" "$SOURCE_ROOT" "$seed"
  dayflow_prepare_notification_fixture
  export FAKE_CODEX_MODE=model-rejected
  export FAKE_REVIEW_MODE=clean

  if "$SOURCE_ROOT/scripts/dayflow_runner.sh" run CEN-29 >/dev/null 2>&1; then
    test_fail 'model rejection should fail the run'
  fi
  assert_eq 'blocked' "$(jq -r '.status' "$DAYFLOW_STATE_ROOT/CEN-29.json")" 'model rejection local state'
  assert_file_contains "$DAYFLOW_STATE_ROOT/CEN-29.json" 'model rejected' 'model rejection reason'
  assert_file_contains "$FAKE_CURL_LOG" 'state-blocked' 'Linear Blocked mutation'
  assert_file_contains "$FAKE_CURL_LOG" 'discord.test/webhook' 'Blocked webhook'
  rm -rf "$test_root"
}

run_review_remediation_test
run_model_rejection_test
run_delivery_integrity_test
run_review_execution_failure_draft_test
run_start_transition_failure_test
run_review_visibility_test
run_final_blocker_visibility_test
run_ci_timeout_test
run_webhook_retry_and_lock_test
run_merged_base_integrity_test
run_merged_reviewed_head_integrity_test
run_merged_linear_done_rejection_test
run_cross_issue_merge_ready_store_lock_test
finish_tests 'dayflow_runner_integration_test'
