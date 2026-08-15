#!/usr/bin/env bash
set -euo pipefail

TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SOURCE_ROOT="$(cd "$TEST_DIR/../.." && pwd)"
# shellcheck source=scripts/tests/testlib.sh
source "$TEST_DIR/testlib.sh"
# shellcheck source=scripts/tests/system_test_helpers.sh
source "$TEST_DIR/system_test_helpers.sh"

write_rest_fallback_gh() {
  local wrapper="$1"
  cat >"$wrapper" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

if [[ "${1:-} ${2:-}" == 'pr list' || ( "${1:-} ${2:-}" == 'pr create' && "${FAKE_GH_REST_CREATE:-false}" == 'true' ) ]]; then
  printf 'GH_CONFIG_DIR=%s :: %s\n' "${GH_CONFIG_DIR:-}" "$*" >>"${FAKE_GH_LOG:?}"
  exit 1
fi

if [[ "${1:-}" == 'api' && "$*" == *'repos/test/dayflow/pulls'* ]]; then
  printf 'GH_CONFIG_DIR=%s :: %s\n' "${GH_CONFIG_DIR:-}" "$*" >>"${FAKE_GH_LOG:?}"
  branch="${FAKE_PR_BRANCH:?}"
  body=''
  for arg in "$@"; do
    case "$arg" in
      head=*) branch="${arg#head=}"; branch="${branch#*:}" ;;
      body=*) body="${arg#body=}" ;;
    esac
  done
  head_sha="$(git -C "${FAKE_GIT_ROOT:?}" ls-remote --heads origin "refs/heads/$branch" | awk 'NR == 1 {print $1}')"
  if [[ "$*" == *'--method POST'* ]]; then
    printf '%s' "$body" >"${FAKE_GH_BODY_FILE:?}"
    : >"${FAKE_GH_PR_CREATED_FILE:?}"
  elif [[ ! -f "${FAKE_GH_PR_CREATED_FILE:?}" ]]; then
    printf '%s\n' '[]'
    exit 0
  fi
  draft=true
  [[ -f "${FAKE_GH_READY_FILE:?}" ]] && draft=false
  jq -n --argjson number 29 --arg branch "$branch" --arg head "$head_sha" --arg body "$(<"${FAKE_GH_BODY_FILE:?}")" \
    --argjson draft "$draft" \
    '{number:$number,html_url:"https://github.test/pr/29",draft:$draft,state:"open",merged_at:null,head:{ref:$branch,sha:$head},base:{ref:"develop"},mergeable_state:"clean",body:$body}' |
    if [[ "$*" == *'--method POST'* ]]; then jq -c '.'; else jq -cs '.'; fi
  exit 0
fi

exec "${FAKE_GH_DELEGATE_BIN:?}" "$@"
EOF
  chmod +x "$wrapper"
}

run_commit_then_push_recovery_test() {
  local test_root seed hook worktree
  test_root="$(mktemp -d)"
  seed="$(dayflow_create_test_repo "$test_root" "$SOURCE_ROOT")"
  dayflow_export_fake_environment "$test_root" "$SOURCE_ROOT" "$seed"
  dayflow_prepare_notification_fixture
  export FAKE_CODEX_MODE=success FAKE_REVIEW_MODE=clean
  export FAKE_CODEX_PRIMARY_COUNT_FILE="$test_root/primary-count"
  hook="$test_root/remote.git/hooks/pre-receive"
  printf '%s\n' '#!/bin/sh' 'exit 1' >"$hook"
  chmod +x "$hook"
  if "$SOURCE_ROOT/scripts/dayflow_runner.sh" run CEN-29 >/dev/null 2>&1; then
    test_fail 'push rejection should leave publication retry state'
  fi
  assert_eq 'committed' "$(jq -r '.publication.phase' "$DAYFLOW_STATE_ROOT/CEN-29.json")" 'commit phase persisted before push failure'
  rm -f "$hook"
  "$SOURCE_ROOT/scripts/dayflow_runner.sh" run CEN-29 >/dev/null
  assert_eq '1' "$(<"$FAKE_CODEX_PRIMARY_COUNT_FILE")" 'push retry invokes no additional primary model'
  worktree="$(jq -r '.worktree' "$DAYFLOW_STATE_ROOT/CEN-29.json")"
  assert_eq '1' "$(git -C "$worktree" rev-list --count origin/develop..HEAD)" 'push retry creates no duplicate commit'
  assert_eq 'merge-ready' "$(jq -r '.status' "$DAYFLOW_STATE_ROOT/CEN-29.json")" 'push retry completes review lifecycle'
  rm -rf "$test_root"
}

