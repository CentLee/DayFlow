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
export FAKE_LINEAR_REQUEST_COUNT="$TEST_TMP/linear-requests"
export FAKE_LINEAR_MUTATION_COUNT="$TEST_TMP/linear-mutations"
export FAKE_GITHUB_MARKER_FILE="$TEST_TMP/github-marker"
export FAKE_GITHUB_COMMENT_COUNT="$TEST_TMP/github-comments"
export FAKE_GITHUB_COMMENT_UPDATE_COUNT="$TEST_TMP/github-comment-updates"
export FAKE_DISCORD_COUNT="$TEST_TMP/discord-count"
export FAKE_DISCORD_FAILURES_FILE="$TEST_TMP/discord-failures"
valid_event="$TEST_DIR/fixtures/merged-task-pr.json"

reset_fakes() {
  rm -f "$FAKE_MERGE_CURL_LOG" "$FAKE_LINEAR_STATE_FILE" "$FAKE_LINEAR_REQUEST_COUNT" \
    "$FAKE_LINEAR_MUTATION_COUNT" "$FAKE_GITHUB_MARKER_FILE" "$FAKE_GITHUB_COMMENT_COUNT" \
    "$FAKE_GITHUB_COMMENT_UPDATE_COUNT" "$FAKE_DISCORD_COUNT" "$FAKE_DISCORD_FAILURES_FILE"
  unset FAKE_LINEAR_MUTATION_FAIL FAKE_LINEAR_MALFORMED_QUERY FAKE_LINEAR_DESCRIPTION FAKE_GITHUB_CLAIM_CREATE_FAIL FAKE_GITHUB_LIST_FAIL \
    FAKE_GITHUB_DELIVERED_UPDATE_FAIL FAKE_GITHUB_CONCURRENT_CLAIM FAKE_DISCORD_TRANSPORT_FAIL
}

counter_value() {
  local file="$1"
  [[ -f "$file" ]] && printf '%s\n' "$(<"$file")" || printf '%s\n' '0'
}

run_event() {
  GITHUB_EVENT_PATH="$1" "$SOURCE_ROOT/scripts/github_merge_reconcile.sh"
}

marker_count() {
  local state="$1"
  if [[ ! -f "$FAKE_GITHUB_MARKER_FILE" ]]; then
    printf '%s\n' '0'
    return
  fi
  jq -r --arg marker "state=${state}" \
    '[.[] | select(((.body // "") | type) == "string" and (.body | contains($marker)))] | length' \
    "$FAKE_GITHUB_MARKER_FILE"
}

assert_no_external_calls() {
  local label="$1"
  assert_eq '0' "$(counter_value "$FAKE_LINEAR_REQUEST_COUNT")" "${label} does not call Linear"
  assert_eq '0' "$(counter_value "$FAKE_DISCORD_COUNT")" "${label} does not call Discord"
  assert_eq '0' "$(counter_value "$FAKE_GITHUB_COMMENT_COUNT")" "${label} does not create a claim"
  assert_eq '0' "$(counter_value "$FAKE_GITHUB_COMMENT_UPDATE_COUNT")" "${label} does not update a claim"
}

reset_fakes
run_event "$valid_event" >/dev/null
assert_eq 'Done' "$(<"$FAKE_LINEAR_STATE_FILE")" 'eligible merge transitions Linear to Done'
assert_eq '1' "$(counter_value "$FAKE_LINEAR_MUTATION_COUNT")" 'eligible merge mutates Linear once'
assert_eq '1' "$(counter_value "$FAKE_DISCORD_COUNT")" 'eligible merge sends one completion notification'
assert_eq '1' "$(counter_value "$FAKE_GITHUB_COMMENT_COUNT")" 'eligible merge creates one claim comment'
assert_eq '1' "$(counter_value "$FAKE_GITHUB_COMMENT_UPDATE_COUNT")" 'eligible merge patches its claim once'
assert_eq '1' "$(marker_count delivered)" 'eligible merge records a v2 delivered marker'
assert_eq '0' "$(marker_count claimed)" 'eligible merge leaves no unresolved claim'

