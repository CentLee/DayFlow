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

  "$SOURCE_ROOT/scripts/dayflow_runner.sh" run CEN-29 >/dev/null
  assert_eq 'merge-ready' "$(jq -r '.status' "$DAYFLOW_STATE_ROOT/CEN-29.json")" 'remediation path status'
  assert_eq '2' "$(<"$FAKE_CODEX_REVIEW_COUNT_FILE")" 'review rerun count'
  assert_file_contains "$FAKE_CODEX_LOG" 'resume' 'same primary session was resumed'
  assert_file_contains "$FAKE_GH_LOG" 'comment' 'review findings were posted'
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
finish_tests 'dayflow_runner_integration_test'