run_push_then_pr_recovery_test() {
  local test_root seed worktree
  test_root="$(mktemp -d)"
  seed="$(dayflow_create_test_repo "$test_root" "$SOURCE_ROOT")"
  dayflow_export_fake_environment "$test_root" "$SOURCE_ROOT" "$seed"
  dayflow_prepare_notification_fixture
  export FAKE_CODEX_MODE=success FAKE_REVIEW_MODE=clean
  export FAKE_CODEX_PRIMARY_COUNT_FILE="$test_root/primary-count"
  export FAKE_GH_PR_CREATED_FILE="$test_root/pr-created"
  export FAKE_GH_CREATE_FAIL_FILE="$test_root/fail-create-once"
  : >"$FAKE_GH_CREATE_FAIL_FILE"
  if "$SOURCE_ROOT/scripts/dayflow_runner.sh" run CEN-29 >/dev/null 2>&1; then
    test_fail 'PR creation rejection should leave publication retry state'
  fi
  assert_eq 'pushed' "$(jq -r '.publication.phase' "$DAYFLOW_STATE_ROOT/CEN-29.json")" 'push phase persisted before PR failure'
  assert_eq 'publication-retry' "$(jq -r '.status' "$DAYFLOW_STATE_ROOT/CEN-29.json")" 'post-push publication failure enters recovery'
  assert_success 'post-push publication failure preserves worktree' test -e "$DAYFLOW_WORKTREE_ROOT/CEN-29/.git"
  "$SOURCE_ROOT/scripts/dayflow_runner.sh" run CEN-29 >/dev/null
  assert_eq '1' "$(<"$FAKE_CODEX_PRIMARY_COUNT_FILE")" 'PR retry invokes no additional primary model'
  worktree="$(jq -r '.worktree' "$DAYFLOW_STATE_ROOT/CEN-29.json")"
  assert_eq '1' "$(git -C "$worktree" rev-list --count origin/develop..HEAD)" 'PR retry creates no duplicate commit'
  assert_eq '2' "$(rg -c 'pr create' "$FAKE_GH_LOG")" 'PR retry occurs once after one definite creation failure'
  assert_success 'PR retry converges to one created PR state' test -f "$FAKE_GH_PR_CREATED_FILE"
  assert_eq 'merge-ready' "$(jq -r '.status' "$DAYFLOW_STATE_ROOT/CEN-29.json")" 'PR retry completes review lifecycle'
  rm -rf "$test_root"
}

run_graphql_rest_publication_fallback_test() {
  local test_root seed wrapper
  test_root="$(mktemp -d)"
  seed="$(dayflow_create_test_repo "$test_root" "$SOURCE_ROOT")"
  dayflow_export_fake_environment "$test_root" "$SOURCE_ROOT" "$seed"
  dayflow_prepare_notification_fixture
  wrapper="$test_root/gh-rest-fallback"
  export FAKE_GH_DELEGATE_BIN="$DAYFLOW_GH_BIN"
  write_rest_fallback_gh "$wrapper"
  export DAYFLOW_GH_BIN="$wrapper"
  export FAKE_GH_REST_CREATE=true
  export FAKE_GH_PR_CREATED_FILE="$test_root/pr-created"
  export FAKE_CODEX_MODE=success FAKE_REVIEW_MODE=clean
  export FAKE_CODEX_PRIMARY_COUNT_FILE="$test_root/primary-count"

  "$SOURCE_ROOT/scripts/dayflow_runner.sh" run CEN-29 >/dev/null
  assert_eq 'merge-ready' "$(jq -r '.status' "$DAYFLOW_STATE_ROOT/CEN-29.json")" 'REST fallback publication lifecycle'
  assert_eq 'pr-created' "$(jq -r '.publication.phase' "$DAYFLOW_STATE_ROOT/CEN-29.json")" 'REST-created PR publication phase'
  assert_eq '1' "$(<"$FAKE_CODEX_PRIMARY_COUNT_FILE")" 'REST fallback launches one primary session'
  assert_file_contains "$FAKE_GH_LOG" 'pr create' 'GraphQL PR creation was attempted first'
  assert_file_contains "$FAKE_GH_LOG" 'api --method POST repos/test/dayflow/pulls' 'REST PR creation fallback was used'
  assert_file_contains "$FAKE_GH_LOG" 'api -X GET repos/test/dayflow/pulls' 'REST PR discovery validates delivery'
  rm -rf "$test_root"
}

