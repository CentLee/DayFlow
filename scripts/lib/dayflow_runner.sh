#!/usr/bin/env bash

DAYFLOW_SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ROOT_DIR="${DAYFLOW_ROOT_DIR:-$(cd "$DAYFLOW_SCRIPT_DIR/.." && pwd)}"
DAYFLOW_RUNTIME_DIR="${DAYFLOW_RUNTIME_DIR:-$ROOT_DIR/.dayflow}"
DAYFLOW_WORKTREE_ROOT="${DAYFLOW_WORKTREE_ROOT:-$DAYFLOW_RUNTIME_DIR/worktrees}"
DAYFLOW_STATE_ROOT="${DAYFLOW_STATE_ROOT:-$DAYFLOW_RUNTIME_DIR/state}"
DAYFLOW_LOG_ROOT="${DAYFLOW_LOG_ROOT:-$DAYFLOW_RUNTIME_DIR/logs}"
DAYFLOW_GH_CONFIG_DIR="${GH_CONFIG_DIR:-$DAYFLOW_RUNTIME_DIR/gh}"
DAYFLOW_NOTIFICATIONS_ENV_FILE="${DAYFLOW_NOTIFICATIONS_ENV_FILE:-$DAYFLOW_RUNTIME_DIR/notifications.env}"
DAYFLOW_MERGE_READY_STORE="${DAYFLOW_MERGE_READY_STORE:-$DAYFLOW_STATE_ROOT/merge-ready.json}"
DAYFLOW_LEGACY_RUNTIME_DIR="${DAYFLOW_LEGACY_RUNTIME_DIR:-$ROOT_DIR/.symphony}"

DAYFLOW_LINEAR_API_URL="${DAYFLOW_LINEAR_API_URL:-https://api.linear.app/graphql}"
DAYFLOW_LINEAR_TEAM_ID="${DAYFLOW_LINEAR_TEAM_ID:-6f6e5287-d893-439d-981f-94d73ccd720a}"
DAYFLOW_STATE_TODO_NAME="${DAYFLOW_STATE_TODO_NAME:-Todo}"
DAYFLOW_STATE_IN_PROGRESS_NAME="${DAYFLOW_STATE_IN_PROGRESS_NAME:-In Progress}"
DAYFLOW_STATE_IN_REVIEW_NAME="${DAYFLOW_STATE_IN_REVIEW_NAME:-In Review}"
DAYFLOW_STATE_DONE_NAME="${DAYFLOW_STATE_DONE_NAME:-Done}"
DAYFLOW_STATE_BLOCKED_NAME="${DAYFLOW_STATE_BLOCKED_NAME:-Blocked}"

DAYFLOW_CODEX_BIN="${DAYFLOW_CODEX_BIN:-codex}"
DAYFLOW_GH_BIN="${DAYFLOW_GH_BIN:-gh}"
DAYFLOW_CURL_BIN="${DAYFLOW_CURL_BIN:-curl}"
DAYFLOW_EXECUTION_LIMIT_SECONDS="${DAYFLOW_EXECUTION_LIMIT_SECONDS:-1200}"
DAYFLOW_STALL_LIMIT_SECONDS="${DAYFLOW_STALL_LIMIT_SECONDS:-300}"
DAYFLOW_TOKEN_LIMIT="${DAYFLOW_TOKEN_LIMIT:-120000}"
DAYFLOW_MONITOR_INTERVAL_SECONDS="${DAYFLOW_MONITOR_INTERVAL_SECONDS:-2}"
DAYFLOW_CI_POLL_INTERVAL_SECONDS="${DAYFLOW_CI_POLL_INTERVAL_SECONDS:-5}"
DAYFLOW_CI_WAIT_TIMEOUT_SECONDS="${DAYFLOW_CI_WAIT_TIMEOUT_SECONDS:-600}"
DAYFLOW_DEFAULT_SANDBOX="${DAYFLOW_DEFAULT_SANDBOX:-workspace-write}"
DAYFLOW_DRY_RUN="${DAYFLOW_DRY_RUN:-false}"
DAYFLOW_ACTIVE_CODEX_PID=""
DAYFLOW_ACTIVE_CODEX_PGID=""

dayflow_error() {
  printf 'dayflow-runner: %s\n' "$*" >&2
}

dayflow_require_commands() {
  local command_name
  for command_name in "$@"; do
    if ! command -v "$command_name" >/dev/null 2>&1; then
      dayflow_error "required command not found: $command_name"
      return 1
    fi
  done
}

dayflow_validate_issue_key() {
  [[ "${1:-}" =~ ^CEN-[0-9]+$ ]]
}

dayflow_issue_number() {
  local issue_key="$1"
  dayflow_validate_issue_key "$issue_key" || return 1
  printf '%s\n' "${issue_key#CEN-}"
}

dayflow_slugify() {
  local value="$1"
  value="$(printf '%s' "$value" | sed -E 's/^\[[^]]+\][[:space:]]*//')"
  printf '%s' "$value" |
    tr '[:upper:]' '[:lower:]' |
    sed -E 's/[^a-z0-9]+/-/g; s/^-+//; s/-+$//' |
    cut -c1-64 |
    sed -E 's/-+$//'
}

dayflow_branch_name() {
  local issue_key="$1"
  local title="$2"
  local number slug
  number="$(dayflow_issue_number "$issue_key")" || return 1
  slug="$(dayflow_slugify "$title")"
  [[ -n "$slug" ]] || slug="issue"
  printf 'feature/tasks-%s-%s\n' "$number" "$slug"
}

dayflow_model_for_agent() {
  case "$1" in
    product-agent|integration-agent|review-agent)
      printf 'gpt-5.6-sol high\n'
      ;;
    backend-agent|ios-agent)
      printf 'gpt-5.6-terra medium\n'
      ;;
    *)
      return 1
      ;;
  esac
}

dayflow_now_iso() {
  date -u +%Y-%m-%dT%H:%M:%SZ
}

dayflow_state_file() {
  printf '%s/%s.json\n' "$DAYFLOW_STATE_ROOT" "$1"
}

dayflow_state_update() {
  local issue_key="$1"
  shift
  local state_file tmp_file
  state_file="$(dayflow_state_file "$issue_key")"
  tmp_file="${state_file}.tmp.$$"
  [[ -f "$state_file" ]] || printf '{}\n' >"$state_file"
  jq "$@" "$state_file" >"$tmp_file"
  mv "$tmp_file" "$state_file"
}

dayflow_state_value() {
  local issue_key="$1"
  local expression="$2"
  local state_file
  state_file="$(dayflow_state_file "$issue_key")"
  [[ -f "$state_file" ]] || return 1
  jq -r "$expression" "$state_file"
}

dayflow_initialize_runtime() {
  mkdir -p "$DAYFLOW_WORKTREE_ROOT" "$DAYFLOW_STATE_ROOT" "$DAYFLOW_LOG_ROOT"
  chmod 700 "$DAYFLOW_RUNTIME_DIR" "$DAYFLOW_STATE_ROOT" "$DAYFLOW_LOG_ROOT" 2>/dev/null || true
  dayflow_migrate_legacy_runtime
}