reset_fakes
integration_event="$TEST_TMP/integration-base.json"
jq '.pull_request.base.ref = "integration/private-two-person-cutover"' "$valid_event" >"$integration_event"
export FAKE_LINEAR_DESCRIPTION='Integration Base: integration/private-two-person-cutover'
run_event "$integration_event" >/dev/null
assert_eq 'Done' "$(<"$FAKE_LINEAR_STATE_FILE")" 'eligible integration-base merge transitions Linear to Done'
assert_eq '1' "$(counter_value "$FAKE_DISCORD_COUNT")" 'eligible integration-base merge sends one completion notification'

reset_fakes
export FAKE_LINEAR_DESCRIPTION='Integration Base: integration/private-two-person-cutover'
if run_event "$valid_event" >"$TEST_TMP/base-mismatch.log" 2>&1; then
  test_fail 'develop merge with integration metadata must fail closed'
fi
assert_eq '0' "$(counter_value "$FAKE_LINEAR_MUTATION_COUNT")" 'base mismatch does not mutate Linear'
assert_eq '0' "$(counter_value "$FAKE_DISCORD_COUNT")" 'base mismatch does not call Discord'
assert_eq '1' "$(marker_count retryable)" 'base mismatch releases its claim for retry'

reset_fakes
export FAKE_LINEAR_DESCRIPTION='Integration Base:'
if run_event "$integration_event" >"$TEST_TMP/empty-base.log" 2>&1; then
  test_fail 'empty Integration Base must fail closed'
fi
assert_eq '0' "$(counter_value "$FAKE_LINEAR_MUTATION_COUNT")" 'empty Integration Base does not mutate Linear'
assert_eq '0' "$(counter_value "$FAKE_DISCORD_COUNT")" 'empty Integration Base does not call Discord'
assert_eq '1' "$(marker_count retryable)" 'empty Integration Base releases its claim for retry'

reset_fakes
export FAKE_LINEAR_DESCRIPTION=$'Integration Base: integration/private-two-person-cutover\nIntegration Base: integration/private-two-person-cutover'
if run_event "$integration_event" >"$TEST_TMP/duplicate-base.log" 2>&1; then
  test_fail 'duplicate Integration Base must fail closed'
fi
assert_eq '0' "$(counter_value "$FAKE_LINEAR_MUTATION_COUNT")" 'duplicate Integration Base does not mutate Linear'
assert_eq '0' "$(counter_value "$FAKE_DISCORD_COUNT")" 'duplicate Integration Base does not call Discord'
assert_eq '1' "$(marker_count retryable)" 'duplicate Integration Base releases its claim for retry'

reset_fakes
final_cutover_event="$TEST_TMP/final-cutover.json"
jq '.pull_request.head.ref = "integration/private-two-person-cutover"' "$valid_event" >"$final_cutover_event"
run_event "$final_cutover_event" >/dev/null
assert_no_external_calls 'final integration-to-develop cutover'

run_event "$valid_event" >/dev/null
assert_eq '1' "$(counter_value "$FAKE_LINEAR_MUTATION_COUNT")" 'replayed merge does not repeat Done mutation'
assert_eq '1' "$(counter_value "$FAKE_DISCORD_COUNT")" 'replayed merge does not repeat Discord delivery'
assert_eq '1' "$(counter_value "$FAKE_GITHUB_COMMENT_COUNT")" 'replayed merge does not create another claim'
assert_eq '1' "$(counter_value "$FAKE_GITHUB_COMMENT_UPDATE_COUNT")" 'replayed merge does not patch a comment'

reset_fakes
export FAKE_GITHUB_CLAIM_CREATE_FAIL=true
if run_event "$valid_event" >"$TEST_TMP/claim-create-failure.log" 2>&1; then
  test_fail 'claim creation failure must fail closed'
fi
assert_eq '0' "$(counter_value "$FAKE_LINEAR_REQUEST_COUNT")" 'claim creation failure happens before any Linear call'
assert_eq '0' "$(counter_value "$FAKE_LINEAR_MUTATION_COUNT")" 'claim creation failure does not mutate Linear'
assert_eq '0' "$(counter_value "$FAKE_DISCORD_COUNT")" 'claim creation failure does not call Discord'
assert_eq '0' "$(counter_value "$FAKE_GITHUB_COMMENT_COUNT")" 'failed claim creation records no comment'
assert_file_contains "$TEST_TMP/claim-create-failure.log" 'Linear and Discord were not mutated' 'claim failure explains mutation ordering'