run_missing_blocked_state_admission_test() {
  local test_root seed wrapper delegate
  test_root="$(mktemp -d)"
  seed="$(dayflow_create_test_repo "$test_root" "$SOURCE_ROOT")"
  dayflow_export_fake_environment "$test_root" "$SOURCE_ROOT" "$seed"
  dayflow_prepare_notification_fixture
  unset DAYFLOW_STATE_BLOCKED_ID
  delegate="$DAYFLOW_CURL_BIN"
  wrapper="$test_root/curl-missing-blocked"
  cat >"$wrapper" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
if [[ "$*" == *'states { nodes'* ]]; then
  printf '%s\n' "$*" >>"${FAKE_CURL_LOG:?}"
  printf '%s\n' '{"data":{"team":{"states":{"nodes":[{"id":"state-in-progress","name":"In Progress"},{"id":"state-in-review","name":"In Review"},{"id":"state-done","name":"Done"}]}}}}'
  exit 0
fi
exec "${FAKE_CURL_DELEGATE_BIN:?}" "$@"
EOF
  chmod +x "$wrapper"
  export FAKE_CURL_DELEGATE_BIN="$delegate"
  export DAYFLOW_CURL_BIN="$wrapper"
  export FAKE_CODEX_INVOCATION_COUNT_FILE="$test_root/invocations"

  if "$SOURCE_ROOT/scripts/dayflow_runner.sh" run CEN-29 >/dev/null 2>&1; then
    test_fail 'missing Linear Blocked state must reject admission'
  fi
  assert_eq 'blocked' "$(jq -r '.status' "$DAYFLOW_STATE_ROOT/CEN-29.json")" 'missing Blocked state records local block'
  assert_file_contains "$DAYFLOW_STATE_ROOT/CEN-29.json" 'DAYFLOW_STATE_\*_ID values before retrying' 'configuration block is actionable'
  assert_failure 'missing Blocked state creates no issue worktree' test -e "$DAYFLOW_WORKTREE_ROOT/CEN-29"
  assert_failure 'missing Blocked state launches no primary model' test -e "$FAKE_CODEX_INVOCATION_COUNT_FILE"
  assert_file_contains "$FAKE_CURL_LOG" 'discord.test/webhook' 'configuration block alerts Discord'
  assert_failure 'missing Blocked state attempts no impossible transition' rg -q 'state-blocked' "$FAKE_CURL_LOG"
  rm -rf "$test_root"
}

run_terminal_issue_skips_lifecycle_configuration_block_test() {
  local test_root seed wrapper delegate issue_fixture
  test_root="$(mktemp -d)"
  seed="$(dayflow_create_test_repo "$test_root" "$SOURCE_ROOT")"
  dayflow_export_fake_environment "$test_root" "$SOURCE_ROOT" "$seed"
  dayflow_prepare_notification_fixture
  unset DAYFLOW_STATE_BLOCKED_ID
  issue_fixture="$test_root/done-issue.json"
  jq '.state.name = "Done"' "$DAYFLOW_ISSUE_FIXTURE_FILE" >"$issue_fixture"
  export DAYFLOW_ISSUE_FIXTURE_FILE="$issue_fixture"
  delegate="$DAYFLOW_CURL_BIN"
  wrapper="$test_root/curl-missing-blocked"
  cat >"$wrapper" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
if [[ "$*" == *'states { nodes'* ]]; then
  printf '%s\n' '{"data":{"team":{"states":{"nodes":[{"id":"state-in-progress","name":"In Progress"},{"id":"state-in-review","name":"In Review"},{"id":"state-done","name":"Done"}]}}}}'
  exit 0
fi
exec "${FAKE_CURL_DELEGATE_BIN:?}" "$@"
EOF
  chmod +x "$wrapper"
  export FAKE_CURL_DELEGATE_BIN="$delegate"
  export DAYFLOW_CURL_BIN="$wrapper"

  assert_failure 'terminal issue remains non-runnable' "$SOURCE_ROOT/scripts/dayflow_runner.sh" run CEN-29
  assert_failure 'terminal issue creates no configuration block record' test -e "$DAYFLOW_STATE_ROOT/CEN-29.json"
  assert_failure 'terminal issue creates no worktree' test -e "$DAYFLOW_WORKTREE_ROOT/CEN-29"
  assert_failure 'terminal issue sends no configuration alert' rg -q 'discord.test/webhook' "$FAKE_CURL_LOG"
  rm -rf "$test_root"
}

run_missing_test_evidence_test() {
  local test_root seed
  test_root="$(mktemp -d)"
  seed="$(dayflow_create_test_repo "$test_root" "$SOURCE_ROOT")"
  dayflow_export_fake_environment "$test_root" "$SOURCE_ROOT" "$seed"
  dayflow_prepare_notification_fixture
  export FAKE_CODEX_MODE=success FAKE_REVIEW_MODE=clean FAKE_TEST_EVIDENCE_MODE=missing
  if "$SOURCE_ROOT/scripts/dayflow_runner.sh" run CEN-29 >/dev/null 2>&1; then
    test_fail 'missing structured test evidence must block publication'
  fi
  assert_eq 'blocked' "$(jq -r '.status' "$DAYFLOW_STATE_ROOT/CEN-29.json")" 'missing test evidence blocks issue'
  assert_failure 'missing test evidence creates no commit' git -C "$DAYFLOW_WORKTREE_ROOT/CEN-29" rev-parse HEAD^ >/dev/null 2>&1
  assert_failure 'missing test evidence creates no PR' rg -q 'pr create\|pr edit' "$FAKE_GH_LOG"
  rm -rf "$test_root"
}