dayflow_migrate_legacy_runtime() {
  local legacy_gh="$DAYFLOW_LEGACY_RUNTIME_DIR/gh"
  local legacy_notifications="$DAYFLOW_LEGACY_RUNTIME_DIR/notifications.env"
  local legacy_merge_ready="$DAYFLOW_LEGACY_RUNTIME_DIR/artifacts/merge_ready_notifications.json"

  if [[ ! -e "$DAYFLOW_GH_CONFIG_DIR" && -d "$legacy_gh" ]]; then
    cp -R "$legacy_gh" "$DAYFLOW_GH_CONFIG_DIR"
  fi
  if [[ ! -e "$DAYFLOW_NOTIFICATIONS_ENV_FILE" && -f "$legacy_notifications" ]]; then
    cp "$legacy_notifications" "$DAYFLOW_NOTIFICATIONS_ENV_FILE"
    chmod 600 "$DAYFLOW_NOTIFICATIONS_ENV_FILE" 2>/dev/null || true
  fi
  if [[ ! -e "$DAYFLOW_MERGE_READY_STORE" && -f "$legacy_merge_ready" ]]; then
    cp "$legacy_merge_ready" "$DAYFLOW_MERGE_READY_STORE"
  fi
  [[ -f "$DAYFLOW_MERGE_READY_STORE" ]] || printf '{}\n' >"$DAYFLOW_MERGE_READY_STORE"
  dayflow_normalize_merge_ready_store
}

dayflow_normalize_merge_ready_store() {
  local tmp_file="${DAYFLOW_MERGE_READY_STORE}.tmp.$$"
  jq '
    reduce to_entries[] as $entry ({};
      if ($entry.key | test("^CEN-[0-9]+$")) then
        .[$entry.key] = $entry.value
      elif (($entry.value | type) == "object") and
           ((($entry.value.issue_key // $entry.value.identifier // "") | test("^CEN-[0-9]+$"))) then
        ($entry.value.issue_key // $entry.value.identifier) as $issue_key
        | .[$issue_key] = ($entry.value + {
          pr_number: ($entry.value.pr_number // ($entry.key | tonumber?))
        })
      else
        .[$entry.key] = $entry.value
      end
    )
  ' "$DAYFLOW_MERGE_READY_STORE" >"$tmp_file"
  mv "$tmp_file" "$DAYFLOW_MERGE_READY_STORE"
}

dayflow_acquire_lock() {
  local issue_key="$1"
  local lock_dir="$DAYFLOW_STATE_ROOT/${issue_key}.lock"
  local existing_pid=""

  if mkdir "$lock_dir" 2>/dev/null; then
    printf '%s\n' "$$" >"$lock_dir/pid"
    DAYFLOW_ACTIVE_LOCK_DIR="$lock_dir"
    return 0
  fi

  [[ -f "$lock_dir/pid" ]] && existing_pid="$(<"$lock_dir/pid")"
  if [[ "$existing_pid" =~ ^[0-9]+$ ]] && kill -0 "$existing_pid" 2>/dev/null; then
    dayflow_error "$issue_key is already running under pid $existing_pid"
    return 1
  fi

  rm -f "$lock_dir/pid"
  rmdir "$lock_dir" 2>/dev/null || {
    dayflow_error "unable to recover stale lock for $issue_key"
    return 1
  }
  mkdir "$lock_dir"
  printf '%s\n' "$$" >"$lock_dir/pid"
  DAYFLOW_ACTIVE_LOCK_DIR="$lock_dir"
}

dayflow_release_lock() {
  if [[ -n "${DAYFLOW_ACTIVE_LOCK_DIR:-}" && -d "$DAYFLOW_ACTIVE_LOCK_DIR" ]]; then
    rm -f "$DAYFLOW_ACTIVE_LOCK_DIR/pid"
    rmdir "$DAYFLOW_ACTIVE_LOCK_DIR" 2>/dev/null || true
  fi
  DAYFLOW_ACTIVE_LOCK_DIR=""
}

dayflow_exit_cleanup() {
  local status=$?
  trap - EXIT INT TERM
  dayflow_stop_active_codex
  dayflow_release_lock
  exit "$status"
}

dayflow_install_cleanup_traps() {
  trap dayflow_exit_cleanup EXIT
  trap 'exit 130' INT
  trap 'exit 143' TERM
}

dayflow_linear_graphql() {
  local query="$1"
  [[ -n "${LINEAR_API_KEY:-}" ]] || {
    dayflow_error "LINEAR_API_KEY is required"
    return 1
  }
  "$DAYFLOW_CURL_BIN" -fsS "$DAYFLOW_LINEAR_API_URL" \
    -H 'Content-Type: application/json' \
    -H "Authorization: ${LINEAR_API_KEY}" \
    --data "$(jq -n --arg query "$query" '{query: $query}')"
}

dayflow_linear_issue() {
  local issue_key="$1"
  local fixture_file="${DAYFLOW_ISSUE_FIXTURE_FILE:-}"
  local response

  if [[ -n "$fixture_file" ]]; then
    jq -c '.' "$fixture_file"
    return
  fi

  response="$(dayflow_linear_graphql "query { issue(id: \"${issue_key}\") { id identifier title description state { id name } } }")" || return 1
  if jq -e '.errors | length > 0' >/dev/null 2>&1 <<<"$response"; then
    jq -r '.errors[].message' <<<"$response" >&2
    return 1
  fi
  jq -ce '.data.issue | select(. != null)' <<<"$response"
}

dayflow_linear_state_id() {
  local state_name="$1"
  local configured=""
  local response
  case "$state_name" in
    "$DAYFLOW_STATE_TODO_NAME") configured="${DAYFLOW_STATE_TODO_ID:-}" ;;
    "$DAYFLOW_STATE_IN_PROGRESS_NAME") configured="${DAYFLOW_STATE_IN_PROGRESS_ID:-}" ;;
    "$DAYFLOW_STATE_IN_REVIEW_NAME") configured="${DAYFLOW_STATE_IN_REVIEW_ID:-}" ;;
    "$DAYFLOW_STATE_DONE_NAME") configured="${DAYFLOW_STATE_DONE_ID:-}" ;;
    "$DAYFLOW_STATE_BLOCKED_NAME") configured="${DAYFLOW_STATE_BLOCKED_ID:-}" ;;
  esac
  if [[ -n "$configured" ]]; then
    printf '%s\n' "$configured"
    return 0
  fi

  response="$(dayflow_linear_graphql "query { team(id: \"${DAYFLOW_LINEAR_TEAM_ID}\") { states { nodes { id name } } } }")" || return 1
  jq -er --arg name "$state_name" '.data.team.states.nodes[] | select(.name == $name) | .id' <<<"$response" | head -n 1
}

dayflow_linear_set_state() {
  local issue_id="$1"
  local state_name="$2"
  local state_id response
  if [[ "$DAYFLOW_DRY_RUN" == "true" ]]; then
    printf 'dry-run: Linear %s -> %s\n' "$issue_id" "$state_name"
    return 0
  fi
  state_id="$(dayflow_linear_state_id "$state_name")" || return 1
  response="$(dayflow_linear_graphql "mutation { issueUpdate(id: \"${issue_id}\", input: {stateId: \"${state_id}\"}) { success } }")" || return 1
  jq -e '.data.issueUpdate.success == true' >/dev/null <<<"$response"
}

dayflow_load_notifications() {
  if [[ -f "$DAYFLOW_NOTIFICATIONS_ENV_FILE" ]]; then
    # shellcheck disable=SC1090
    source "$DAYFLOW_NOTIFICATIONS_ENV_FILE"
  fi
}

dayflow_notify() {
  local title="$1"
  local body="$2"
  local color="${3:-3447003}"
  local payload
  [[ "$DAYFLOW_DRY_RUN" == "false" ]] || return 0
  dayflow_load_notifications
  [[ -n "${DAYFLOW_DISCORD_WEBHOOK_URL:-}" ]] || return 1
  payload="$(jq -n --arg title "$title" --arg description "$body" --argjson color "$color" \
    '{embeds: [{title: $title, description: $description, color: $color}]}')"
  "$DAYFLOW_CURL_BIN" -fsS -X POST "$DAYFLOW_DISCORD_WEBHOOK_URL" \
    -H 'Content-Type: application/json' --data "$payload" >/dev/null
}

dayflow_notify_state() {
  local issue_key="$1"
  local state_name="$2"
  local detail="$3"
  local color=3447003
  case "$state_name" in
    "$DAYFLOW_STATE_IN_PROGRESS_NAME") color=16753920 ;;
    "$DAYFLOW_STATE_IN_REVIEW_NAME") color=5814783 ;;
    "$DAYFLOW_STATE_DONE_NAME") color=5763719 ;;
    "$DAYFLOW_STATE_BLOCKED_NAME") color=15158332 ;;
  esac
  dayflow_notify "DayFlow ${issue_key} -> ${state_name}" "$detail" "$color" || true
}