reset_fakes
printf '%s\n' '1' >"$FAKE_DISCORD_FAILURES_FILE"
if run_event "$valid_event" >"$TEST_TMP/discord-rejection.log" 2>&1; then
  test_fail 'definite Discord rejection must fail the workflow for retry'
fi
assert_eq '1' "$(counter_value "$FAKE_LINEAR_MUTATION_COUNT")" 'Discord failure preserves completed Linear transition'
assert_eq '1' "$(counter_value "$FAKE_DISCORD_COUNT")" 'definite rejection attempts Discord once'
assert_eq '1' "$(counter_value "$FAKE_GITHUB_COMMENT_COUNT")" 'definite rejection creates one claim'
assert_eq '1' "$(counter_value "$FAKE_GITHUB_COMMENT_UPDATE_COUNT")" 'definite rejection releases its claim'
assert_eq '1' "$(marker_count retryable)" 'definite rejection marks its claim retryable'
assert_eq '0' "$(marker_count claimed)" 'definite rejection leaves no unresolved claim'
run_event "$valid_event" >/dev/null
assert_eq '1' "$(counter_value "$FAKE_LINEAR_MUTATION_COUNT")" 'Discord retry does not repeat Done mutation'
assert_eq '2' "$(counter_value "$FAKE_DISCORD_COUNT")" 'rerun sends Discord exactly once after definite rejection'
assert_eq '2' "$(counter_value "$FAKE_GITHUB_COMMENT_COUNT")" 'rerun creates exactly one new claim'
assert_eq '2' "$(counter_value "$FAKE_GITHUB_COMMENT_UPDATE_COUNT")" 'rerun patches the new claim delivered'
assert_eq '1' "$(marker_count delivered)" 'successful rejection retry records delivery'

reset_fakes
export FAKE_DISCORD_TRANSPORT_FAIL=true
if run_event "$valid_event" >"$TEST_TMP/transport-failure.log" 2>&1; then
  test_fail 'ambiguous Discord transport failure must fail closed'
fi
assert_eq '1' "$(counter_value "$FAKE_LINEAR_MUTATION_COUNT")" 'transport failure preserves Linear Done convergence'
assert_eq '1' "$(counter_value "$FAKE_DISCORD_COUNT")" 'transport failure makes one ambiguous Discord attempt'
assert_eq '1' "$(counter_value "$FAKE_GITHUB_COMMENT_COUNT")" 'transport failure keeps its claim comment'
assert_eq '0' "$(counter_value "$FAKE_GITHUB_COMMENT_UPDATE_COUNT")" 'transport failure does not release its claim'
assert_eq '1' "$(marker_count claimed)" 'transport failure leaves the claim unresolved'
linear_requests_before="$(counter_value "$FAKE_LINEAR_REQUEST_COUNT")"
unset FAKE_DISCORD_TRANSPORT_FAIL
if run_event "$valid_event" >"$TEST_TMP/transport-rerun.log" 2>&1; then
  test_fail 'unresolved transport claim must fail replay closed'
fi
assert_eq '1' "$(counter_value "$FAKE_DISCORD_COUNT")" 'transport replay sends zero additional Discord messages'
assert_eq "$linear_requests_before" "$(counter_value "$FAKE_LINEAR_REQUEST_COUNT")" 'transport replay stops before Linear'
assert_eq '1' "$(counter_value "$FAKE_GITHUB_COMMENT_COUNT")" 'transport replay creates no additional claim'
assert_file_contains "$TEST_TMP/transport-rerun.log" 'operator reconciliation is required' 'transport replay explains operator reconciliation'

reset_fakes
export FAKE_GITHUB_DELIVERED_UPDATE_FAIL=true
if run_event "$valid_event" >"$TEST_TMP/delivered-patch-failure.log" 2>&1; then
  test_fail 'delivered marker PATCH failure must fail closed'