run_review_remediation_test() {
  local test_root seed worktree commit_count
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
  worktree="$(jq -r '.worktree' "$DAYFLOW_STATE_ROOT/CEN-29.json")"
  commit_count="$(git -C "$worktree" rev-list --count origin/develop..HEAD)"
  assert_eq '2' "$commit_count" 'runner owns primary and remediation commits'
  assert_file_contains <(git -C "$worktree" log --format=%s origin/develop..HEAD) '^feat\(CEN-29\):' 'runner-generated commit subject'
  assert_file_contains "$FAKE_GH_LOG" "GH_CONFIG_DIR=$DAYFLOW_RUNTIME_DIR/gh :: auth status" 'canonical GitHub auth reaches issue worktree publication'
  assert_file_contains "$FAKE_GH_LOG" 'pr edit' 'runner owns PR proof publication'
  assert_file_contains "$FAKE_CODEX_LOG" 'mcp_servers=\{\}' 'irrelevant MCP startup disabled'
  assert_failure 'model never receives danger-full-access' rg -q 'danger-full-access' "$FAKE_CODEX_LOG"
  rm -rf "$test_root"
}

run_publication_preflight_failure_test() {
  local test_root seed
  test_root="$(mktemp -d)"
  seed="$(dayflow_create_test_repo "$test_root" "$SOURCE_ROOT")"
  dayflow_export_fake_environment "$test_root" "$SOURCE_ROOT" "$seed"
  dayflow_prepare_notification_fixture
  export FAKE_GH_AUTH_FAIL=true
  export FAKE_CODEX_INVOCATION_COUNT_FILE="$test_root/invocations"

  if "$SOURCE_ROOT/scripts/dayflow_runner.sh" run CEN-29 >/dev/null 2>&1; then
    test_fail 'missing GitHub publication capability must fail before model launch'
  fi
  assert_eq 'pre-session-blocked' "$(jq -r '.status' "$DAYFLOW_STATE_ROOT/CEN-29.json")" 'publication preflight recovery state'
  assert_failure 'publication preflight failure must not invoke Codex' test -e "$FAKE_CODEX_INVOCATION_COUNT_FILE"
  assert_file_contains "$FAKE_GH_LOG" "GH_CONFIG_DIR=$DAYFLOW_RUNTIME_DIR/gh :: auth status" 'preflight uses canonical GitHub auth directory'
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

run_stale_done_reconciliation_skip_test() {
  local test_root seed state_file auxiliary_file auxiliary_before
  test_root="$(mktemp -d)"
  seed="$(dayflow_create_test_repo "$test_root" "$SOURCE_ROOT")"
  dayflow_export_fake_environment "$test_root" "$SOURCE_ROOT" "$seed"
  state_file="$DAYFLOW_STATE_ROOT/CEN-29.json"
  mkdir -p "$DAYFLOW_STATE_ROOT"
  jq -n '{issue:"CEN-29",status:"done",branch:"feature/tasks-29-stacked-delivery",pr_number:29}' >"$state_file"
  auxiliary_file="$DAYFLOW_STATE_ROOT/CEN-28-publication.json"
  jq -n '{issue:"CEN-28",status:"publication-retry",publication:{phase:"committed"}}' >"$auxiliary_file"
  auxiliary_before="$(<"$auxiliary_file")"
  export DAYFLOW_ISSUE_FIXTURE_FILE="$test_root/missing-linear-fixture.json"
  export FAKE_GH_PR_STATE=MERGED FAKE_GH_BASE_BRANCH=feature/tasks-28-stack-base

  "$SOURCE_ROOT/scripts/dayflow_runner.sh" reconcile CEN-29 >/dev/null
  "$SOURCE_ROOT/scripts/dayflow_runner.sh" reconcile >/dev/null

  assert_eq 'done' "$(jq -r '.status' "$state_file")" 'stale completed record remains terminal'
  assert_eq "$auxiliary_before" "$(<"$auxiliary_file")" 'all-issue reconciliation ignores auxiliary state records'
  assert_failure 'auxiliary state record acquires no issue lock' test -e "$DAYFLOW_STATE_ROOT/CEN-28-publication.lock"
  assert_failure 'stale completed record makes no Linear call' test -s "$FAKE_CURL_LOG"
  assert_failure 'stale completed stacked PR makes no GitHub call' test -s "$FAKE_GH_LOG"
  rm -rf "$test_root"
}

run_merged_develop_reconciliation_test() {
  local test_root seed state_file
  test_root="$(mktemp -d)"
  seed="$(dayflow_create_test_repo "$test_root" "$SOURCE_ROOT")"
  dayflow_export_fake_environment "$test_root" "$SOURCE_ROOT" "$seed"
  dayflow_prepare_notification_fixture
  export FAKE_CODEX_MODE=success FAKE_REVIEW_MODE=clean
  "$SOURCE_ROOT/scripts/dayflow_runner.sh" run CEN-29 >/dev/null
  state_file="$DAYFLOW_STATE_ROOT/CEN-29.json"
  : >"$FAKE_CURL_LOG"
  export FAKE_GH_PR_STATE=MERGED

  "$SOURCE_ROOT/scripts/dayflow_runner.sh" reconcile CEN-29 >/dev/null

  assert_eq 'done' "$(jq -r '.status' "$state_file")" 'merged develop PR closes active local record'
  assert_file_contains "$FAKE_CURL_LOG" 'state-done' 'merged develop PR transitions Linear to Done'
  rm -rf "$test_root"
}

run_active_wrong_base_reconciliation_test() {
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
  export FAKE_GH_BASE_BRANCH=feature/tasks-28-stack-base

  if "$SOURCE_ROOT/scripts/dayflow_runner.sh" reconcile CEN-29 >/dev/null 2>&1; then
    test_fail 'active wrong-base PR must fail reconciliation'
  fi

  assert_eq "$state_before" "$(<"$state_file")" 'active wrong-base PR preserves fail-closed local state'
  assert_failure 'active wrong-base PR does not transition Linear to Done' rg -q -- 'state-done' "$FAKE_CURL_LOG"
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
  assert_failure 'failed primary run must not launch review' test -e "$FAKE_CODEX_REVIEW_COUNT_FILE"
  rm -rf "$test_root"
}

run_runner_guard_classification_case() (
  local guard="$1"
  local expected_reason="$2"
  local test_root seed
  test_root="$(mktemp -d)"
  seed="$(dayflow_create_test_repo "$test_root" "$SOURCE_ROOT")"
  dayflow_export_fake_environment "$test_root" "$SOURCE_ROOT" "$seed"
  dayflow_prepare_notification_fixture
  export DAYFLOW_RESOURCE_TOKEN_LIMIT=1000
  export DAYFLOW_CONTEXT_TOKEN_LIMIT=1000
  export DAYFLOW_LOG_LIMIT_BYTES=5242880
  export DAYFLOW_STALL_LIMIT_SECONDS=10
  export DAYFLOW_EXECUTION_LIMIT_SECONDS=10
  export FAKE_REVIEW_MODE=clean

  case "$guard" in
    resource-token)
      export FAKE_CODEX_MODE=token-limit DAYFLOW_RESOURCE_TOKEN_LIMIT=10
      ;;
    context-token)
      export FAKE_CODEX_MODE=token-limit DAYFLOW_CONTEXT_TOKEN_LIMIT=10
      ;;
    command-output)
      export FAKE_CODEX_MODE=output-limit DAYFLOW_LOG_LIMIT_BYTES=512
      ;;
    stall)
      export FAKE_CODEX_MODE=stall DAYFLOW_STALL_LIMIT_SECONDS=1
      ;;
    timeout)
      export FAKE_CODEX_MODE=execution-limit DAYFLOW_EXECUTION_LIMIT_SECONDS=1
      ;;
    *)
      test_fail "unknown runner guard fixture: $guard"
      ;;
  esac

  if "$SOURCE_ROOT/scripts/dayflow_runner.sh" run CEN-29 >/dev/null 2>&1; then
    test_fail "$guard guard should fail the run"
  fi
  assert_eq 'blocked' "$(jq -r '.status' "$DAYFLOW_STATE_ROOT/CEN-29.json")" "$guard guard records blocked state"
  assert_eq "$expected_reason" "$(jq -r '.last_error' "$DAYFLOW_STATE_ROOT/CEN-29.json")" "$guard guard reason is preserved"
  assert_failure "$guard guard is not classified as model rejection" rg -q 'model rejected' "$DAYFLOW_STATE_ROOT/CEN-29.json"
  assert_eq 'uncached_input_tokens + output_tokens' "$(jq -r '.token_budget.basis.resource' "$DAYFLOW_STATE_ROOT/CEN-29.json")" "$guard state exposes resource budget basis"
  rm -rf "$test_root"
)

