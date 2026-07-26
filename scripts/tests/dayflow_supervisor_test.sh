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
export DAYFLOW_ROOT_DIR="$SOURCE_ROOT"
export DAYFLOW_RUNTIME_DIR="$TEST_TMP/runtime"
export DAYFLOW_WORKTREE_ROOT="$DAYFLOW_RUNTIME_DIR/worktrees"
export DAYFLOW_STATE_ROOT="$DAYFLOW_RUNTIME_DIR/state"
export DAYFLOW_LOG_ROOT="$DAYFLOW_RUNTIME_DIR/logs"
export DAYFLOW_LEGACY_RUNTIME_DIR="$TEST_TMP/legacy"
export DAYFLOW_SUPERVISOR_ROOT="$DAYFLOW_RUNTIME_DIR/supervisor"
export DAYFLOW_SUPERVISOR_CLAIM_ROOT="$DAYFLOW_SUPERVISOR_ROOT/claims"
export DAYFLOW_SUPERVISOR_LOCK_DIR="$DAYFLOW_SUPERVISOR_ROOT/once.lock"
export DAYFLOW_SUPERVISOR_SNAPSHOT="$DAYFLOW_SUPERVISOR_ROOT/queue.json"
export DAYFLOW_CURL_BIN="$TEST_DIR/fakes/curl"
export FAKE_CURL_LOG="$TEST_TMP/curl.log"
# shellcheck source=scripts/lib/dayflow_supervisor.sh
source "$SOURCE_ROOT/scripts/lib/dayflow_supervisor.sh"

dayflow_supervisor_initialize
snapshot="$(jq -c --argjson now "$(date +%s)" '.generated_epoch = $now' "$TEST_DIR/fixtures/supervisor-issues.json")"
assert_success 'fresh queue snapshot validation' dayflow_supervisor_validate_snapshot "$snapshot"
assert_eq $'CEN-41\nCEN-40\nCEN-43' "$(dayflow_supervisor_candidates "$snapshot")" 'priority order after dependency filtering'

resume_worktree="$DAYFLOW_WORKTREE_ROOT/CEN-50"
mkdir -p "$resume_worktree"
git -C "$resume_worktree" init -b feature/tasks-50-remediation >/dev/null
git -C "$resume_worktree" config user.name 'DayFlow Tests'
git -C "$resume_worktree" config user.email 'dayflow-tests@example.invalid'
printf '%s\n' owned >"$resume_worktree/README.md"
git -C "$resume_worktree" add README.md
git -C "$resume_worktree" commit -m seed >/dev/null
jq -n --arg worktree "$resume_worktree" '{issue:"CEN-50",status:"review-changes",worktree:$worktree,branch:"feature/tasks-50-remediation",session_id:"owned-session",primary_agent:"integration-agent",model:"gpt-5.6-sol",reasoning:"high"}' \
  >"$DAYFLOW_STATE_ROOT/CEN-50.json"
resume_snapshot="$(jq -c '
  .issues += [
    {id:"issue-50",identifier:"CEN-50",title:"[Integration] Owned remediation",description:"Parallel Safe: yes\nWrite Scope:\n- docs/remediation/**",priority:4,state:"In Progress",blockers:[]},
    {id:"issue-51",identifier:"CEN-51",title:"[Integration] Unrelated active work",description:"Write Scope:\n- docs/unrelated/**",priority:1,state:"In Progress",blockers:[]}
  ]
' <<<"$snapshot")"
resume_candidates="$(dayflow_supervisor_candidates "$resume_snapshot")"
assert_eq 'CEN-50' "$(head -n 1 <<<"$resume_candidates")" 'owned review changes are prioritized before Todo'
assert_failure 'unrelated In Progress issue is skipped' grep -Fxq CEN-51 <<<"$resume_candidates"
resume_selected="$TEST_TMP/resume-selected"
DAYFLOW_SUPERVISOR_MAX_PARALLEL=1 dayflow_supervisor_select "$resume_snapshot" "$resume_selected"
resume_dispatch_log="$TEST_TMP/resume-dispatch.log"
export FAKE_SUPERVISOR_RUNNER_LOG="$resume_dispatch_log"
saved_supervisor_runner_bin="$DAYFLOW_SUPERVISOR_RUNNER_BIN"
DAYFLOW_SUPERVISOR_RUNNER_BIN="$TEST_DIR/fakes/supervisor_runner"
assert_success 'owned review changes dispatch automatically' dayflow_supervisor_dispatch "$resume_selected"
assert_file_contains "$resume_dispatch_log" '^run CEN-50$' 'owned remediation was dispatched before Todo'
DAYFLOW_SUPERVISOR_RUNNER_BIN="$saved_supervisor_runner_bin"