fi
assert_eq '1' "$(counter_value "$FAKE_DISCORD_COUNT")" 'PATCH failure occurs after one accepted Discord delivery'
assert_eq '1' "$(counter_value "$FAKE_GITHUB_COMMENT_UPDATE_COUNT")" 'PATCH failure attempts one delivered update'
assert_eq '1' "$(marker_count claimed)" 'PATCH failure preserves the unresolved claim'
unset FAKE_GITHUB_DELIVERED_UPDATE_FAIL
if run_event "$valid_event" >"$TEST_TMP/delivered-patch-rerun.log" 2>&1; then
  test_fail 'unresolved post-delivery claim must fail replay closed'
fi
assert_eq '1' "$(counter_value "$FAKE_DISCORD_COUNT")" 'PATCH failure replay sends zero additional Discord messages'
assert_eq '1' "$(counter_value "$FAKE_GITHUB_COMMENT_UPDATE_COUNT")" 'PATCH failure replay does not patch again'
assert_eq '1' "$(counter_value "$FAKE_GITHUB_COMMENT_COUNT")" 'PATCH failure replay creates no additional claim'
assert_file_contains "$TEST_TMP/delivered-patch-rerun.log" 'operator reconciliation is required' 'PATCH failure replay explains operator reconciliation'

reset_fakes
printf '%s\n' '[{"id":501,"body":"<!-- dayflow-merge-reconcile:v2 issue=CEN-30 pr=42 state=delivered -->","user":{"login":"github-actions[bot]"}}]' >"$FAKE_GITHUB_MARKER_FILE"
run_event "$valid_event" >/dev/null
assert_no_external_calls 'delivered replay'

reset_fakes
export FAKE_GITHUB_CONCURRENT_CLAIM=true
run_event "$valid_event" >/dev/null
assert_eq '0' "$(counter_value "$FAKE_LINEAR_REQUEST_COUNT")" 'losing concurrent claim stops before Linear'
assert_eq '0' "$(counter_value "$FAKE_DISCORD_COUNT")" 'losing concurrent claim does not call Discord'
assert_eq '1' "$(counter_value "$FAKE_GITHUB_COMMENT_COUNT")" 'losing concurrent run creates its own claim once'
assert_eq '1' "$(counter_value "$FAKE_GITHUB_COMMENT_UPDATE_COUNT")" 'losing concurrent run supersedes its own claim'
assert_eq '1' "$(marker_count claimed)" 'winning concurrent claim remains unresolved'
assert_eq '1' "$(marker_count superseded)" 'losing concurrent claim is marked superseded'

for variant in wrong-action action-type repository-mismatch repository-malformed repository-type \
  pr-string pr-object merged-string pull-request-type; do
  reset_fakes
  event="$TEST_TMP/${variant}.json"
  case "$variant" in
    wrong-action) jq '.action = "opened"' "$valid_event" >"$event" ;;
    action-type) jq '.action = 7' "$valid_event" >"$event" ;;
    repository-mismatch) jq '.repository.full_name = "Other/DayFlow" | .pull_request.head.repo.full_name = "Other/DayFlow"' "$valid_event" >"$event" ;;
    repository-malformed) jq '.repository.full_name = "bad repo" | .pull_request.head.repo.full_name = "bad repo"' "$valid_event" >"$event" ;;
    repository-type) jq '.repository.full_name = 42' "$valid_event" >"$event" ;;
    pr-string) jq '.pull_request.number = "42"' "$valid_event" >"$event" ;;
    pr-object) jq '.pull_request.number = {}' "$valid_event" >"$event" ;;
    merged-string) jq '.pull_request.merged = "true"' "$valid_event" >"$event" ;;
    pull-request-type) jq '.pull_request = "closed"' "$valid_event" >"$event" ;;
  esac
  run_event "$event" >/dev/null
  assert_no_external_calls "${variant} event"
done

reset_fakes
non_object_event="$TEST_TMP/non-object.json"
printf '%s\n' '[]' >"$non_object_event"
if run_event "$non_object_event" >"$TEST_TMP/non-object.log" 2>&1; then
  test_fail 'non-object event must fail safely'
fi
assert_no_external_calls 'non-object event'