run_runner_guard_classification_test() {
  run_runner_guard_classification_case resource-token 'uncached/output token limit exceeded (10)'
  run_runner_guard_classification_case context-token 'total context token limit exceeded (10)'
  run_runner_guard_classification_case command-output 'command output limit exceeded (512 bytes)'
  run_runner_guard_classification_case stall 'no progress for 1s'
  run_runner_guard_classification_case timeout 'execution limit exceeded (1s)'
}

run_publication_recovery_preflight_preservation_test() {
  local test_root seed hook before after
  test_root="$(mktemp -d)"
  seed="$(dayflow_create_test_repo "$test_root" "$SOURCE_ROOT")"
  dayflow_export_fake_environment "$test_root" "$SOURCE_ROOT" "$seed"
  dayflow_prepare_notification_fixture
  export FAKE_CODEX_MODE=success FAKE_REVIEW_MODE=clean FAKE_CODEX_PRIMARY_COUNT_FILE="$test_root/primary-count"
  hook="$test_root/remote.git/hooks/pre-receive"
  printf '%s\n' '#!/bin/sh' 'exit 1' >"$hook"
  chmod +x "$hook"
  "$SOURCE_ROOT/scripts/dayflow_runner.sh" run CEN-29 >/dev/null 2>&1 || true
  rm -f "$hook"
  before="$(jq -c '{session_id,publication,test_evidence}' "$DAYFLOW_STATE_ROOT/CEN-29.json")"
  export FAKE_GH_AUTH_FAIL=true
  assert_failure 'publication recovery preflight failure returns safely' "$SOURCE_ROOT/scripts/dayflow_runner.sh" run CEN-29
  after="$(jq -c '{session_id,publication,test_evidence}' "$DAYFLOW_STATE_ROOT/CEN-29.json")"
  assert_eq 'publication-retry' "$(jq -r '.status' "$DAYFLOW_STATE_ROOT/CEN-29.json")" 'preflight failure preserves publication retry status'
  assert_eq "$before" "$after" 'preflight failure preserves session phase head and evidence'
  assert_eq '1' "$(<"$FAKE_CODEX_PRIMARY_COUNT_FILE")" 'preflight recovery failure invokes no primary model'
  unset FAKE_GH_AUTH_FAIL
  rm -rf "$test_root"
}

