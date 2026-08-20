#!/usr/bin/env bash
set -euo pipefail

TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SOURCE_ROOT="$(cd "$TEST_DIR/../.." && pwd)"
# shellcheck source=scripts/tests/testlib.sh
source "$TEST_DIR/testlib.sh"

TEST_TMP="$(mktemp -d)"
trap 'rm -rf "$TEST_TMP"' EXIT

export DAYFLOW_CURL_BIN="$TEST_DIR/fakes/github_merge_ready_curl"
export DAYFLOW_GITHUB_API_URL='https://github.test'
export DAYFLOW_DISCORD_WEBHOOK_URL='https://discord.test/merge-ready'
export GITHUB_TOKEN='test-github-token'
export GITHUB_REPOSITORY='CentLee/DayFlow'
export FAKE_READY_CURL_LOG="$TEST_TMP/curl.log"
export FAKE_READY_COMMENTS="$TEST_TMP/comments.json"
export FAKE_READY_COMMENT_CREATE_COUNT="$TEST_TMP/comment-creates"
export FAKE_READY_COMMENT_UPDATE_COUNT="$TEST_TMP/comment-updates"
export FAKE_READY_DISCORD_COUNT="$TEST_TMP/discord-count"
event="$TEST_DIR/fixtures/completed-task-ci.json"

count() {
  [[ -f "$1" ]] && cat "$1" || printf '0\n'
}

reset_fakes() {
  rm -f "$FAKE_READY_CURL_LOG" "$FAKE_READY_COMMENTS" "$FAKE_READY_COMMENT_CREATE_COUNT" \
    "$FAKE_READY_COMMENT_UPDATE_COUNT" "$FAKE_READY_DISCORD_COUNT"
  unset FAKE_READY_CI_STATE FAKE_READY_PR_VARIANT FAKE_READY_DISCORD_REJECT
}

run_event() {
  GITHUB_EVENT_PATH="$event" "$SOURCE_ROOT/scripts/github_merge_ready_notify.sh"
}

reset_fakes
run_event >/dev/null
assert_eq '1' "$(count "$FAKE_READY_DISCORD_COUNT")" 'successful CI sends one Discord notification'
assert_eq '1' "$(count "$FAKE_READY_COMMENT_CREATE_COUNT")" 'successful CI creates a delivery claim'
assert_eq '1' "$(count "$FAKE_READY_COMMENT_UPDATE_COUNT")" 'successful CI marks the claim delivered'
assert_file_contains "$FAKE_READY_COMMENTS" 'state=delivered' 'delivery marker is durable'

run_event >/dev/null
assert_eq '1' "$(count "$FAKE_READY_DISCORD_COUNT")" 'same head does not repeat Discord delivery'
assert_eq '1' "$(count "$FAKE_READY_COMMENT_CREATE_COUNT")" 'same head does not create a duplicate claim'

for ci_state in waiting failed; do
  reset_fakes
  export FAKE_READY_CI_STATE="$ci_state"
  run_event >/dev/null
  assert_eq '0' "$(count "$FAKE_READY_DISCORD_COUNT")" "${ci_state} CI does not notify Discord"
  assert_eq '0' "$(count "$FAKE_READY_COMMENT_CREATE_COUNT")" "${ci_state} CI does not claim delivery"
done

reset_fakes
export FAKE_READY_PR_VARIANT='draft'
run_event >/dev/null
assert_eq '0' "$(count "$FAKE_READY_DISCORD_COUNT")" 'draft PR does not notify Discord'

reset_fakes
export FAKE_READY_DISCORD_REJECT=true
if run_event >"$TEST_TMP/rejected.log" 2>&1; then
  test_fail 'Discord rejection must fail for a later retry'
fi
assert_eq '1' "$(count "$FAKE_READY_DISCORD_COUNT")" 'Discord rejection attempts delivery once'
assert_eq '1' "$(count "$FAKE_READY_COMMENT_UPDATE_COUNT")" 'Discord rejection releases the claim'
assert_file_contains "$FAKE_READY_COMMENTS" 'state=retryable' 'Discord rejection leaves a retryable marker'

assert_file_contains "$SOURCE_ROOT/.github/workflows/merge-ready-notify.yml" 'workflow_run:' 'workflow reacts to CI completion'
assert_file_contains "$SOURCE_ROOT/.github/workflows/merge-ready-notify.yml" 'DAYFLOW_DISCORD_WEBHOOK_URL:.*secrets.DAYFLOW_DISCORD_WEBHOOK_URL' 'workflow wires Discord secret'
assert_file_contains "$SOURCE_ROOT/.github/workflows/merge-ready-notify.yml" 'issues: write' 'workflow can record durable PR-comment state'
assert_file_contains "$SOURCE_ROOT/.github/workflows/merge-ready-notify.yml" 'cancel-in-progress: false' 'workflow serializes same-head notifications'

finish_tests 'github_merge_ready_notify_test'
