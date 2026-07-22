#!/usr/bin/env bash
set -euo pipefail

TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SOURCE_ROOT="$(cd "$TEST_DIR/../.." && pwd)"
# shellcheck source=scripts/tests/testlib.sh
source "$TEST_DIR/testlib.sh"

TEST_TMP="$(mktemp -d)"
trap 'rm -rf "$TEST_TMP"' EXIT

export DAYFLOW_CURL_BIN="$TEST_DIR/fakes/github_merge_curl"
export DAYFLOW_LINEAR_API_URL='https://linear.test/graphql'
export DAYFLOW_GITHUB_API_URL='https://github.test'
export DAYFLOW_DISCORD_WEBHOOK_URL='https://discord.test/completion'
export LINEAR_API_KEY='test-linear-key'
export GITHUB_TOKEN='test-github-token'
export GITHUB_REPOSITORY='CentLee/DayFlow'
export FAKE_MERGE_CURL_LOG="$TEST_TMP/curl.log"
export FAKE_LINEAR_STATE_FILE="$TEST_TMP/linear-state"
export FAKE_LINEAR_MUTATION_COUNT="$TEST_TMP/linear-mutations"
export FAKE_GITHUB_MARKER_FILE="$TEST_TMP/github-marker"
export FAKE_GITHUB_COMMENT_COUNT="$TEST_TMP/github-comments"
export FAKE_DISCORD_COUNT="$TEST_TMP/discord-count"
export FAKE_DISCORD_FAILURES_FILE="$TEST_TMP/discord-failures"
valid_event="$TEST_DIR/fixtures/merged-task-pr.json"

reset_fakes() {
  rm -f "$FAKE_MERGE_CURL_LOG" "$FAKE_LINEAR_STATE_FILE" "$FAKE_LINEAR_MUTATION_COUNT" \
    "$FAKE_GITHUB_MARKER_FILE" "$FAKE_GITHUB_COMMENT_COUNT" "$FAKE_DISCORD_COUNT" \
    "$FAKE_DISCORD_FAILURES_FILE"
  unset FAKE_LINEAR_MUTATION_FAIL FAKE_GITHUB_COMMENT_FAIL FAKE_GITHUB_LIST_FAIL
}

counter_value() {
  local file="$1"
  [[ -f "$file" ]] && printf '%s\n' "$(<"$file")" || printf '%s\n' '0'
}

run_event() {
  GITHUB_EVENT_PATH="$1" "$SOURCE_ROOT/scripts/github_merge_reconcile.sh" >/dev/null
}

reset_fakes
run_event "$valid_event"
assert_eq 'Done' "$(<"$FAKE_LINEAR_STATE_FILE")" 'eligible merge transitions Linear to Done'
assert_eq '1' "$(counter_value "$FAKE_LINEAR_MUTATION_COUNT")" 'eligible merge mutates Linear once'
assert_eq '1' "$(counter_value "$FAKE_DISCORD_COUNT")" 'eligible merge sends one completion notification'
assert_eq '1' "$(counter_value "$FAKE_GITHUB_COMMENT_COUNT")" 'eligible merge records one dedupe marker'
assert_file_contains "$FAKE_GITHUB_MARKER_FILE" 'dayflow-merge-reconcile:v1 issue=CEN-30 pr=42 discord=delivered' 'dedupe marker identity'

run_event "$valid_event"
assert_eq '1' "$(counter_value "$FAKE_LINEAR_MUTATION_COUNT")" 'replayed merge does not repeat Done mutation'
assert_eq '1' "$(counter_value "$FAKE_DISCORD_COUNT")" 'replayed merge does not repeat Discord delivery'
assert_eq '1' "$(counter_value "$FAKE_GITHUB_COMMENT_COUNT")" 'replayed merge does not repeat marker write'

reset_fakes
printf '%s\n' '1' >"$FAKE_DISCORD_FAILURES_FILE"
if run_event "$valid_event" 2>/dev/null; then
  test_fail 'failed Discord delivery must fail the workflow for retry'
fi
assert_eq '1' "$(counter_value "$FAKE_LINEAR_MUTATION_COUNT")" 'Discord failure preserves completed Linear transition'
assert_eq '0' "$(counter_value "$FAKE_GITHUB_COMMENT_COUNT")" 'Discord failure does not record success marker'
run_event "$valid_event"
assert_eq '1' "$(counter_value "$FAKE_LINEAR_MUTATION_COUNT")" 'Discord retry does not repeat Done mutation'
assert_eq '2' "$(counter_value "$FAKE_DISCORD_COUNT")" 'Discord failure is retried once'
assert_eq '1' "$(counter_value "$FAKE_GITHUB_COMMENT_COUNT")" 'successful retry records dedupe marker'