run_requested_changes_auto_resume_test() {
  local test_root seed state_file worktree commits
  test_root="$(mktemp -d)"
  seed="$(dayflow_create_test_repo "$test_root" "$SOURCE_ROOT")"
  dayflow_export_fake_environment "$test_root" "$SOURCE_ROOT" "$seed"
  dayflow_prepare_notification_fixture
  export FAKE_CODEX_MODE=success FAKE_REVIEW_MODE=clean FAKE_CODEX_PRIMARY_COUNT_FILE="$test_root/primary-count"
  "$SOURCE_ROOT/scripts/dayflow_runner.sh" run CEN-29 >/dev/null
  export FAKE_GH_REQUESTED_CHANGES=true FAKE_GH_REQUESTED_BODY='Change the focused fixture behavior.'
  "$SOURCE_ROOT/scripts/dayflow_runner.sh" reconcile CEN-29 >/dev/null
  state_file="$DAYFLOW_STATE_ROOT/CEN-29.json"
  assert_eq 'review-changes' "$(jq -r '.status' "$state_file")" 'requested changes persisted for auto resume'
  assert_eq 'Change the focused fixture behavior.' "$(jq -r '.requested_changes.reviews[0].body' "$state_file")" 'current requested-change body persisted'
  assert_eq "$(jq -r '.reviewed_head_sha' "$state_file")" "$(jq -r '.requested_changes.reviewed_head_sha' "$state_file")" 'requested changes persist reviewed head'
  unset FAKE_GH_REQUESTED_CHANGES
  export FAKE_CODEX_PROMPT_LOG="$test_root/requested.prompt"
  "$SOURCE_ROOT/scripts/dayflow_runner.sh" run CEN-29 >/dev/null
  assert_file_contains "$FAKE_CODEX_PROMPT_LOG" 'Change the focused fixture behavior' 'auto-resume prompt includes current requested feedback'
  assert_file_contains "$FAKE_CODEX_LOG" 'resume.*fake-primary-session' 'requested changes reuse the primary session'
  assert_eq '2' "$(<"$FAKE_CODEX_PRIMARY_COUNT_FILE")" 'requested changes invoke one remediation primary turn'
  worktree="$(jq -r '.worktree' "$state_file")"
  commits="$(git -C "$worktree" rev-list --count origin/develop..HEAD)"
  assert_eq '2' "$commits" 'requested changes publish a new remediation commit'
  rm -rf "$test_root"
}