dayflow_extract_section() {
  local description="$1"
  local requested="$2"
  printf '%s\n' "$description" | awk -v requested="$requested" '
    function normalized(line) {
      sub(/^[[:space:]]*#+[[:space:]]*/, "", line)
      sub(/:[[:space:]]*$/, "", line)
      return line
    }
    {
      current = normalized($0)
      if (!found && current == requested) { found = 1; next }
      if (found && ($0 ~ /^[[:space:]]*#+[[:space:]]+/ || $0 ~ /^[A-Z][A-Za-z -]+:[[:space:]]*$/)) { exit }
      if (found) print
    }
  ' | sed -E '/^[[:space:]]*$/d'
}

dayflow_primary_agent() {
  local description="$1"
  dayflow_extract_section "$description" 'Primary Agent' |
    head -n 1 |
    sed -E 's/^[[:space:]-]+//; s/[`*]//g; s/[[:space:]]+$//'
}

dayflow_validate_admission() {
  local issue_json="$1"
  local title description primary section content done_count
  title="$(jq -r '.title // ""' <<<"$issue_json")"
  description="$(jq -r '.description // ""' <<<"$issue_json")"
  [[ "$title" =~ ^\[[^]]+\][[:space:]]+.+ ]] || {
    dayflow_error 'issue title must follow [Agent] description'
    return 1
  }
  for section in 'Goal' 'Primary Agent' 'Inputs' 'Done When' 'Out of Scope'; do
    content="$(dayflow_extract_section "$description" "$section")"
    [[ -n "$content" ]] || {
      dayflow_error "missing or empty issue section: $section"
      return 1
    }
  done
  primary="$(dayflow_primary_agent "$description")"
  dayflow_model_for_agent "$primary" >/dev/null || {
    dayflow_error "unsupported Primary Agent: $primary"
    return 1
  }
  done_count="$(dayflow_extract_section "$description" 'Done When' | awk '/^[[:space:]]*[-*][[:space:]]+/ {count++} END {print count+0}')"
  (( done_count >= 2 && done_count <= 5 )) || {
    dayflow_error 'Done When must contain 2 to 5 checks'
    return 1
  }
}

dayflow_github_repo() {
  if [[ -n "${DAYFLOW_GITHUB_REPO_SLUG:-}" ]]; then
    printf '%s\n' "$DAYFLOW_GITHUB_REPO_SLUG"
    return
  fi
  git -C "$ROOT_DIR" remote get-url origin |
    sed -E 's#^(git@github.com:|https://github.com/)##; s#\.git$##'
}

dayflow_gh() {
  GH_CONFIG_DIR="$DAYFLOW_GH_CONFIG_DIR" "$DAYFLOW_GH_BIN" "$@"
}

dayflow_agent_definition() {
  local agent="$1"
  local path="$ROOT_DIR/.codex/agents/${agent}.md"
  [[ -f "$path" ]] || {
    dayflow_error "agent definition not found: $path"
    return 1
  }
  sed -n '1,260p' "$path"
}

dayflow_issue_prompt() {
  local issue_json="$1"
  local agent="$2"
  local issue_key title description
  issue_key="$(jq -r '.identifier' <<<"$issue_json")"
  title="$(jq -r '.title' <<<"$issue_json")"
  description="$(jq -r '.description' <<<"$issue_json")"
  cat <<EOF
You are the primary ${agent} for ${issue_key} in DayFlow.

Own this issue through implementation, tests, commit, push, a ready PR targeting develop, proof-of-work completion, and review follow-up. Work only in the current issue branch. Do not merge the PR. Keep secrets and runtime artifacts out of git.

Issue title: ${title}

Issue description:
${description}

Agent definition:
$(dayflow_agent_definition "$agent")

Required PR proof headings:
- Changed files
- Behavior implemented
- Tests run
- Review feedback addressed
- Complexity snapshot
- Risks or follow-ups
- Next suggested issue
EOF
}

dayflow_review_prompt() {
  local issue_key="$1"
  cat <<EOF
Review the current ${issue_key} branch against origin/develop. Follow the repository review-agent definition and docs/review-checklist.md. Do not edit files. Return only the requested structured review result. Classify actionable findings as P0, P1, P2, or P3. P0-P2 block merge readiness.

Review agent definition:
$(dayflow_agent_definition review-agent)

Review checklist:
$(sed -n '1,260p' "$ROOT_DIR/docs/review-checklist.md")
EOF
}

dayflow_prepare_new_worktree() {
  local issue_key="$1"
  local branch="$2"
  local worktree="$DAYFLOW_WORKTREE_ROOT/$issue_key"
  [[ ! -e "$worktree" ]] || {
    dayflow_error "new Todo issue already has a worktree: $worktree"
    return 1
  }
  git -C "$ROOT_DIR" fetch origin develop
  if git -C "$ROOT_DIR" show-ref --verify --quiet "refs/heads/$branch"; then
    dayflow_error "new Todo issue already has local branch: $branch"
    return 1
  fi
  git -C "$ROOT_DIR" worktree add -b "$branch" "$worktree" origin/develop >&2
  printf '%s\n' "$worktree"
}

dayflow_validate_resume_state() {
  local issue_key="$1"
  local expected_branch="$2"
  local expected_agent="$3"
  local expected_model="$4"
  local expected_reasoning="$5"
  local state_file worktree branch session_id persisted_agent persisted_model persisted_reasoning
  state_file="$(dayflow_state_file "$issue_key")"
  [[ -f "$state_file" ]] || {
    dayflow_error "$issue_key cannot resume without local state"
    return 1
  }
  worktree="$(jq -r '.worktree // ""' "$state_file")"
  session_id="$(jq -r '.session_id // ""' "$state_file")"
  persisted_agent="$(jq -r '.primary_agent // ""' "$state_file")"
  persisted_model="$(jq -r '.model // ""' "$state_file")"
  persisted_reasoning="$(jq -r '.reasoning // ""' "$state_file")"
  [[ -n "$worktree" && -e "$worktree/.git" && -n "$session_id" ]] || {
    dayflow_error "$issue_key resume state lacks a valid worktree or session"
    return 1
  }
  branch="$(git -C "$worktree" branch --show-current)"
  [[ "$branch" == "$expected_branch" ]] || {
    dayflow_error "$issue_key resume branch mismatch: $branch"
    return 1
  }
  [[ "$persisted_agent" == "$expected_agent" && "$persisted_model" == "$expected_model" && "$persisted_reasoning" == "$expected_reasoning" ]] || {
    dayflow_error "$issue_key resume ownership metadata no longer matches Linear routing"
    return 1
  }
  printf '%s\n' "$worktree"
}

dayflow_jsonl_tokens() {
  local log_file="$1"
  [[ -s "$log_file" ]] || {
    printf '0\n'
    return
  }
  jq -R -s '
    split("\n") | map(fromjson? // empty)
    | [ .[]
      | (.usage // .token_usage // .response.usage // .event.usage // .item.usage // empty)
      | (
          .total_tokens // .totalTokens //
          ((.input_tokens // .inputTokens // .prompt_tokens // .promptTokens // 0) +
           (.output_tokens // .outputTokens // .completion_tokens // .completionTokens // 0))
        )
    ] | add // 0
  ' "$log_file" 2>/dev/null || printf '0\n'
}

dayflow_jsonl_session_id() {
  local log_file="$1"
  jq -R -sr 'split("\n") | map(fromjson? // empty) | [.[] | select(.type == "thread.started" or .type == "thread_started") | (.thread_id // .threadId // .id)] | map(select(. != null)) | first // empty' "$log_file" 2>/dev/null
}

dayflow_descendant_pids() {
  local parent_pid="$1"
  local child_pid
  while IFS= read -r child_pid; do
    [[ "$child_pid" =~ ^[0-9]+$ ]] || continue
    dayflow_descendant_pids "$child_pid"
    printf '%s\n' "$child_pid"
  done < <(pgrep -P "$parent_pid" 2>/dev/null || true)
}

dayflow_stop_process_tree() {
  local pid="$1"
  local runner_pgid target_pgid descendant
  [[ "$pid" =~ ^[0-9]+$ ]] || return 0
  kill -0 "$pid" 2>/dev/null || return 0

  runner_pgid="$(ps -o pgid= -p $$ 2>/dev/null | tr -d ' ')"
  target_pgid="$(ps -o pgid= -p "$pid" 2>/dev/null | tr -d ' ')"
  if [[ -n "$target_pgid" && "$target_pgid" != "$runner_pgid" ]]; then
    kill -TERM -- "-$target_pgid" 2>/dev/null || true
  else
    while IFS= read -r descendant; do
      kill -TERM "$descendant" 2>/dev/null || true
    done < <(dayflow_descendant_pids "$pid")
    kill -TERM "$pid" 2>/dev/null || true
  fi

  local attempts=0
  while kill -0 "$pid" 2>/dev/null && (( attempts < 10 )); do
    sleep 0.2
    attempts=$((attempts + 1))
  done
  if kill -0 "$pid" 2>/dev/null; then
    if [[ -n "$target_pgid" && "$target_pgid" != "$runner_pgid" ]]; then
      kill -KILL -- "-$target_pgid" 2>/dev/null || true
    else
      while IFS= read -r descendant; do
        kill -KILL "$descendant" 2>/dev/null || true
      done < <(dayflow_descendant_pids "$pid")
      kill -KILL "$pid" 2>/dev/null || true
    fi
  fi
}

dayflow_stop_active_codex() {
  local pid="${DAYFLOW_ACTIVE_CODEX_PID:-}"
  if [[ -n "$pid" ]]; then
    dayflow_stop_process_tree "$pid"
  fi
  DAYFLOW_ACTIVE_CODEX_PID=""
  DAYFLOW_ACTIVE_CODEX_PGID=""
}

dayflow_codex_command() {
  local mode="$1"
  local worktree="$2"
  local model="$3"
  local reasoning="$4"
  local session_id="$5"
  local prompt_file="$6"
  local output_file="$7"
  local schema="$ROOT_DIR/scripts/schemas/dayflow-review.schema.json"
  local common=(--json -m "$model" -c "model_reasoning_effort=\"$reasoning\"" -c 'approval_policy="never"')

  case "$mode" in
    primary-new)
      "$DAYFLOW_CODEX_BIN" exec "${common[@]}" -s "$DAYFLOW_DEFAULT_SANDBOX" -C "$worktree" -o "$output_file" - <"$prompt_file"
      ;;
    primary-resume)
      (
        cd "$worktree"
        "$DAYFLOW_CODEX_BIN" exec resume "${common[@]}" -c "sandbox_mode=\"$DAYFLOW_DEFAULT_SANDBOX\"" -o "$output_file" "$session_id" - <"$prompt_file"
      )
      ;;
    review)
      "$DAYFLOW_CODEX_BIN" exec "${common[@]}" -s read-only -C "$worktree" --output-schema "$schema" -o "$output_file" - <"$prompt_file"
      ;;
    *)
      dayflow_error "unknown Codex mode: $mode"
      return 2
      ;;
  esac
}

dayflow_execute_bounded() {
  local issue_key="$1"
  local mode="$2"
  local worktree="$3"
  local model="$4"
  local reasoning="$5"
  local session_id="$6"
  local prompt_file="$7"
  local log_file="$8"
  local output_file="$9"
  local started_at now last_progress last_size=0 size elapsed invocation_tokens aggregate_tokens pid rc=0 limit_reason=""

  aggregate_tokens="$(dayflow_state_value "$issue_key" '.tokens_used // 0' 2>/dev/null || printf '0')"
  if (( aggregate_tokens >= DAYFLOW_TOKEN_LIMIT )); then
    DAYFLOW_EXECUTION_ERROR="token limit reached before launch (${DAYFLOW_TOKEN_LIMIT})"
    export DAYFLOW_EXECUTION_ERROR
    return 124
  fi

  : >"$log_file"
  started_at="$(date +%s)"
  last_progress="$started_at"
  (
    trap - EXIT INT TERM
    dayflow_codex_command "$mode" "$worktree" "$model" "$reasoning" "$session_id" "$prompt_file" "$output_file"
  ) >"$log_file" 2>&1 &
  pid=$!
  DAYFLOW_ACTIVE_CODEX_PID="$pid"
  DAYFLOW_ACTIVE_CODEX_PGID="$(ps -o pgid= -p "$pid" 2>/dev/null | tr -d ' ')"

  while kill -0 "$pid" 2>/dev/null; do
    sleep "$DAYFLOW_MONITOR_INTERVAL_SECONDS"
    if ! kill -0 "$pid" 2>/dev/null; then
      break
    fi
    now="$(date +%s)"
    size="$(wc -c <"$log_file" | tr -d ' ')"
    if [[ "$size" != "$last_size" ]]; then
      last_size="$size"
      last_progress="$now"
      dayflow_state_update "$issue_key" --argjson at "$now" '.last_progress_epoch = $at'
    fi
    elapsed=$((now - started_at))
    invocation_tokens="$(dayflow_jsonl_tokens "$log_file")"
    aggregate_tokens="$(dayflow_state_value "$issue_key" '.tokens_used // 0' 2>/dev/null || printf '0')"
    if (( aggregate_tokens + invocation_tokens >= DAYFLOW_TOKEN_LIMIT )); then
      limit_reason="token limit exceeded (${DAYFLOW_TOKEN_LIMIT})"
    elif (( now - last_progress >= DAYFLOW_STALL_LIMIT_SECONDS )); then
      limit_reason="no progress for ${DAYFLOW_STALL_LIMIT_SECONDS}s"
    elif (( elapsed >= DAYFLOW_EXECUTION_LIMIT_SECONDS )); then
      limit_reason="execution limit exceeded (${DAYFLOW_EXECUTION_LIMIT_SECONDS}s)"
    fi
    if [[ -n "$limit_reason" ]]; then
      dayflow_stop_active_codex
      break
    fi
  done

  if [[ -z "$limit_reason" ]]; then
    if wait "$pid"; then rc=0; else rc=$?; fi
    DAYFLOW_ACTIVE_CODEX_PID=""
    DAYFLOW_ACTIVE_CODEX_PGID=""
  else
    wait "$pid" 2>/dev/null || true
    rc=124
  fi

  invocation_tokens="$(dayflow_jsonl_tokens "$log_file")"
  aggregate_tokens="$(dayflow_state_value "$issue_key" '.tokens_used // 0' 2>/dev/null || printf '0')"
  aggregate_tokens=$((aggregate_tokens + invocation_tokens))
  dayflow_state_update "$issue_key" \
    --argjson tokens "$aggregate_tokens" \
    --arg at "$(dayflow_now_iso)" \
    '.tokens_used = $tokens | .updated_at = $at'

  if [[ -z "$limit_reason" && "$rc" == "0" ]] && (( aggregate_tokens >= DAYFLOW_TOKEN_LIMIT )); then
    limit_reason="token limit exceeded after process exit (${DAYFLOW_TOKEN_LIMIT})"
    rc=124
  fi

  if [[ -n "$limit_reason" ]]; then
    DAYFLOW_EXECUTION_ERROR="$limit_reason"
  elif (( rc != 0 )); then
    if rg -qi 'model.*(not found|unsupported|unavailable|access|invalid)|unknown model' "$log_file"; then
      DAYFLOW_EXECUTION_ERROR="model rejected: $model"
    else
      DAYFLOW_EXECUTION_ERROR="Codex exited with status $rc"
    fi
  else
    DAYFLOW_EXECUTION_ERROR=""
  fi
  export DAYFLOW_EXECUTION_ERROR
  return "$rc"
}

dayflow_block_issue() {
  local issue_json="$1"
  local reason="$2"
  local issue_key issue_id
  issue_key="$(jq -r '.identifier' <<<"$issue_json")"
  issue_id="$(jq -r '.id' <<<"$issue_json")"
  if [[ "$DAYFLOW_DRY_RUN" == "false" ]]; then
    dayflow_state_update "$issue_key" --arg reason "$reason" --arg at "$(dayflow_now_iso)" \
      '.status = "blocked" | .last_error = $reason | .updated_at = $at'
  fi
  if ! dayflow_linear_set_state "$issue_id" "$DAYFLOW_STATE_BLOCKED_NAME"; then
    dayflow_error "Linear has no usable Blocked state; local state remains fail-closed"
  fi
  dayflow_notify_state "$issue_key" "$DAYFLOW_STATE_BLOCKED_NAME" "$reason"
}

dayflow_pr_for_branch() {
  local branch="$1"
  local state="${2:-open}"
  local repo
  repo="$(dayflow_github_repo)"
  dayflow_gh pr list -R "$repo" --head "$branch" --state "$state" --limit 1 \
    --json number,url,isDraft,state,headRefName,headRefOid,baseRefName,mergeStateStatus,body
}

dayflow_validate_proof() {
  local body="$1"
  local heading section
  for heading in 'Changed files' 'Behavior implemented' 'Tests run' 'Review feedback addressed' 'Complexity snapshot' 'Risks or follow-ups' 'Next suggested issue'; do
    section="$(printf '%s\n' "$body" | awk -v heading="## $heading" '
      $0 == heading {found=1; next}
      found && /^## / {exit}
      found {print}
    ' | sed -E '/^[[:space:]]*$/d; /^[[:space:]]*-[[:space:]]*$/d')"
    [[ -n "$section" ]] || {
      dayflow_error "PR proof section is missing or empty: $heading"
      return 1
    }
  done
}

dayflow_validate_delivery() {
  local issue_key="$1"
  local branch="$2"
  local worktree="$3"
  local current_branch commit_count local_head remote_head remote_sha pr_head prs pr_json body
  current_branch="$(git -C "$worktree" branch --show-current)"
  [[ "$current_branch" == "$branch" ]] || {
    dayflow_error "delivery branch mismatch: $current_branch"
    return 1
  }
  commit_count="$(git -C "$worktree" rev-list --count origin/develop..HEAD)"
  (( commit_count > 0 )) || {
    dayflow_error 'delivery has no commits beyond origin/develop'
    return 1
  }
  remote_head="$(git -C "$worktree" ls-remote --heads origin "refs/heads/$branch")"
  [[ -n "$remote_head" ]] || {
    dayflow_error 'delivery branch has not been pushed'
    return 1
  }
  local_head="$(git -C "$worktree" rev-parse HEAD)"
  remote_sha="$(awk 'NR == 1 {print $1}' <<<"$remote_head")"
  prs="$(dayflow_pr_for_branch "$branch" open)"
  pr_json="$(jq -ce '.[0] | select(.baseRefName == "develop")' <<<"$prs")" || {
    dayflow_error 'delivery has no open PR targeting develop'
    return 1
  }
  pr_head="$(jq -r '.headRefOid // ""' <<<"$pr_json")"
  [[ -n "$pr_head" && "$local_head" == "$remote_sha" && "$remote_sha" == "$pr_head" ]] || {
    dayflow_error "delivery head mismatch: local=${local_head} remote=${remote_sha} pr=${pr_head}"
    return 1
  }
  body="$(jq -r '.body // ""' <<<"$pr_json")"
  dayflow_validate_proof "$body" || return 1
  printf '%s\n' "$pr_json"
}

dayflow_review_has_blockers() {
  local review_file="$1"
  jq -e '[.findings[]? | select(.severity == "P0" or .severity == "P1" or .severity == "P2")] | length > 0' "$review_file" >/dev/null
}

dayflow_publish_review_result() {
  local pr_number="$1"
  local review_file="$2"
  local comment_file="$3"
  local review_round="$4"
  local outcome="$5"
  local repo
  repo="$(dayflow_github_repo)"
  {
    printf '## Automated review round %s\n\n' "$review_round"
    printf '**Outcome:** %s\n\n' "$outcome"
    if [[ "$(jq '.findings | length' "$review_file")" == "0" ]]; then
      printf '### Findings\n\n- None.\n'
    else
      printf '### Findings\n\n'
      jq -r '.findings[] | "- **[\(.severity)] \(.title)**: \(.body)"' "$review_file"
    fi
    printf '\n### Residual risks\n\n'
    if [[ "$(jq '.residual_risks | length' "$review_file")" == "0" ]]; then
      printf '%s\n' '- None.'
    else
      jq -r '.residual_risks[] | "- " + .' "$review_file"
    fi
  } >"$comment_file"
  dayflow_gh pr comment -R "$repo" "$pr_number" --body-file "$comment_file" >/dev/null
}

dayflow_check_status() {
  local pr_number="$1"
  local repo checks count
  repo="$(dayflow_github_repo)"
  checks="$(dayflow_gh pr checks -R "$repo" "$pr_number" --json bucket,name,state 2>/dev/null)" || {
    printf 'pending\n'
    return 0
  }
  count="$(jq 'length' <<<"$checks")"
  if (( count == 0 )); then
    if [[ "${DAYFLOW_ALLOW_NO_CHECKS:-false}" == "true" ]]; then
      printf 'pass\n'
    else
      printf 'pending\n'
    fi
  elif jq -e 'any(.[]; .bucket == "fail" or .bucket == "cancel")' >/dev/null <<<"$checks"; then
    printf 'fail\n'
  elif jq -e 'all(.[]; .bucket == "pass" or .bucket == "skipping")' >/dev/null <<<"$checks"; then
    printf 'pass\n'
  else
    printf 'pending\n'
  fi
}

dayflow_checks_green() {
  local pr_number="$1"
  [[ "$(dayflow_check_status "$pr_number")" == "pass" ]]
}

dayflow_wait_for_ci() {
  local pr_number="$1"
  local started_at now check_status
  started_at="$(date +%s)"
  while true; do
    check_status="$(dayflow_check_status "$pr_number")"
    case "$check_status" in
      pass) return 0 ;;
      fail)
        DAYFLOW_CI_WAIT_STATUS="failed"
        return 1
        ;;
    esac
    now="$(date +%s)"
    if (( now - started_at >= DAYFLOW_CI_WAIT_TIMEOUT_SECONDS )); then
      DAYFLOW_CI_WAIT_STATUS="timeout"
      return 124
    fi
    sleep "$DAYFLOW_CI_POLL_INTERVAL_SECONDS"
  done
}

dayflow_has_requested_changes() {
  local pr_number="$1"
  local repo detail
  repo="$(dayflow_github_repo)"
  detail="$(dayflow_gh pr view -R "$repo" "$pr_number" --json reviews,commits)"
  jq -e '
    ((.commits | last | .committedDate) // "") as $latest
    | (.reviews // [] | map(select(.submittedAt != null and .author.login != null and .state != "COMMENTED"))
      | sort_by(.submittedAt) | group_by(.author.login) | map(last)
      | map(select(.submittedAt >= $latest)) | any(.state == "CHANGES_REQUESTED"))
  ' >/dev/null <<<"$detail"
}

dayflow_record_merge_ready() {
  local issue_key="$1"
  local pr_number="$2"
  local pr_url="$3"
  local head_sha="$4"
  local existing tmp
  existing="$(jq -r --arg key "$issue_key" --arg pr "$pr_number" '.[$key].head_sha? // .[$pr].head_sha? // ""' "$DAYFLOW_MERGE_READY_STORE")"
  [[ "$existing" != "$head_sha" ]] || return 0
  dayflow_notify "DayFlow ${issue_key} merge-ready" "PR #${pr_number} is ready to merge.\n${pr_url}" 5763719 || return 1
  tmp="${DAYFLOW_MERGE_READY_STORE}.tmp.$$"
  jq --arg key "$issue_key" --arg sha "$head_sha" --argjson pr "$pr_number" --arg at "$(dayflow_now_iso)" \
    '.[$key] = {head_sha: $sha, pr_number: $pr, notified_at: $at}' "$DAYFLOW_MERGE_READY_STORE" >"$tmp"
  mv "$tmp" "$DAYFLOW_MERGE_READY_STORE"
}

dayflow_reconcile_one() {
  local issue_key="$1"
  local state_file issue_json issue_id branch prs pr_json pr_number pr_url head_sha reviewed_head_sha
  local is_draft pr_state current_state base_branch head_branch merge_state
  state_file="$(dayflow_state_file "$issue_key")"
  [[ -f "$state_file" ]] || {
    dayflow_error "no local state for $issue_key"
    return 1
  }
  issue_json="$(dayflow_linear_issue "$issue_key")" || return 1
  issue_id="$(jq -r '.id' <<<"$issue_json")"
  current_state="$(jq -r '.state.name' <<<"$issue_json")"
  branch="$(jq -r '.branch // ""' "$state_file")"
  [[ -n "$branch" ]] || return 0
  prs="$(dayflow_pr_for_branch "$branch" all)"
  pr_json="$(jq -c '.[0] // empty' <<<"$prs")"
  [[ -n "$pr_json" ]] || return 0
  pr_number="$(jq -r '.number' <<<"$pr_json")"
  pr_url="$(jq -r '.url' <<<"$pr_json")"
  head_sha="$(jq -r '.headRefOid // ""' <<<"$pr_json")"
  is_draft="$(jq -r '.isDraft' <<<"$pr_json")"
  pr_state="$(jq -r '.state' <<<"$pr_json")"
  base_branch="$(jq -r '.baseRefName // ""' <<<"$pr_json")"
  head_branch="$(jq -r '.headRefName // ""' <<<"$pr_json")"
  merge_state="$(jq -r '.mergeStateStatus // "UNKNOWN"' <<<"$pr_json")"
  reviewed_head_sha="$(jq -r '.reviewed_head_sha // ""' "$state_file")"

  [[ "$base_branch" == "develop" && "$head_branch" == "$branch" ]] || {
    dayflow_error "$issue_key PR is not the tracked develop delivery"
    return 1
  }

  if [[ "$pr_state" == "MERGED" ]]; then
    if [[ "$current_state" != "$DAYFLOW_STATE_DONE_NAME" ]]; then
      dayflow_linear_set_state "$issue_id" "$DAYFLOW_STATE_DONE_NAME"
      dayflow_notify_state "$issue_key" "$DAYFLOW_STATE_DONE_NAME" "PR #${pr_number} merged into develop."
    fi
    dayflow_state_update "$issue_key" --arg at "$(dayflow_now_iso)" '.status = "done" | .updated_at = $at'
    return 0
  fi

  if dayflow_has_requested_changes "$pr_number"; then
    if [[ "$is_draft" != "true" ]]; then
      dayflow_gh pr ready -R "$(dayflow_github_repo)" --undo "$pr_number" >/dev/null
    fi
    dayflow_linear_set_state "$issue_id" "$DAYFLOW_STATE_IN_PROGRESS_NAME"
    dayflow_state_update "$issue_key" --arg at "$(dayflow_now_iso)" '.status = "review-changes" | .updated_at = $at'
    return 0
  fi

  if [[ -z "$reviewed_head_sha" || "$head_sha" != "$reviewed_head_sha" ]]; then
    if [[ "$is_draft" != "true" ]]; then
      dayflow_gh pr ready -R "$(dayflow_github_repo)" --undo "$pr_number" >/dev/null
    fi
    [[ "$current_state" == "$DAYFLOW_STATE_IN_PROGRESS_NAME" ]] || dayflow_linear_set_state "$issue_id" "$DAYFLOW_STATE_IN_PROGRESS_NAME"
    dayflow_state_update "$issue_key" --arg head "$head_sha" --arg at "$(dayflow_now_iso)" \
      '.status = "review-required" | .unreviewed_head_sha = $head | .updated_at = $at'
    return 0
  fi

  if [[ "$is_draft" == "true" ]]; then
    [[ "$current_state" == "$DAYFLOW_STATE_IN_PROGRESS_NAME" ]] || dayflow_linear_set_state "$issue_id" "$DAYFLOW_STATE_IN_PROGRESS_NAME"
    return 0
  fi

  [[ "$current_state" == "$DAYFLOW_STATE_IN_REVIEW_NAME" ]] || dayflow_linear_set_state "$issue_id" "$DAYFLOW_STATE_IN_REVIEW_NAME"
  dayflow_state_update "$issue_key" --argjson pr "$pr_number" --arg url "$pr_url" --arg at "$(dayflow_now_iso)" \
    '.status = "in-review" | .pr_number = $pr | .pr_url = $url | .updated_at = $at'
  if [[ "$merge_state" == "CLEAN" ]] && dayflow_checks_green "$pr_number"; then
    if dayflow_record_merge_ready "$issue_key" "$pr_number" "$pr_url" "$head_sha"; then
      dayflow_state_update "$issue_key" --arg at "$(dayflow_now_iso)" '.status = "merge-ready" | del(.last_error) | .updated_at = $at'
    else
      dayflow_state_update "$issue_key" --arg at "$(dayflow_now_iso)" \
        '.status = "merge-ready-notification-failed" | .last_error = "merge-ready webhook delivery failed" | .updated_at = $at'
      return 1
    fi
  fi
}

dayflow_run_issue() {
  local issue_key="$1"
  local issue_json issue_id title description linear_state primary model_route model reasoning branch worktree session_id mode
  local timestamp prompt_file log_file output_file pr_json pr_number review_prompt review_log review_output
  local review_round=1 findings_comment remediation_prompt remediation_log remediation_output repo

  dayflow_validate_issue_key "$issue_key" || {
    dayflow_error "invalid issue key: $issue_key"
    return 2
  }
  issue_json="$(dayflow_linear_issue "$issue_key")" || return 1
  if ! dayflow_validate_admission "$issue_json"; then
    if [[ "$DAYFLOW_DRY_RUN" == "false" ]]; then dayflow_block_issue "$issue_json" 'Issue failed admission validation.'; fi
    return 1
  fi
  issue_id="$(jq -r '.id' <<<"$issue_json")"
  title="$(jq -r '.title' <<<"$issue_json")"
  description="$(jq -r '.description' <<<"$issue_json")"
  linear_state="$(jq -r '.state.name' <<<"$issue_json")"
  primary="$(dayflow_primary_agent "$description")"
  model_route="$(dayflow_model_for_agent "$primary")"
  read -r model reasoning <<<"$model_route"
  branch="$(dayflow_branch_name "$issue_key" "$title")"

  if [[ "$DAYFLOW_DRY_RUN" == "true" ]]; then
    case "$linear_state" in
      "$DAYFLOW_STATE_TODO_NAME") ;;
      "$DAYFLOW_STATE_IN_PROGRESS_NAME"|"$DAYFLOW_STATE_IN_REVIEW_NAME")
        dayflow_validate_resume_state "$issue_key" "$branch" "$primary" "$model" "$reasoning" >/dev/null || return 1
        ;;
      *) dayflow_error "issue state is not runnable: $linear_state"; return 1 ;;
    esac
    jq -n --arg issue "$issue_key" --arg state "$linear_state" --arg agent "$primary" \
      --arg model "$model" --arg reasoning "$reasoning" --arg branch "$branch" \
      '{dry_run: true, issue: $issue, state: $state, primary_agent: $agent, model: $model, reasoning: $reasoning, branch: $branch}'
    return 0
  fi

  dayflow_acquire_lock "$issue_key" || return 1
  dayflow_install_cleanup_traps
  case "$linear_state" in
    "$DAYFLOW_STATE_TODO_NAME")
      worktree="$(dayflow_prepare_new_worktree "$issue_key" "$branch")" || return 1
      session_id=""
      mode="primary-new"
      ;;
    "$DAYFLOW_STATE_IN_PROGRESS_NAME"|"$DAYFLOW_STATE_IN_REVIEW_NAME")
      worktree="$(dayflow_validate_resume_state "$issue_key" "$branch" "$primary" "$model" "$reasoning")" || return 1
      session_id="$(dayflow_state_value "$issue_key" '.session_id')"
      mode="primary-resume"
      ;;
    *)
      dayflow_error "issue state is not runnable: $linear_state"
      return 1
      ;;
  esac

  dayflow_state_update "$issue_key" \
    --arg issue "$issue_key" --arg id "$issue_id" --arg title "$title" --arg agent "$primary" \
    --arg model "$model" --arg reasoning "$reasoning" --arg branch "$branch" --arg worktree "$worktree" \
    --arg at "$(dayflow_now_iso)" \
    '. + {issue: $issue, issue_id: $id, title: $title, primary_agent: $agent, model: $model, reasoning: $reasoning, branch: $branch, worktree: $worktree, status: "running", updated_at: $at, tokens_used: (.tokens_used // 0)}'
  if ! dayflow_linear_set_state "$issue_id" "$DAYFLOW_STATE_IN_PROGRESS_NAME"; then
    dayflow_state_update "$issue_key" --arg at "$(dayflow_now_iso)" \
      '.status = "pre-session-blocked" | .last_error = "Linear In Progress transition failed before Codex launch" | .updated_at = $at | del(.session_id)'
    dayflow_linear_set_state "$issue_id" "$DAYFLOW_STATE_BLOCKED_NAME" || true
    dayflow_notify_state "$issue_key" "$DAYFLOW_STATE_BLOCKED_NAME" "Linear In Progress transition failed before Codex launch; workspace preserved."
    return 1
  fi
  dayflow_notify_state "$issue_key" "$DAYFLOW_STATE_IN_PROGRESS_NAME" "Primary agent ${primary} started with ${model}/${reasoning}."

  timestamp="$(date -u +%Y%m%dT%H%M%SZ)"
  prompt_file="$DAYFLOW_LOG_ROOT/${issue_key}-${timestamp}-primary.prompt"
  log_file="$DAYFLOW_LOG_ROOT/${issue_key}-${timestamp}-primary.jsonl"
  output_file="$DAYFLOW_LOG_ROOT/${issue_key}-${timestamp}-primary.out"
  dayflow_issue_prompt "$issue_json" "$primary" >"$prompt_file"
  if ! dayflow_execute_bounded "$issue_key" "$mode" "$worktree" "$model" "$reasoning" "$session_id" "$prompt_file" "$log_file" "$output_file"; then
    dayflow_block_issue "$issue_json" "$DAYFLOW_EXECUTION_ERROR"
    return 1
  fi
  if [[ "$mode" == "primary-new" ]]; then
    session_id="$(dayflow_jsonl_session_id "$log_file")"
    [[ -n "$session_id" ]] || {
      dayflow_block_issue "$issue_json" 'Codex completed without a resumable session id.'
      return 1
    }
    dayflow_state_update "$issue_key" --arg session "$session_id" '.session_id = $session'
  fi

  if ! pr_json="$(dayflow_validate_delivery "$issue_key" "$branch" "$worktree")"; then
    dayflow_block_issue "$issue_json" 'Primary agent did not produce a valid pushed develop PR with proof.'
    return 1
  fi
  pr_number="$(jq -r '.number' <<<"$pr_json")"

  while (( review_round <= 2 )); do
    review_prompt="$DAYFLOW_LOG_ROOT/${issue_key}-${timestamp}-review-${review_round}.prompt"
    review_log="$DAYFLOW_LOG_ROOT/${issue_key}-${timestamp}-review-${review_round}.jsonl"
    review_output="$DAYFLOW_LOG_ROOT/${issue_key}-${timestamp}-review-${review_round}.json"
    dayflow_review_prompt "$issue_key" >"$review_prompt"
    if ! dayflow_execute_bounded "$issue_key" review "$worktree" gpt-5.6-sol high "" "$review_prompt" "$review_log" "$review_output"; then
      dayflow_block_issue "$issue_json" "$DAYFLOW_EXECUTION_ERROR"
      return 1
    fi
    jq -e '.findings and .residual_risks' "$review_output" >/dev/null || {
      dayflow_block_issue "$issue_json" 'Review agent returned invalid structured output.'
      return 1
    }
    findings_comment="$DAYFLOW_LOG_ROOT/${issue_key}-${timestamp}-review-${review_round}.md"
    if dayflow_review_has_blockers "$review_output"; then
      if [[ "$(jq -r '.isDraft' <<<"$pr_json")" != "true" ]]; then
        dayflow_gh pr ready -R "$(dayflow_github_repo)" --undo "$pr_number" >/dev/null
        pr_json="$(jq '.isDraft = true' <<<"$pr_json")"
      fi
      dayflow_publish_review_result "$pr_number" "$review_output" "$findings_comment" "$review_round" "blocking findings"
    else
      dayflow_publish_review_result "$pr_number" "$review_output" "$findings_comment" "$review_round" "passed"
      break
    fi
    if (( review_round == 2 )); then
      dayflow_block_issue "$issue_json" 'P0-P2 review findings remain after one remediation attempt.'
      return 1
    fi

    remediation_prompt="$DAYFLOW_LOG_ROOT/${issue_key}-${timestamp}-remediation.prompt"
    remediation_log="$DAYFLOW_LOG_ROOT/${issue_key}-${timestamp}-remediation.jsonl"
    remediation_output="$DAYFLOW_LOG_ROOT/${issue_key}-${timestamp}-remediation.out"
    {
      printf 'Address all P0-P2 review findings below. Re-run relevant tests, commit, push, and refresh the existing PR proof. Do not open a second PR.\n\n'
      jq '.' "$review_output"
    } >"$remediation_prompt"
    if ! dayflow_execute_bounded "$issue_key" primary-resume "$worktree" "$model" "$reasoning" "$session_id" "$remediation_prompt" "$remediation_log" "$remediation_output"; then
      dayflow_block_issue "$issue_json" "$DAYFLOW_EXECUTION_ERROR"
      return 1
    fi
    pr_json="$(dayflow_validate_delivery "$issue_key" "$branch" "$worktree")" || {
      dayflow_block_issue "$issue_json" 'Review remediation did not preserve a valid delivery.'
      return 1
    }
    review_round=$((review_round + 1))
  done

  pr_json="$(dayflow_validate_delivery "$issue_key" "$branch" "$worktree")" || {
    dayflow_block_issue "$issue_json" 'Delivery head changed after automated review; rereview required.'
    return 1
  }
  dayflow_state_update "$issue_key" --arg head "$(jq -r '.headRefOid' <<<"$pr_json")" --arg at "$(dayflow_now_iso)" \
    '.reviewed_head_sha = $head | del(.unreviewed_head_sha) | .updated_at = $at'
  repo="$(dayflow_github_repo)"
  if [[ "$(jq -r '.isDraft' <<<"$pr_json")" == "true" ]]; then
    dayflow_gh pr ready -R "$repo" "$pr_number" >/dev/null
  fi
  dayflow_linear_set_state "$issue_id" "$DAYFLOW_STATE_IN_REVIEW_NAME"
  dayflow_notify_state "$issue_key" "$DAYFLOW_STATE_IN_REVIEW_NAME" "PR #${pr_number} passed automated review."
  dayflow_state_update "$issue_key" --argjson pr "$pr_number" --arg url "$(jq -r '.url' <<<"$pr_json")" --arg at "$(dayflow_now_iso)" \
    '.status = "in-review" | .pr_number = $pr | .pr_url = $url | .updated_at = $at'
  if dayflow_wait_for_ci "$pr_number"; then
    dayflow_reconcile_one "$issue_key"
  else
    case "${DAYFLOW_CI_WAIT_STATUS:-timeout}" in
      failed)
        dayflow_state_update "$issue_key" --arg at "$(dayflow_now_iso)" \
          '.status = "in-review-ci-failed" | .last_error = "CI checks failed after PR became ready" | .updated_at = $at'
        ;;
      *)
        dayflow_state_update "$issue_key" --arg at "$(dayflow_now_iso)" \
          '.status = "in-review-ci-timeout" | .last_error = "CI wait timed out; run reconcile after checks complete" | .updated_at = $at'
        ;;
    esac
  fi
}

