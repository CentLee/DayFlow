#!/usr/bin/env bash

dayflow_create_test_repo() {
  local test_root="$1"
  local source_root="$2"
  local bare="$test_root/remote.git"
  local seed="$test_root/seed"
  mkdir -p "$seed/scripts/lib" "$seed/scripts/schemas" "$seed/.codex/agents" "$seed/docs"
  cp "$source_root/scripts/lib/dayflow_runner.sh" "$seed/scripts/lib/dayflow_runner.sh"
  cp "$source_root/scripts/schemas/dayflow-review.schema.json" "$seed/scripts/schemas/dayflow-review.schema.json"
  cp "$source_root/.codex/agents/integration-agent.md" "$seed/.codex/agents/integration-agent.md"
  cp "$source_root/.codex/agents/review-agent.md" "$seed/.codex/agents/review-agent.md"
  cp "$source_root/docs/review-checklist.md" "$seed/docs/review-checklist.md"
  printf '%s\n' '# test repo' >"$seed/README.md"
  git init --bare "$bare" >/dev/null
  git -C "$seed" init -b develop >/dev/null
  git -C "$seed" config user.name 'DayFlow Tests'
  git -C "$seed" config user.email 'dayflow-tests@example.invalid'
  git -C "$seed" add .
  git -C "$seed" commit -m 'test: seed develop' >/dev/null
  git -C "$seed" remote add origin "$bare"
  git -C "$seed" push -u origin develop >/dev/null
  git -C "$bare" symbolic-ref HEAD refs/heads/develop
  printf '%s\n' "$seed"
}

dayflow_export_fake_environment() {
  local test_root="$1"
  local source_root="$2"
  local seed="$3"
  export DAYFLOW_ROOT_DIR="$seed"
  export DAYFLOW_RUNTIME_DIR="$test_root/runtime"
  export DAYFLOW_WORKTREE_ROOT="$DAYFLOW_RUNTIME_DIR/worktrees"
  export DAYFLOW_STATE_ROOT="$DAYFLOW_RUNTIME_DIR/state"
  export DAYFLOW_LOG_ROOT="$DAYFLOW_RUNTIME_DIR/logs"
  export DAYFLOW_MERGE_READY_STORE="$DAYFLOW_STATE_ROOT/merge-ready.json"
  export DAYFLOW_LEGACY_RUNTIME_DIR="$test_root/legacy"
  export DAYFLOW_CODEX_BIN="$source_root/scripts/tests/fakes/codex"
  export DAYFLOW_GH_BIN="$source_root/scripts/tests/fakes/gh"
  export DAYFLOW_CURL_BIN="$source_root/scripts/tests/fakes/curl"
  export DAYFLOW_ISSUE_FIXTURE_FILE="$source_root/scripts/tests/fixtures/admissible-issue.json"
  export DAYFLOW_GITHUB_REPO_SLUG='test/dayflow'
  export DAYFLOW_STATE_IN_PROGRESS_ID='state-in-progress'
  export DAYFLOW_STATE_IN_REVIEW_ID='state-in-review'
  export DAYFLOW_STATE_DONE_ID='state-done'
  export DAYFLOW_STATE_BLOCKED_ID='state-blocked'
  export DAYFLOW_MONITOR_INTERVAL_SECONDS=0.1
  export DAYFLOW_EXECUTION_LIMIT_SECONDS=10
  export DAYFLOW_STALL_LIMIT_SECONDS=5
  export DAYFLOW_CI_POLL_INTERVAL_SECONDS=0.1
  export DAYFLOW_CI_WAIT_TIMEOUT_SECONDS=3
  export LINEAR_API_KEY='test-linear-key'
  export FAKE_CODEX_LOG="$test_root/codex.log"
  export FAKE_CODEX_REVIEW_COUNT_FILE="$test_root/review-count"
  export FAKE_GH_LOG="$test_root/gh.log"
  export FAKE_GH_READY_FILE="$test_root/gh-ready"
  export FAKE_CURL_LOG="$test_root/curl.log"
  export FAKE_GH_COMMENTS_LOG="$test_root/comments.log"
  export FAKE_GIT_ROOT="$seed"
  export FAKE_PR_BRANCH='feature/tasks-29-replace-symphony-with-dayflow-local-runner'
  unset FAKE_CODEX_INVOCATION_COUNT_FILE FAKE_CODEX_PARENT_PID_FILE FAKE_CODEX_CHILD_PID_FILE
  unset FAKE_GH_HEAD_SHA_OVERRIDE FAKE_GH_BASE_BRANCH FAKE_GH_MERGE_STATE FAKE_GH_CHECK_MODE FAKE_GH_PENDING_COUNT_FILE
  unset FAKE_LINEAR_FAIL_STATE FAKE_WEBHOOK_FAILURES_FILE FAKE_WEBHOOK_DELAY_SECONDS FAKE_GH_PR_STATE
  unset FAKE_REQUIRE_DRAFT_REVIEW FAKE_REVIEW_DRAFT_MARKER
}

dayflow_prepare_notification_fixture() {
  mkdir -p "$DAYFLOW_RUNTIME_DIR"
  printf '%s\n' 'DAYFLOW_DISCORD_WEBHOOK_URL=https://discord.test/webhook' >"$DAYFLOW_RUNTIME_DIR/notifications.env"
}