run_requested_changes_no_change_test() {
  local test_root seed worktree
  test_root="$(mktemp -d)"
  seed="$(dayflow_create_test_repo "$test_root" "$SOURCE_ROOT")"
  dayflow_export_fake_environment "$test_root" "$SOURCE_ROOT" "$seed"
  dayflow_prepare_notification_fixture
  export FAKE_CODEX_MODE=success FAKE_REVIEW_MODE=clean
  "$SOURCE_ROOT/scripts/dayflow_runner.sh" run CEN-29 >/dev/null
  export FAKE_GH_REQUESTED_CHANGES=true
  "$SOURCE_ROOT/scripts/dayflow_runner.sh" reconcile CEN-29 >/dev/null
  unset FAKE_GH_REQUESTED_CHANGES
  export FAKE_CODEX_NO_CHANGE=true
  assert_failure 'requested changes no-op blocks safely' "$SOURCE_ROOT/scripts/dayflow_runner.sh" run CEN-29
  assert_eq 'blocked' "$(jq -r '.status' "$DAYFLOW_STATE_ROOT/CEN-29.json")" 'requested changes no-op is blocked'
  worktree="$(jq -r '.worktree' "$DAYFLOW_STATE_ROOT/CEN-29.json")"
  assert_eq '1' "$(git -C "$worktree" rev-list --count origin/develop..HEAD)" 'requested changes no-op does not republish old commit'
  rm -rf "$test_root"
}

run_unsafe_publication_case() {
  local kind="$1"
  local test_root seed hook state_file worktree tmp
  test_root="$(mktemp -d)"
  seed="$(dayflow_create_test_repo "$test_root" "$SOURCE_ROOT")"
  dayflow_export_fake_environment "$test_root" "$SOURCE_ROOT" "$seed"
  dayflow_prepare_notification_fixture
  export FAKE_CODEX_MODE=success FAKE_REVIEW_MODE=clean
  hook="$test_root/remote.git/hooks/pre-receive"
  printf '%s\n' '#!/bin/sh' 'exit 1' >"$hook"
  chmod +x "$hook"
  "$SOURCE_ROOT/scripts/dayflow_runner.sh" run CEN-29 >/dev/null 2>&1 || true
  rm -f "$hook"
  state_file="$DAYFLOW_STATE_ROOT/CEN-29.json"
  worktree="$(jq -r '.worktree' "$state_file")"
  case "$kind" in
    invalid-phase) tmp="$state_file.tmp"; jq '.publication.phase = "invalid"' "$state_file" >"$tmp"; mv "$tmp" "$state_file" ;;
    dirty-post-commit) printf '%s\n' dirty >>"$worktree/runner-result.txt" ;;
    mismatched-commit)
      git -C "$worktree" commit --allow-empty -m 'wrong publication subject' >/dev/null
      tmp="$state_file.tmp"; jq '.publication.phase = "edited"' "$state_file" >"$tmp"; mv "$tmp" "$state_file"
      ;;
  esac
  assert_failure "$kind publication invariant fails" "$SOURCE_ROOT/scripts/dayflow_runner.sh" run CEN-29
  assert_eq 'blocked' "$(jq -r '.status' "$state_file")" "$kind is classified unsafe and blocked"
  assert_eq 'unsafe' "$(jq -r '.publication.failure' "$state_file")" "$kind persists unsafe classification"
  rm -rf "$test_root"
}

