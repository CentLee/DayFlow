#!/usr/bin/env bash
set -euo pipefail

TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SOURCE_ROOT="$(cd "$TEST_DIR/../.." && pwd)"
# shellcheck source=scripts/tests/testlib.sh
source "$TEST_DIR/testlib.sh"
# shellcheck source=scripts/tests/system_test_helpers.sh
source "$TEST_DIR/system_test_helpers.sh"

TEST_TMP="$(mktemp -d)"
trap 'rm -rf "$TEST_TMP"' EXIT
seed="$(dayflow_create_test_repo "$TEST_TMP" "$SOURCE_ROOT")"
dayflow_export_fake_environment "$TEST_TMP" "$SOURCE_ROOT" "$seed"
dayflow_prepare_notification_fixture
export FAKE_CODEX_MODE=success
export FAKE_REVIEW_MODE=clean

"$SOURCE_ROOT/scripts/dayflow_runner.sh" run CEN-29 >/dev/null

state_file="$DAYFLOW_STATE_ROOT/CEN-29.json"
assert_eq 'merge-ready' "$(jq -r '.status' "$state_file")" 'system lifecycle result'
assert_eq 'fake-primary-session' "$(jq -r '.session_id' "$state_file")" 'primary session persistence'
assert_eq 'gpt-5.6-sol' "$(jq -r '.model' "$state_file")" 'model persistence'
assert_success 'remote issue branch exists' git -C "$seed" ls-remote --exit-code --heads origin refs/heads/feature/tasks-29-replace-symphony-with-dayflow-local-runner
assert_file_contains "$FAKE_GH_LOG" 'ready' 'PR was marked ready'
assert_file_contains "$FAKE_CURL_LOG" 'state-in-progress' 'Linear start transition'
assert_file_contains "$FAKE_CURL_LOG" 'state-in-review' 'Linear review transition'

before_count="$(rg -c 'discord.test/webhook' "$FAKE_CURL_LOG")"
"$SOURCE_ROOT/scripts/dayflow_runner.sh" reconcile CEN-29 >/dev/null
after_count="$(rg -c 'discord.test/webhook' "$FAKE_CURL_LOG")"
assert_eq "$before_count" "$after_count" 'merge-ready webhook deduplication'

finish_tests 'dayflow_runner_system_test'
