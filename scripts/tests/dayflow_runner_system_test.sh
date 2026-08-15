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
gh_delegate="$DAYFLOW_GH_BIN"
gh_wrapper="$TEST_TMP/gh-graphql-list-failure"
cat >"$gh_wrapper" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
if [[ "${1:-} ${2:-}" == 'pr list' ]]; then
  printf 'GH_CONFIG_DIR=%s :: %s\n' "${GH_CONFIG_DIR:-}" "$*" >>"${FAKE_GH_LOG:?}"
  exit 1
fi
if [[ "${1:-}" == 'api' && "$*" == *'repos/test/dayflow/pulls'* ]]; then
  printf 'GH_CONFIG_DIR=%s :: %s\n' "${GH_CONFIG_DIR:-}" "$*" >>"${FAKE_GH_LOG:?}"
  if [[ ! -f "${FAKE_GH_PR_CREATED_FILE:?}" ]]; then
    printf '%s\n' '[]'
    exit 0
  fi
  branch="${FAKE_PR_BRANCH:?}"
  head_sha="$(git -C "${FAKE_GIT_ROOT:?}" ls-remote --heads origin "refs/heads/$branch" | awk 'NR == 1 {print $1}')"
  draft=true
  [[ -f "${FAKE_GH_READY_FILE:?}" ]] && draft=false
  state="${FAKE_GH_PR_STATE:-OPEN}"
  rest_state=open
  merged_at=null
  if [[ "$state" == 'MERGED' ]]; then rest_state=closed; merged_at='"2026-08-15T00:00:00Z"'; fi
  jq -n --arg branch "$branch" --arg head "${FAKE_GH_HEAD_SHA_OVERRIDE:-$head_sha}" \
    --arg base "${FAKE_GH_BASE_BRANCH:-develop}" --arg merge "${FAKE_GH_MERGE_STATE:-clean}" \
    --arg body "$(<"${FAKE_GH_BODY_FILE:?}")" --arg state "$rest_state" --argjson merged_at "$merged_at" \
    --argjson draft "$draft" \
    '[{number:29,html_url:"https://github.test/pr/29",draft:$draft,state:$state,merged_at:$merged_at,head:{ref:$branch,sha:$head},base:{ref:$base},mergeable_state:$merge,body:$body}]'
  exit 0
fi
exec "${FAKE_GH_DELEGATE_BIN:?}" "$@"
EOF
chmod +x "$gh_wrapper"
export FAKE_GH_DELEGATE_BIN="$gh_delegate"
export DAYFLOW_GH_BIN="$gh_wrapper"
export FAKE_GH_PR_CREATED_FILE="$TEST_TMP/pr-created"
export FAKE_CODEX_MODE=success
export FAKE_REVIEW_MODE=clean
export FAKE_GH_PENDING_COUNT_FILE="$TEST_TMP/pending-checks"
printf '%s\n' '2' >"$FAKE_GH_PENDING_COUNT_FILE"

"$SOURCE_ROOT/scripts/dayflow_runner.sh" run CEN-29 >/dev/null

state_file="$DAYFLOW_STATE_ROOT/CEN-29.json"
assert_eq 'merge-ready' "$(jq -r '.status' "$state_file")" 'system lifecycle result'
assert_eq 'fake-primary-session' "$(jq -r '.session_id' "$state_file")" 'primary session persistence'
assert_eq 'gpt-5.6-sol' "$(jq -r '.model' "$state_file")" 'model persistence'
assert_eq "$(git -C "$DAYFLOW_WORKTREE_ROOT/CEN-29" rev-parse HEAD)" "$(jq -r '.reviewed_head_sha' "$state_file")" 'reviewed head persistence'
assert_success 'remote issue branch exists' git -C "$seed" ls-remote --exit-code --heads origin refs/heads/feature/tasks-29-replace-symphony-with-dayflow-local-runner
assert_file_contains "$FAKE_GH_LOG" 'ready' 'PR was marked ready'
assert_file_contains "$FAKE_CURL_LOG" 'state-in-progress' 'Linear start transition'
assert_file_contains "$FAKE_CURL_LOG" 'state-in-review' 'Linear review transition'
assert_file_contains "$FAKE_GH_COMMENTS_LOG" 'Outcome:.*passed' 'clean review result published'
status_pr_number="$("$SOURCE_ROOT/scripts/dayflow_runner.sh" status CEN-29 | jq -r '.pull_request.number')"
assert_eq '29' "$status_pr_number" 'status discovers valid PR through REST fallback'
assert_file_contains "$FAKE_GH_LOG" 'api -X GET repos/test/dayflow/pulls' 'system lifecycle used REST PR discovery fallback'
checks_count="$(rg -c 'pr checks' "$FAKE_GH_LOG")"
assert_success 'CI wait polled until green' test "$checks_count" -ge 3

before_count="$(rg -c 'discord.test/webhook' "$FAKE_CURL_LOG")"
"$SOURCE_ROOT/scripts/dayflow_runner.sh" reconcile CEN-29 >/dev/null
after_count="$(rg -c 'discord.test/webhook' "$FAKE_CURL_LOG")"
assert_eq "$before_count" "$after_count" 'merge-ready webhook deduplication'

printf '%s\n' '{}' >"$DAYFLOW_MERGE_READY_STORE"
: >"$FAKE_CURL_LOG"
export FAKE_GH_MERGE_STATE=DIRTY
"$SOURCE_ROOT/scripts/dayflow_runner.sh" reconcile CEN-29 >/dev/null
assert_eq 'in-review' "$(jq -r '.status' "$state_file")" 'dirty merge state is not merge-ready'
assert_eq '' "$(jq -r '.["CEN-29"].head_sha // ""' "$DAYFLOW_MERGE_READY_STORE")" 'dirty merge state not deduped'

unset FAKE_GH_MERGE_STATE
worktree="$DAYFLOW_WORKTREE_ROOT/CEN-29"
printf '%s\n' 'post-review change' >"$worktree/post-review.txt"
git -C "$worktree" add post-review.txt
git -C "$worktree" commit -m 'test: post-review push' >/dev/null
git -C "$worktree" push origin HEAD >/dev/null
"$SOURCE_ROOT/scripts/dayflow_runner.sh" reconcile CEN-29 >/dev/null
assert_eq 'review-required' "$(jq -r '.status' "$state_file")" 'post-review push requires rereview'
assert_failure 'post-review push returns PR to draft' test -f "$FAKE_GH_READY_FILE"

finish_tests 'dayflow_runner_system_test'