run_owned_recovery_gate_case() {
  local recovery_mode="$1"
  local failure_gate="$2"
  local test_root seed hook state_file original preserved session_id expected_primary_count
  test_root="$(mktemp -d)"
  seed="$(dayflow_create_test_repo "$test_root" "$SOURCE_ROOT")"
  dayflow_export_fake_environment "$test_root" "$SOURCE_ROOT" "$seed"
  dayflow_prepare_notification_fixture
  export FAKE_CODEX_MODE=success FAKE_REVIEW_MODE=clean FAKE_CODEX_PRIMARY_COUNT_FILE="$test_root/primary-count"

  if [[ "$recovery_mode" == "publication-retry" ]]; then
    hook="$test_root/remote.git/hooks/pre-receive"
    printf '%s\n' '#!/bin/sh' 'exit 1' >"$hook"
    chmod +x "$hook"
    "$SOURCE_ROOT/scripts/dayflow_runner.sh" run CEN-29 >/dev/null 2>&1 || true
    rm -f "$hook"
    expected_primary_count=1
  else
    "$SOURCE_ROOT/scripts/dayflow_runner.sh" run CEN-29 >/dev/null
    export FAKE_GH_REQUESTED_CHANGES=true FAKE_GH_REQUESTED_BODY='Preserve this requested-change feedback.'
    "$SOURCE_ROOT/scripts/dayflow_runner.sh" reconcile CEN-29 >/dev/null
    unset FAKE_GH_REQUESTED_CHANGES
    expected_primary_count=2
  fi

  state_file="$DAYFLOW_STATE_ROOT/CEN-29.json"
  assert_eq "$recovery_mode" "$(jq -r '.status' "$state_file")" "$recovery_mode fixture enters owned recovery"
  session_id="$(jq -r '.session_id' "$state_file")"
  original="$(jq -Sc 'del(.last_error,.updated_at)' "$state_file")"
  if [[ "$failure_gate" == "preflight" ]]; then
    export FAKE_GH_AUTH_FAIL=true
  else
    export FAKE_LINEAR_FAIL_STATE=state-in-progress
  fi
  assert_failure "$recovery_mode $failure_gate gate failure returns" "$SOURCE_ROOT/scripts/dayflow_runner.sh" run CEN-29
  preserved="$(jq -Sc 'del(.last_error,.updated_at)' "$state_file")"
  assert_eq "$original" "$preserved" "$recovery_mode $failure_gate preserves exact owned recovery state"

  unset FAKE_GH_AUTH_FAIL FAKE_LINEAR_FAIL_STATE
  "$SOURCE_ROOT/scripts/dayflow_runner.sh" run CEN-29 >/dev/null
  assert_eq "$session_id" "$(jq -r '.session_id' "$state_file")" "$recovery_mode $failure_gate later retry preserves primary session"
  assert_eq "$expected_primary_count" "$(<"$FAKE_CODEX_PRIMARY_COUNT_FILE")" "$recovery_mode $failure_gate later retry creates no new primary session"
  assert_eq 'merge-ready' "$(jq -r '.status' "$state_file")" "$recovery_mode $failure_gate later retry completes"
  if [[ "$recovery_mode" == "review-changes" ]]; then
    assert_file_contains "$FAKE_CODEX_LOG" 'resume.*fake-primary-session' "$recovery_mode $failure_gate uses same-session resume"
  fi
  rm -rf "$test_root"
}

if [[ "${DAYFLOW_INTEGRATION_FOCUS:-}" == "state-scan" ]]; then
  run_stale_done_reconciliation_skip_test
elif [[ "${DAYFLOW_INTEGRATION_FOCUS:-}" == "locks" ]]; then
  run_webhook_retry_and_lock_test
elif [[ "${DAYFLOW_INTEGRATION_FOCUS:-}" == "publication-fallback" ]]; then
  run_push_then_pr_recovery_test
  run_graphql_rest_publication_fallback_test
  run_missing_blocked_state_admission_test
  run_terminal_issue_skips_lifecycle_configuration_block_test
elif [[ "${DAYFLOW_INTEGRATION_FOCUS:-}" == "reconciliation" ]]; then
  run_stale_done_reconciliation_skip_test
  run_merged_develop_reconciliation_test
  run_active_wrong_base_reconciliation_test
elif [[ "${DAYFLOW_INTEGRATION_FOCUS:-}" == "owned-recovery-gates" ]]; then
  run_owned_recovery_gate_case publication-retry preflight
  run_owned_recovery_gate_case publication-retry linear
  run_owned_recovery_gate_case review-changes preflight
  run_owned_recovery_gate_case review-changes linear
elif [[ "${DAYFLOW_INTEGRATION_FOCUS:-}" == "runner-guards" ]]; then
  run_runner_guard_classification_test
else
  run_commit_then_push_recovery_test
  run_push_then_pr_recovery_test
  run_graphql_rest_publication_fallback_test
  run_missing_blocked_state_admission_test
  run_terminal_issue_skips_lifecycle_configuration_block_test
  run_missing_test_evidence_test
  run_publication_recovery_preflight_preservation_test
  run_requested_changes_auto_resume_test
  run_requested_changes_no_change_test
  run_unsafe_publication_case invalid-phase
  run_unsafe_publication_case dirty-post-commit
  run_unsafe_publication_case mismatched-commit
  run_owned_recovery_gate_case publication-retry preflight
  run_owned_recovery_gate_case publication-retry linear
  run_owned_recovery_gate_case review-changes preflight
  run_owned_recovery_gate_case review-changes linear
  run_review_remediation_test
  run_publication_preflight_failure_test
  run_model_rejection_test
  run_delivery_integrity_test
  run_review_execution_failure_draft_test
  run_start_transition_failure_test
  run_review_visibility_test
  run_final_blocker_visibility_test
  run_ci_timeout_test
  run_webhook_retry_and_lock_test
  run_stale_done_reconciliation_skip_test
  run_merged_develop_reconciliation_test
  run_active_wrong_base_reconciliation_test
  run_merged_reviewed_head_integrity_test
  run_merged_linear_done_rejection_test
  run_cross_issue_merge_ready_store_lock_test
  run_runner_guard_classification_test
fi
finish_tests 'dayflow_runner_integration_test'