reset_fakes
export FAKE_LINEAR_MUTATION_FAIL=true
printf '%s\n' 'In Review' >"$FAKE_LINEAR_STATE_FILE"
if run_event "$valid_event" >"$TEST_TMP/linear-failure.log" 2>&1; then
  test_fail 'rejected Linear Done mutation must fail closed'
fi
assert_eq 'In Review' "$(<"$FAKE_LINEAR_STATE_FILE")" 'rejected Linear mutation preserves prior state'
assert_eq '0' "$(counter_value "$FAKE_DISCORD_COUNT")" 'rejected Linear mutation does not notify Discord'
assert_eq '1' "$(marker_count retryable)" 'rejected Linear mutation releases its pre-Discord claim'
assert_eq '0' "$(marker_count claimed)" 'rejected Linear mutation leaves no unresolved claim'

reset_fakes
export FAKE_LINEAR_MALFORMED_QUERY=true
if run_event "$valid_event" >"$TEST_TMP/linear-malformed-query.log" 2>&1; then
  test_fail 'malformed Linear query response must fail through the retryable claim path'
fi
assert_eq '0' "$(counter_value "$FAKE_LINEAR_MUTATION_COUNT")" 'malformed Linear query response does not mutate Linear'
assert_eq '0' "$(counter_value "$FAKE_DISCORD_COUNT")" 'malformed Linear query response does not call Discord'
assert_eq '1' "$(marker_count retryable)" 'malformed Linear query response marks the claim retryable'
assert_eq '0' "$(marker_count claimed)" 'malformed Linear query response leaves no claimed marker'
unset FAKE_LINEAR_MALFORMED_QUERY
run_event "$valid_event" >/dev/null
assert_eq '1' "$(counter_value "$FAKE_LINEAR_MUTATION_COUNT")" 'malformed Linear query rerun converges Linear once'
assert_eq '1' "$(counter_value "$FAKE_DISCORD_COUNT")" 'malformed Linear query rerun sends Discord once'
assert_eq '1' "$(marker_count delivered)" 'malformed Linear query rerun records delivery'

reset_fakes
export FAKE_GITHUB_LIST_FAIL=true
if run_event "$valid_event" >"$TEST_TMP/list-failure.log" 2>&1; then
  test_fail 'unavailable dedupe state must fail closed'
fi
assert_no_external_calls 'dedupe read failure'

reset_fakes
runtime_marker="$TEST_TMP/local-runtime/dirty-worktree-marker"
mkdir -p "$(dirname "$runtime_marker")"
printf '%s\n' 'preserve me' >"$runtime_marker"
DAYFLOW_RUNTIME_DIR="$TEST_TMP/local-runtime" run_event "$valid_event" >/dev/null
assert_eq 'preserve me' "$(<"$runtime_marker")" 'remote branch deletion path never touches local runtime state'
assert_failure 'merge reconciler never calls a remote branch API' rg -q '/git/refs/' "$FAKE_MERGE_CURL_LOG"

assert_file_contains "$SOURCE_ROOT/.github/workflows/merge-lifecycle.yml" 'types: \[closed\]' 'workflow listens for closed PR events'
assert_file_contains "$SOURCE_ROOT/.github/workflows/merge-lifecycle.yml" 'branches: \[develop, integration/private-two-person-cutover\]' 'workflow filters to both allowed base branches'
assert_file_contains "$SOURCE_ROOT/.github/workflows/merge-lifecycle.yml" 'if: github.event.pull_request.merged == true' 'workflow skips unmerged PRs before secret use'
assert_file_contains "$SOURCE_ROOT/.github/workflows/merge-lifecycle.yml" 'cancel-in-progress: false' 'workflow serializes retries without cancellation'
assert_file_contains "$SOURCE_ROOT/.github/workflows/merge-lifecycle.yml" 'LINEAR_API_KEY:.*secrets.LINEAR_API_KEY' 'workflow wires Linear secret'
assert_file_contains "$SOURCE_ROOT/.github/workflows/merge-lifecycle.yml" 'DAYFLOW_DISCORD_WEBHOOK_URL:.*secrets.DAYFLOW_DISCORD_WEBHOOK_URL' 'workflow wires Discord secret'

finish_tests 'github_merge_reconcile_test'