dayflow_status_issue() {
  local issue_key="$1"
  local state_file local_state='{}' linear_state='unavailable' branch='' pr='null'
  dayflow_validate_issue_key "$issue_key" || return 2
  state_file="$(dayflow_state_file "$issue_key")"
  [[ -f "$state_file" ]] && local_state="$(<"$state_file")"
  if [[ -n "${LINEAR_API_KEY:-}" ]]; then
    linear_state="$(dayflow_linear_issue "$issue_key" | jq -r '.state.name' 2>/dev/null || printf 'unavailable')"
  fi
  branch="$(jq -r '.branch // ""' <<<"$local_state")"
  if [[ -n "$branch" ]] && command -v "$DAYFLOW_GH_BIN" >/dev/null 2>&1; then
    pr="$(dayflow_pr_for_branch "$branch" all | jq -c '.[0] // null' 2>/dev/null || printf 'null')"
  fi
  jq -n --arg issue "$issue_key" --arg linear_state "$linear_state" --argjson local "$local_state" --argjson pr "$pr" \
    '{issue: $issue, linear_state: $linear_state, local: $local, pull_request: $pr}'
}

dayflow_reconcile() {
  local issue_key="${1:-}"
  local state_file target rc=0
  if [[ -n "$issue_key" ]]; then
    dayflow_validate_issue_key "$issue_key" || return 2
    dayflow_acquire_lock "$issue_key" || return 1
    if dayflow_reconcile_one "$issue_key"; then rc=0; else rc=$?; fi
    dayflow_release_lock
    return "$rc"
  fi
  for state_file in "$DAYFLOW_STATE_ROOT"/CEN-*.json; do
    [[ -f "$state_file" ]] || continue
    target="$(basename "$state_file" .json)"
    if ! dayflow_acquire_lock "$target"; then
      rc=1
      continue
    fi
    if ! dayflow_reconcile_one "$target"; then rc=1; fi
    dayflow_release_lock
  done
  return "$rc"
}