jq -n --arg worktree "$resume_worktree" '{issue:"CEN-50",status:"publication-retry",worktree:$worktree,branch:"feature/tasks-50-remediation",session_id:"owned-session",primary_agent:"integration-agent",model:"gpt-5.6-sol",reasoning:"high",publication:{phase:"committed",head_sha:"fixture-head"},test_evidence:{summary:"fixture",tests:[{name:"focused",status:"passed"}]}}' \
  >"$DAYFLOW_STATE_ROOT/CEN-50.json"
printf '%s\n' '{"identifier":"CEN-50","pid":999999,"process_start":"stale","parallel_safe":true,"write_scopes":["docs/remediation"]}' \
  >"$DAYFLOW_SUPERVISOR_CLAIM_ROOT/CEN-50.json"
assert_success 'stale publication retry claim is terminal-safe' dayflow_supervisor_reconcile_claims
assert_failure 'stale publication retry claim is released' test -f "$DAYFLOW_SUPERVISOR_CLAIM_ROOT/CEN-50.json"
publication_selected="$TEST_TMP/publication-selected"
DAYFLOW_SUPERVISOR_MAX_PARALLEL=1 dayflow_supervisor_select "$resume_snapshot" "$publication_selected"
publication_dispatch_log="$TEST_TMP/publication-dispatch.log"
export FAKE_SUPERVISOR_RUNNER_LOG="$publication_dispatch_log"
DAYFLOW_SUPERVISOR_RUNNER_BIN="$TEST_DIR/fakes/supervisor_runner"
assert_success 'released publication retry dispatches automatically' dayflow_supervisor_dispatch "$publication_selected"
assert_file_contains "$publication_dispatch_log" '^run CEN-50$' 'publication retry was picked up after stale claim release'
DAYFLOW_SUPERVISOR_RUNNER_BIN="$saved_supervisor_runner_bin"

relation_response='{"data":{"issues":{"nodes":[
  {"id":"a","identifier":"CEN-80","title":"blocker","description":"","priority":1,"updatedAt":"","state":{"name":"Done"},"relations":{"nodes":[{"type":"blocks","relatedIssue":{"identifier":"CEN-81","state":{"name":"Todo"}}}]},"inverseRelations":{"nodes":[]}},
  {"id":"b","identifier":"CEN-81","title":"inverse blocked","description":"","priority":2,"updatedAt":"","state":{"name":"Todo"},"relations":{"nodes":[]},"inverseRelations":{"nodes":[{"type":"blocks","relatedIssue":{"identifier":"CEN-80","state":{"name":"Done"}}}]}},
  {"id":"c","identifier":"CEN-82","title":"direct blockedBy","description":"","priority":3,"updatedAt":"","state":{"name":"Todo"},"relations":{"nodes":[{"type":"blockedBy","relatedIssue":{"identifier":"CEN-80","state":{"name":"Done"}}}]},"inverseRelations":{"nodes":[]}}
]}}}'
relation_snapshot="$(dayflow_supervisor_snapshot_from_response "$relation_response" "$(date +%s)")"
assert_eq '0' "$(jq '.issues[] | select(.identifier == "CEN-80") | .blockers | length' <<<"$relation_snapshot")" 'outgoing blocks relation is not reversed onto blocker'
assert_eq 'CEN-80' "$(jq -r '.issues[] | select(.identifier == "CEN-81") | .blockers[0].identifier' <<<"$relation_snapshot")" 'inverse blocks relation identifies blocker'
assert_eq 'CEN-80' "$(jq -r '.issues[] | select(.identifier == "CEN-82") | .blockers[0].identifier' <<<"$relation_snapshot")" 'direct blockedBy relation identifies blocker'
set +e
(ulimit -t 2; dayflow_supervisor_graph_has_cycle "$snapshot")
acyclic_status=$?
set -e
assert_eq '1' "$acyclic_status" 'acyclic dependency graph returns promptly without a cycle'

cycle="$(jq -c --argjson now "$(date +%s)" '.generated_epoch = $now' "$TEST_DIR/fixtures/supervisor-cycle.json")"
assert_success 'cycle detection fails closed' dayflow_supervisor_graph_has_cycle "$cycle"
stale="$(jq -c --argjson old "$(( $(date +%s) - 1000 ))" '.generated_epoch = $old' <<<"$snapshot")"
DAYFLOW_SUPERVISOR_STALE_SECONDS=10
assert_failure 'stale queue snapshot fails closed' dayflow_supervisor_validate_snapshot "$stale"
DAYFLOW_SUPERVISOR_STALE_SECONDS=300