for variant in unmerged wrong-base malformed-branch fork-head; do
  reset_fakes
  event="$TEST_TMP/${variant}.json"
  case "$variant" in
    unmerged) jq '.pull_request.merged = false' "$valid_event" >"$event" ;;
    wrong-base) jq '.pull_request.base.ref = "main"' "$valid_event" >"$event" ;;
    malformed-branch) jq '.pull_request.head.ref = "feature/tasks-xx-unsafe"' "$valid_event" >"$event" ;;
    fork-head) jq '.pull_request.head.repo.full_name = "someone/DayFlow"' "$valid_event" >"$event" ;;
  esac
  run_event "$event"
  assert_eq '0' "$(counter_value "$FAKE_LINEAR_MUTATION_COUNT")" "${variant} event does not mutate Linear"
  assert_eq '0' "$(counter_value "$FAKE_DISCORD_COUNT")" "${variant} event does not notify Discord"
  assert_eq '0' "$(counter_value "$FAKE_GITHUB_COMMENT_COUNT")" "${variant} event does not write GitHub"
done

reset_fakes
invalid_event="$TEST_TMP/invalid.json"
printf '%s\n' '{not-json' >"$invalid_event"
if run_event "$invalid_event" 2>/dev/null; then
  test_fail 'invalid JSON event must fail closed'
fi
assert_eq '0' "$(counter_value "$FAKE_LINEAR_MUTATION_COUNT")" 'invalid JSON event does not mutate Linear'
assert_eq '0' "$(counter_value "$FAKE_DISCORD_COUNT")" 'invalid JSON event does not notify Discord'

reset_fakes
export FAKE_LINEAR_MUTATION_FAIL=true
printf '%s\n' 'In Review' >"$FAKE_LINEAR_STATE_FILE"
if run_event "$valid_event" 2>/dev/null; then
  test_fail 'rejected Linear Done mutation must fail closed'
fi
assert_eq 'In Review' "$(<"$FAKE_LINEAR_STATE_FILE")" 'rejected Linear mutation preserves prior state'
assert_eq '0' "$(counter_value "$FAKE_DISCORD_COUNT")" 'rejected Linear mutation does not notify Discord'
assert_eq '0' "$(counter_value "$FAKE_GITHUB_COMMENT_COUNT")" 'rejected Linear mutation does not record delivery'

reset_fakes
export FAKE_GITHUB_LIST_FAIL=true
if run_event "$valid_event" 2>/dev/null; then
  test_fail 'unavailable dedupe state must fail closed'
fi
assert_eq '0' "$(counter_value "$FAKE_LINEAR_MUTATION_COUNT")" 'dedupe read failure happens before Linear mutation'
assert_eq '0' "$(counter_value "$FAKE_DISCORD_COUNT")" 'dedupe read failure does not notify Discord'

reset_fakes
printf '%s\n' '<!-- dayflow-merge-reconcile:v1 issue=CEN-30 pr=42 discord=delivered -->' >"$FAKE_GITHUB_MARKER_FILE"
run_event "$valid_event"
assert_eq '0' "$(counter_value "$FAKE_LINEAR_MUTATION_COUNT")" 'already processed merge does not mutate Linear'
assert_eq '0' "$(counter_value "$FAKE_DISCORD_COUNT")" 'already processed merge does not notify Discord'

reset_fakes
runtime_marker="$TEST_TMP/local-runtime/dirty-worktree-marker"
mkdir -p "$(dirname "$runtime_marker")"
printf '%s\n' 'preserve me' >"$runtime_marker"
DAYFLOW_RUNTIME_DIR="$TEST_TMP/local-runtime" run_event "$valid_event"
assert_eq 'preserve me' "$(<"$runtime_marker")" 'remote branch deletion path never touches local runtime state'
assert_failure 'merge reconciler never calls a remote branch API' rg -q '/git/refs/' "$FAKE_MERGE_CURL_LOG"

assert_file_contains "$SOURCE_ROOT/.github/workflows/merge-lifecycle.yml" 'types: \[closed\]' 'workflow listens for closed PR events'
assert_file_contains "$SOURCE_ROOT/.github/workflows/merge-lifecycle.yml" 'branches: \[develop\]' 'workflow filters to develop PRs'
assert_file_contains "$SOURCE_ROOT/.github/workflows/merge-lifecycle.yml" 'if: github.event.pull_request.merged == true' 'workflow skips unmerged PRs before secret use'
assert_file_contains "$SOURCE_ROOT/.github/workflows/merge-lifecycle.yml" 'cancel-in-progress: false' 'workflow serializes retries without cancellation'
assert_file_contains "$SOURCE_ROOT/.github/workflows/merge-lifecycle.yml" 'LINEAR_API_KEY:.*secrets.LINEAR_API_KEY' 'workflow wires Linear secret'
assert_file_contains "$SOURCE_ROOT/.github/workflows/merge-lifecycle.yml" 'DAYFLOW_DISCORD_WEBHOOK_URL:.*secrets.DAYFLOW_DISCORD_WEBHOOK_URL' 'workflow wires Discord secret'

finish_tests 'github_merge_reconcile_test'