dayflow_usage() {
  cat <<'EOF'
Usage:
  scripts/dayflow_runner.sh [--dry-run] run CEN-N
  scripts/dayflow_runner.sh status CEN-N
  scripts/dayflow_runner.sh reconcile [CEN-N]
EOF
}

dayflow_runner_main() {
  local command_name issue_key=""
  if [[ "${1:-}" == "--dry-run" ]]; then
    DAYFLOW_DRY_RUN=true
    shift
  fi
  command_name="${1:-}"
  [[ -n "$command_name" ]] || { dayflow_usage; return 2; }
  shift
  if [[ "${1:-}" == "--dry-run" ]]; then
    DAYFLOW_DRY_RUN=true
    shift
  fi
  issue_key="${1:-}"
  [[ $# -le 1 ]] || { dayflow_usage; return 2; }

  dayflow_require_commands bash git jq sed awk "$DAYFLOW_CURL_BIN" || return 1

  case "$command_name" in
    run)
      [[ -n "$issue_key" ]] || { dayflow_usage; return 2; }
      if [[ "$DAYFLOW_DRY_RUN" == "false" ]]; then
        dayflow_initialize_runtime
        dayflow_require_commands "$DAYFLOW_CODEX_BIN" "$DAYFLOW_GH_BIN" rg || return 1
      fi
      dayflow_run_issue "$issue_key"
      ;;
    status)
      [[ -n "$issue_key" ]] || { dayflow_usage; return 2; }
      dayflow_status_issue "$issue_key"
      ;;
    reconcile)
      if [[ "$DAYFLOW_DRY_RUN" == "false" ]]; then
        dayflow_initialize_runtime
      fi
      dayflow_require_commands "$DAYFLOW_GH_BIN" || return 1
      dayflow_reconcile "$issue_key"
      ;;
    *)
      dayflow_usage
      return 2
      ;;
  esac
}