selected="$TEST_TMP/selected"
DAYFLOW_SUPERVISOR_MAX_PARALLEL=1
dayflow_supervisor_select "$snapshot" "$selected"
assert_eq 'CEN-41' "$(jq -r '.identifier' "$selected")" 'sequential dispatch is the default'
DAYFLOW_SUPERVISOR_MAX_PARALLEL=2
dayflow_supervisor_select "$snapshot" "$selected"
assert_eq $'CEN-41\nCEN-40' "$(jq -r '.identifier' "$selected")" 'two non-overlapping parallel-safe issues admitted'
overlap="$(jq -c '(.issues[] | select(.identifier == "CEN-40") | .description) = "Parallel Safe: yes\n\nWrite Scope:\n- docs/queue-b/**"' <<<"$snapshot")"
dayflow_supervisor_select "$overlap" "$selected"
assert_eq 'CEN-41' "$(jq -r '.identifier' "$selected")" 'overlapping and non-explicit scopes cannot fill parallel slot'

assert_success 'supervisor lock acquisition' dayflow_supervisor_acquire_lock
assert_failure 'live supervisor lock rejects restart overlap' dayflow_supervisor_acquire_lock
dayflow_supervisor_release_lock
mkdir "$DAYFLOW_SUPERVISOR_LOCK_DIR"
printf '%s\n' 999999 >"$DAYFLOW_SUPERVISOR_LOCK_DIR/pid"
assert_success 'stale supervisor lock recovers' dayflow_supervisor_acquire_lock
dayflow_supervisor_release_lock

printf '%s\n' '{"identifier":"CEN-70","pid":999999,"parallel_safe":true,"write_scopes":["scripts/a"]}' >"$DAYFLOW_SUPERVISOR_CLAIM_ROOT/CEN-70.json"
printf '%s\n' '{"status":"running"}' >"$DAYFLOW_STATE_ROOT/CEN-70.json"
assert_failure 'dead claim with running state fails closed' dayflow_supervisor_reconcile_claims
assert_success 'unsafe stale claim is preserved' test -f "$DAYFLOW_SUPERVISOR_CLAIM_ROOT/CEN-70.json"
printf '%s\n' '{"status":"blocked"}' >"$DAYFLOW_STATE_ROOT/CEN-70.json"
assert_success 'terminal stale claim is restart-safe' dayflow_supervisor_reconcile_claims
assert_failure 'terminal stale claim is released' test -f "$DAYFLOW_SUPERVISOR_CLAIM_ROOT/CEN-70.json"

launchd_root="$TEST_TMP/canonical"
launchd_log="$TEST_TMP/launchctl.log"
launchd_secret='linear-secret-not-for-output'
mkdir -p "$launchd_root/scripts/lib" "$launchd_root/scripts/automation"
cp "$SOURCE_ROOT/scripts/dayflow_supervisor.sh" "$launchd_root/scripts/dayflow_supervisor.sh"
cp "$SOURCE_ROOT/scripts/lib/dayflow_supervisor.sh" "$launchd_root/scripts/lib/dayflow_supervisor.sh"
cp "$SOURCE_ROOT/scripts/lib/dayflow_runner.sh" "$launchd_root/scripts/lib/dayflow_runner.sh"
cp "$SOURCE_ROOT/scripts/automation/com.dayflow.supervisor.plist.template" "$launchd_root/scripts/automation/com.dayflow.supervisor.plist.template"
chmod +x "$launchd_root/scripts/dayflow_supervisor.sh"
saved_canonical_root="$DAYFLOW_CANONICAL_REPO_ROOT"
saved_launchctl_bin="$DAYFLOW_SUPERVISOR_LAUNCHCTL_BIN"
DAYFLOW_CANONICAL_REPO_ROOT="$launchd_root"
DAYFLOW_SUPERVISOR_LAUNCHCTL_BIN="$TEST_DIR/fakes/launchctl"
DAYFLOW_SUPERVISOR_MAX_PARALLEL_EXPLICIT=x
DAYFLOW_SUPERVISOR_MAX_PARALLEL=2
export FAKE_LAUNCHCTL_LOG="$launchd_log"
export LINEAR_API_KEY="$launchd_secret"
assert_success 'start persists launchd runtime and loads job' dayflow_supervisor_start
launchd_env="$launchd_root/.dayflow/supervisor.env"
launchd_plist="$launchd_root/.dayflow/supervisor/com.dayflow.supervisor.plist"
if launchd_mode="$(stat -f '%Lp' "$launchd_env" 2>/dev/null)"; then
  :
else
  launchd_mode="$(stat -c '%a' "$launchd_env")"
fi
assert_eq '600' "$launchd_mode" 'launchd environment mode is 0600'
assert_file_contains "$launchd_env" '^export DAYFLOW_SUPERVISOR_MAX_PARALLEL=2$' 'explicit max parallel persists for launchd'
assert_file_contains "$launchd_plist" "$launchd_root/scripts/dayflow_supervisor.sh" 'plist uses canonical supervisor program'
assert_file_contains "$launchd_plist" 'launchd-once' 'plist uses launchd bootstrap command'
assert_failure 'plist excludes Linear secret' rg -q --fixed-strings "$launchd_secret" "$launchd_plist"
assert_failure 'launchctl log excludes Linear secret' rg -q --fixed-strings "$launchd_secret" "$launchd_log"
assert_success 'launchd bootstrap loads persisted env without terminal exports' env -i HOME="$HOME" /bin/bash -c \
  'source "$1" launchd-once; [[ "$LINEAR_API_KEY" == "$2" && -n "$PATH" ]]' _ \
  "$launchd_root/scripts/dayflow_supervisor.sh" "$launchd_secret"
status_json="$(dayflow_supervisor_status)"
assert_failure 'status excludes Linear secret' rg -q --fixed-strings "$launchd_secret" <<<"$status_json"

missing_log="$TEST_TMP/launchd-missing.log"
mv "$launchd_env" "$launchd_env.saved"
assert_failure 'missing launchd environment fails closed' /bin/bash -c \
  'env -i HOME="$1" /bin/bash "$2" launchd-once 2>"$3"' _ "$HOME" \
  "$launchd_root/scripts/dayflow_supervisor.sh" "$missing_log"
assert_file_contains "$missing_log" 'launchd environment file is missing or invalid' 'missing env produces useful supervisor log'
assert_failure 'missing-env log excludes Linear secret' rg -q --fixed-strings "$launchd_secret" "$missing_log"
mv "$launchd_env.saved" "$launchd_env"
chmod 644 "$launchd_env"
assert_failure 'insecure launchd environment fails closed' env -i HOME="$HOME" /bin/bash \
  "$launchd_root/scripts/dayflow_supervisor.sh" launchd-once
chmod 600 "$launchd_env"
cp "$launchd_env" "$launchd_env.valid"
printf '%s\n' 'export PATH=/usr/bin:/bin' 'unexpected=value' >"$launchd_env"
chmod 600 "$launchd_env"
malformed_log="$TEST_TMP/launchd-malformed.log"
assert_failure 'malformed launchd environment fails closed' /bin/bash -c \
  'env -i HOME="$1" /bin/bash "$2" launchd-once 2>"$3"' _ "$HOME" \
  "$launchd_root/scripts/dayflow_supervisor.sh" "$malformed_log"
assert_file_contains "$malformed_log" 'launchd environment file is malformed' 'malformed env produces useful supervisor log'
mv "$launchd_env.valid" "$launchd_env"

DAYFLOW_CANONICAL_REPO_ROOT="$saved_canonical_root"
DAYFLOW_SUPERVISOR_LAUNCHCTL_BIN="$saved_launchctl_bin"

system_runtime="$TEST_TMP/system-runtime"
system_fixture="$TEST_TMP/system-issues.json"
runner_log="$TEST_TMP/supervisor-runner.log"
jq '{issues: [.issues[] | .state = "In Review"]}' "$TEST_DIR/fixtures/supervisor-issues.json" >"$system_fixture"
export DAYFLOW_RUNTIME_DIR="$system_runtime"
export DAYFLOW_WORKTREE_ROOT="$system_runtime/worktrees"
export DAYFLOW_STATE_ROOT="$system_runtime/state"
export DAYFLOW_LOG_ROOT="$system_runtime/logs"
export DAYFLOW_SUPERVISOR_ROOT="$system_runtime/supervisor"
export DAYFLOW_SUPERVISOR_CLAIM_ROOT="$system_runtime/supervisor/claims"
export DAYFLOW_SUPERVISOR_LOCK_DIR="$system_runtime/supervisor/once.lock"
export DAYFLOW_SUPERVISOR_SNAPSHOT="$system_runtime/supervisor/queue.json"
export DAYFLOW_SUPERVISOR_RUNNER_BIN="$TEST_DIR/fakes/supervisor_runner"
export DAYFLOW_SUPERVISOR_ISSUES_FILE="$system_fixture"
export FAKE_SUPERVISOR_RUNNER_LOG="$runner_log"
export LINEAR_API_KEY=test
DAYFLOW_SUPERVISOR_MAX_PARALLEL=1 "$SOURCE_ROOT/scripts/dayflow_supervisor.sh" once
assert_failure 'idle queue launches no issue model runner' rg -q '^run ' "$runner_log"

printf '%s\n' '{"issues":[{"identifier":"CEN-60","title":"merged blocker","description":"","priority":1,"state":"In Review","blockers":[]},{"identifier":"CEN-61","title":"unblocked next","description":"","priority":2,"state":"Todo","blockers":[{"identifier":"CEN-60","state":"In Review"}]}]}' >"$system_fixture"
export FAKE_SUPERVISOR_RECONCILE_DONE_KEY=CEN-60
DAYFLOW_SUPERVISOR_MAX_PARALLEL=1 "$SOURCE_ROOT/scripts/dayflow_supervisor.sh" once
assert_file_contains "$runner_log" '^run CEN-61$' 'merge reconciliation triggers next eligible dispatch'
assert_failure 'completed claim removed after dispatch' test -f "$DAYFLOW_SUPERVISOR_CLAIM_ROOT/CEN-61.json"
before_status_lines="$(wc -l <"$runner_log" | tr -d ' ')"
status_json="$("$SOURCE_ROOT/scripts/dayflow_supervisor.sh" status)"
assert_eq '0' "$(jq '.claims | length' <<<"$status_json")" 'status reports zero active claims'
assert_eq "$before_status_lines" "$(wc -l <"$runner_log" | tr -d ' ')" 'status starts no model or runner'
unset FAKE_SUPERVISOR_RECONCILE_DONE_KEY

cleanup_root="$TEST_TMP/cleanup"
cleanup_seed="$(dayflow_create_test_repo "$cleanup_root" "$SOURCE_ROOT")"
ROOT_DIR="$cleanup_seed"
DAYFLOW_RUNTIME_DIR="$cleanup_root/runtime"
DAYFLOW_WORKTREE_ROOT="$DAYFLOW_RUNTIME_DIR/worktrees"
DAYFLOW_STATE_ROOT="$DAYFLOW_RUNTIME_DIR/state"
DAYFLOW_LOG_ROOT="$DAYFLOW_RUNTIME_DIR/logs"
mkdir -p "$DAYFLOW_WORKTREE_ROOT" "$DAYFLOW_STATE_ROOT" "$DAYFLOW_LOG_ROOT"
for cleanup_issue in CEN-28 CEN-62 CEN-63; do
  cleanup_branch="feature/tasks-${cleanup_issue#CEN-}-cleanup"
  git -C "$cleanup_seed" worktree add -b "$cleanup_branch" "$DAYFLOW_WORKTREE_ROOT/$cleanup_issue" develop >/dev/null
  jq -n --arg issue "$cleanup_issue" --arg branch "$cleanup_branch" --arg worktree "$DAYFLOW_WORKTREE_ROOT/$cleanup_issue" \
    '{issue:$issue,status:"done",branch:$branch,worktree:$worktree}' >"$DAYFLOW_STATE_ROOT/$cleanup_issue.json"
done
printf '%s\n' dirty >"$DAYFLOW_WORKTREE_ROOT/CEN-63/untracked.txt"
dayflow_status_issue() {
  local issue_key="$1"
  local state_file branch
  state_file="$DAYFLOW_STATE_ROOT/$issue_key.json"
  branch="$(jq -r '.branch' "$state_file")"
  jq -n --arg issue "$issue_key" --arg branch "$branch" --arg done "$DAYFLOW_STATE_DONE_NAME" \
    '{issue:$issue,linear_state:$done,local:{},pull_request:{state:"MERGED",baseRefName:"develop",headRefName:$branch}}'
}
assert_failure 'dirty completed worktree makes cleanup fail closed' dayflow_supervisor_cleanup_completed
assert_failure 'clean completed worktree removed non-forced' test -e "$DAYFLOW_WORKTREE_ROOT/CEN-62"
assert_success 'dirty completed worktree preserved' test -e "$DAYFLOW_WORKTREE_ROOT/CEN-63/.git"
assert_success 'CEN-28 is always preserved' test -e "$DAYFLOW_WORKTREE_ROOT/CEN-28/.git"
assert_eq 'true' "$(jq -r '.worktree_cleaned' "$DAYFLOW_STATE_ROOT/CEN-62.json")" 'cleanup state proof persisted'
assert_failure 'cleanup sends no Discord delivery' rg -q 'discord' "$FAKE_CURL_LOG"

finish_tests 'dayflow_supervisor_test'
