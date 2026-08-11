#!/usr/bin/env bash

DAYFLOW_SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ROOT_DIR="${DAYFLOW_ROOT_DIR:-$(cd "$DAYFLOW_SCRIPT_DIR/.." && pwd)}"
DAYFLOW_GIT_COMMON_DIR="$(git -C "$ROOT_DIR" rev-parse --git-common-dir 2>/dev/null || true)"
if [[ -n "$DAYFLOW_GIT_COMMON_DIR" && "$DAYFLOW_GIT_COMMON_DIR" != /* ]]; then
  DAYFLOW_GIT_COMMON_DIR="$ROOT_DIR/$DAYFLOW_GIT_COMMON_DIR"
fi
DAYFLOW_CANONICAL_REPO_ROOT="$ROOT_DIR"
if [[ -n "$DAYFLOW_GIT_COMMON_DIR" ]]; then
  DAYFLOW_CANONICAL_REPO_ROOT="$(cd "$(dirname "$DAYFLOW_GIT_COMMON_DIR")" && pwd)"
fi
DAYFLOW_RUNTIME_DIR="${DAYFLOW_RUNTIME_DIR:-$DAYFLOW_CANONICAL_REPO_ROOT/.dayflow}"
DAYFLOW_WORKTREE_ROOT="${DAYFLOW_WORKTREE_ROOT:-$DAYFLOW_RUNTIME_DIR/worktrees}"
DAYFLOW_STATE_ROOT="${DAYFLOW_STATE_ROOT:-$DAYFLOW_RUNTIME_DIR/state}"
DAYFLOW_LOG_ROOT="${DAYFLOW_LOG_ROOT:-$DAYFLOW_RUNTIME_DIR/logs}"
DAYFLOW_GH_CONFIG_DIR="${DAYFLOW_GH_CONFIG_DIR:-${GH_CONFIG_DIR:-$DAYFLOW_RUNTIME_DIR/gh}}"
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
DAYFLOW_PERL_BIN="${DAYFLOW_PERL_BIN:-perl}"
DAYFLOW_EXECUTION_LIMIT_SECONDS="${DAYFLOW_EXECUTION_LIMIT_SECONDS:-}"
DAYFLOW_PRIMARY_EXECUTION_LIMIT_SECONDS="${DAYFLOW_PRIMARY_EXECUTION_LIMIT_SECONDS:-${DAYFLOW_EXECUTION_LIMIT_SECONDS:-120}}"
DAYFLOW_REVIEW_EXECUTION_LIMIT_SECONDS="${DAYFLOW_REVIEW_EXECUTION_LIMIT_SECONDS:-${DAYFLOW_EXECUTION_LIMIT_SECONDS:-90}}"
DAYFLOW_REMEDIATION_EXECUTION_LIMIT_SECONDS="${DAYFLOW_REMEDIATION_EXECUTION_LIMIT_SECONDS:-${DAYFLOW_EXECUTION_LIMIT_SECONDS:-90}}"
DAYFLOW_STALL_LIMIT_SECONDS="${DAYFLOW_STALL_LIMIT_SECONDS:-300}"
DAYFLOW_TOKEN_LIMIT="${DAYFLOW_TOKEN_LIMIT:-400000}"
DAYFLOW_PRIMARY_TOKEN_LIMIT="${DAYFLOW_PRIMARY_TOKEN_LIMIT:-220000}"
DAYFLOW_REVIEW_TOKEN_LIMIT="${DAYFLOW_REVIEW_TOKEN_LIMIT:-100000}"
DAYFLOW_REMEDIATION_TOKEN_LIMIT="${DAYFLOW_REMEDIATION_TOKEN_LIMIT:-180000}"
DAYFLOW_PROMPT_LIMIT_BYTES="${DAYFLOW_PROMPT_LIMIT_BYTES:-32768}"
DAYFLOW_LOG_LIMIT_BYTES="${DAYFLOW_LOG_LIMIT_BYTES:-5242880}"
DAYFLOW_MONITOR_INTERVAL_SECONDS="${DAYFLOW_MONITOR_INTERVAL_SECONDS:-2}"
DAYFLOW_CI_POLL_INTERVAL_SECONDS="${DAYFLOW_CI_POLL_INTERVAL_SECONDS:-5}"
DAYFLOW_CI_WAIT_TIMEOUT_SECONDS="${DAYFLOW_CI_WAIT_TIMEOUT_SECONDS:-600}"
DAYFLOW_SHARED_LOCK_ATTEMPTS="${DAYFLOW_SHARED_LOCK_ATTEMPTS:-300}"
DAYFLOW_DEFAULT_SANDBOX="${DAYFLOW_DEFAULT_SANDBOX:-workspace-write}"
DAYFLOW_DRY_RUN="${DAYFLOW_DRY_RUN:-false}"
DAYFLOW_ACTIVE_CODEX_PID=""
DAYFLOW_ACTIVE_CODEX_PGID=""
DAYFLOW_ACTIVE_MERGE_READY_LOCK_TOKEN=""
DAYFLOW_ACTIVE_MERGE_READY_LOCK_PID=""
DAYFLOW_ACTIVE_MERGE_READY_LOCK_IDENTITY=""
DAYFLOW_CURRENT_BASH_PID=""
DAYFLOW_EXECUTION_LATE_TOKEN_LIMIT="false"

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
      printf 'gpt-5.6-terra high\n'
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
  local migration_rc=0

  if [[ ! -e "$DAYFLOW_GH_CONFIG_DIR" && -d "$legacy_gh" ]]; then
    cp -R "$legacy_gh" "$DAYFLOW_GH_CONFIG_DIR"
  fi
  if [[ ! -e "$DAYFLOW_NOTIFICATIONS_ENV_FILE" && -f "$legacy_notifications" ]]; then
    cp "$legacy_notifications" "$DAYFLOW_NOTIFICATIONS_ENV_FILE"
    chmod 600 "$DAYFLOW_NOTIFICATIONS_ENV_FILE" 2>/dev/null || true
  fi
  dayflow_acquire_merge_ready_lock || return 1
  if [[ ! -e "$DAYFLOW_MERGE_READY_STORE" && -f "$legacy_merge_ready" ]]; then
    cp "$legacy_merge_ready" "$DAYFLOW_MERGE_READY_STORE" || migration_rc=1
  fi
  if (( migration_rc == 0 )) && [[ ! -f "$DAYFLOW_MERGE_READY_STORE" ]]; then
    printf '{}\n' >"$DAYFLOW_MERGE_READY_STORE" || migration_rc=1
  fi
  if (( migration_rc == 0 )); then
    dayflow_normalize_merge_ready_store || migration_rc=1
  fi
  dayflow_release_merge_ready_lock
  return "$migration_rc"
}

dayflow_normalize_merge_ready_store() {
  local tmp_file="${DAYFLOW_MERGE_READY_STORE}.tmp.$$"
  if ! jq '
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
  ' "$DAYFLOW_MERGE_READY_STORE" >"$tmp_file"; then
    rm -f "$tmp_file"
    return 1
  fi
  if ! mv "$tmp_file" "$DAYFLOW_MERGE_READY_STORE"; then
    rm -f "$tmp_file"
    return 1
  fi
}

dayflow_process_start_identity() {
  ps -o lstart= -p "$1" 2>/dev/null | awk '{$1=$1; print}'
}

dayflow_pid_identity_matches() {
  local pid="$1"
  local expected="$2"
  local actual
  [[ "$pid" =~ ^[1-9][0-9]*$ && -n "$expected" ]] || return 1
  kill -0 "$pid" 2>/dev/null || return 1
  actual="$(dayflow_process_start_identity "$pid")"
  [[ -n "$actual" && "$actual" == "$expected" ]]
}

dayflow_acquire_lock() {
  local issue_key="$1"
  local lock_dir="$DAYFLOW_STATE_ROOT/${issue_key}.lock"
  local existing_pid="" existing_identity=""

  if mkdir "$lock_dir" 2>/dev/null; then
    printf '%s\n' "$$" >"$lock_dir/pid"
    dayflow_process_start_identity "$$" >"$lock_dir/process-start"
    DAYFLOW_ACTIVE_LOCK_DIR="$lock_dir"
    return 0
  fi

  [[ -f "$lock_dir/pid" ]] && existing_pid="$(<"$lock_dir/pid")"
  [[ -f "$lock_dir/process-start" ]] && existing_identity="$(<"$lock_dir/process-start")"
  if dayflow_pid_identity_matches "$existing_pid" "$existing_identity"; then
    dayflow_error "$issue_key is already running under pid $existing_pid"
    return 1
  fi

  rm -f "$lock_dir/pid" "$lock_dir/process-start"
  rmdir "$lock_dir" 2>/dev/null || {
    dayflow_error "unable to recover stale lock for $issue_key"
    return 1
  }
  mkdir "$lock_dir"
  printf '%s\n' "$$" >"$lock_dir/pid"
  dayflow_process_start_identity "$$" >"$lock_dir/process-start"
  DAYFLOW_ACTIVE_LOCK_DIR="$lock_dir"
}

dayflow_release_lock() {
  if [[ -n "${DAYFLOW_ACTIVE_LOCK_DIR:-}" && -d "$DAYFLOW_ACTIVE_LOCK_DIR" ]]; then
    rm -f "$DAYFLOW_ACTIVE_LOCK_DIR/pid" "$DAYFLOW_ACTIVE_LOCK_DIR/process-start"
    rmdir "$DAYFLOW_ACTIVE_LOCK_DIR" 2>/dev/null || true
  fi
  DAYFLOW_ACTIVE_LOCK_DIR=""
}

dayflow_capture_current_bash_pid() {
  local captured_pid="" capture_file

  capture_file="$(mktemp "${TMPDIR:-/tmp}/dayflow-shell-pid.XXXXXX")" || return 1
  if ! "$DAYFLOW_PERL_BIN" -e 'print getppid, "\n"' >"$capture_file"; then
    rm -f "$capture_file"
    return 1
  fi
  IFS= read -r captured_pid <"$capture_file" || true
  rm -f "$capture_file"
  [[ "$captured_pid" =~ ^[1-9][0-9]*$ ]] || return 1
  DAYFLOW_CURRENT_BASH_PID="$captured_pid"
}

dayflow_shared_lock_transaction() {
  local operation="$1"
  local token="$2"
  local owner_pid="$3"
  local owner_identity="$4"
  local lease_file="$DAYFLOW_STATE_ROOT/merge-ready.lock"
  local mutex_file="$DAYFLOW_STATE_ROOT/merge-ready.lock.mutex"

  "$DAYFLOW_PERL_BIN" - "$operation" "$mutex_file" "$lease_file" "$token" "$owner_pid" "$owner_identity" <<'PERL'
use strict;
use warnings;
use Fcntl qw(:DEFAULT :flock);

my ($operation, $mutex_file, $lease_file, $token, $owner_pid, $owner_identity) = @ARGV;
open my $mutex, '>>', $mutex_file or exit 2;
flock($mutex, LOCK_EX | LOCK_NB) or exit 1;
my $temp_file = "$lease_file.tmp";
if (-e $temp_file || -l $temp_file) {
  unlink $temp_file or exit 2;
}

sub read_lease {
  my ($path) = @_;
  open my $fh, '<', $path or return;
  my @values = <$fh>;
  close $fh;
  return unless @values == 3;
  for my $value (@values) {
    $value =~ s/\r?\n\z//;
    return unless length $value;
  }
  return @values;
}

sub process_identity_matches {
  my ($pid, $identity) = @_;
  return 0 unless $pid =~ /\A[0-9]+\z/ && length $identity;
  open my $ps, '-|', 'ps', '-o', 'lstart=', '-p', $pid or return 0;
  my $actual = <$ps> // '';
  close $ps;
  $actual =~ s/^\s+|\s+$//g;
  $actual =~ s/\s+/ /g;
  return $actual eq $identity;
}

sub publish_lease {
  my ($path, $temp, $token_value, $pid_value, $identity_value) = @_;
  sysopen my $fh, $temp, O_WRONLY | O_CREAT | O_EXCL, 0600 or return 0;
  my $written = print {$fh} "$token_value\n$pid_value\n$identity_value\n";
  my $closed = close $fh;
  unless ($written && $closed && rename $temp, $path) {
    unlink $temp;
    return 0;
  }
  my @published = read_lease($path);
  return @published == 3 && $published[0] eq $token_value &&
    $published[1] eq $pid_value && $published[2] eq $identity_value;
}

if ($operation eq 'acquire') {
  if (-e $lease_file) {
    exit 2 unless -f $lease_file;
    my @existing = read_lease($lease_file);
    exit 1 if @existing == 3 && process_identity_matches($existing[1], $existing[2]);
  }
  exit(publish_lease($lease_file, $temp_file, $token, $owner_pid, $owner_identity) ? 0 : 2);
}

if ($operation eq 'release') {
  exit 0 unless -f $lease_file;
  my @existing = read_lease($lease_file);
  exit 0 unless @existing == 3 && $existing[0] eq $token &&
    $existing[1] eq $owner_pid && $existing[2] eq $owner_identity;
  exit(unlink($lease_file) ? 0 : 2);
}

exit 2;
PERL
}

dayflow_acquire_merge_ready_lock() {
  local attempt token identity owner_pid

  dayflow_capture_current_bash_pid || {
    dayflow_error 'unable to determine merge-ready lock owner PID'
    return 1
  }
  owner_pid="$DAYFLOW_CURRENT_BASH_PID"
  identity="$(dayflow_process_start_identity "$owner_pid")"
  [[ -n "$identity" ]] || {
    dayflow_error 'unable to determine merge-ready lock owner identity'
    return 1
  }
  token="$owner_pid-${RANDOM}-$(date +%s)"

  for ((attempt = 0; attempt < DAYFLOW_SHARED_LOCK_ATTEMPTS; attempt++)); do
    if dayflow_shared_lock_transaction acquire "$token" "$owner_pid" "$identity"; then
      DAYFLOW_ACTIVE_MERGE_READY_LOCK_TOKEN="$token"
      DAYFLOW_ACTIVE_MERGE_READY_LOCK_PID="$owner_pid"
      DAYFLOW_ACTIVE_MERGE_READY_LOCK_IDENTITY="$identity"
      return 0
    fi
    sleep 0.1
  done

  dayflow_error 'timed out waiting for the merge-ready store lock'
  return 1
}

dayflow_release_merge_ready_lock() {
  local attempt
  if [[ -n "${DAYFLOW_ACTIVE_MERGE_READY_LOCK_TOKEN:-}" ]]; then
    for ((attempt = 0; attempt < DAYFLOW_SHARED_LOCK_ATTEMPTS; attempt++)); do
      if dayflow_shared_lock_transaction release \
        "$DAYFLOW_ACTIVE_MERGE_READY_LOCK_TOKEN" \
        "$DAYFLOW_ACTIVE_MERGE_READY_LOCK_PID" \
        "$DAYFLOW_ACTIVE_MERGE_READY_LOCK_IDENTITY"; then
        break
      fi
      sleep 0.1
    done
  fi
  DAYFLOW_ACTIVE_MERGE_READY_LOCK_TOKEN=""
  DAYFLOW_ACTIVE_MERGE_READY_LOCK_PID=""
  DAYFLOW_ACTIVE_MERGE_READY_LOCK_IDENTITY=""
}

dayflow_exit_cleanup() {
  local status=$?
  trap - EXIT INT TERM
  dayflow_stop_active_codex
  dayflow_release_merge_ready_lock
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

dayflow_parallel_safe() {
  local description="$1"
  local value normalized
  value="$(printf '%s\n' "$description" | sed -nE 's/^[[:space:]]*(Parallel Safe|Parallel-Safe):[[:space:]]*(.+)[[:space:]]*$/\2/ip' | head -n 1)"
  if [[ -z "$value" ]]; then
    value="$(dayflow_extract_section "$description" 'Parallel Safe' | head -n 1 | sed -E 's/^[[:space:]-]+//')"
  fi
  normalized="$(printf '%s' "$value" | tr '[:upper:]' '[:lower:]')"
  [[ "$normalized" == "yes" || "$normalized" == "true" ]]
}

dayflow_write_scopes() {
  local description="$1"
  local inline
  inline="$(printf '%s\n' "$description" | sed -nE 's/^[[:space:]]*Write Scope:[[:space:]]*(.+)[[:space:]]*$/\1/p' | head -n 1)"
  if [[ -n "$inline" ]]; then
    printf '%s\n' "$inline" | tr ',' '\n'
  else
    dayflow_extract_section "$description" 'Write Scope'
  fi | sed -E 's/^[[:space:]*-]+//; s/[`"]//g; s/[[:space:]]+$//; s#/?\*\*$##; s#/$##' |
    awk 'NF && $0 !~ /^\.\./ && $0 !~ /\/\.\.($|\/)/ && $0 !~ /^\// {print}' |
    head -n 32
}

dayflow_issue_references() {
  local description="$1"
  dayflow_extract_section "$description" 'Inputs' |
    sed -E 's/^[[:space:]*-]+//; s/[`"]//g; s/[[:space:]]+$//' |
    awk 'length($0) <= 160 && $0 ~ /^[A-Za-z0-9._\/-]+$/ && $0 !~ /^\.\./ && $0 !~ /\/\.\.($|\/)/ {print}' |
    head -n 12
}

dayflow_primary_agent() {
  local description="$1"
  dayflow_extract_section "$description" 'Primary Agent' |
    head -n 1 |
    sed -E 's/^[[:space:]-]+//; s/[`*]//g; s/[[:space:]]+$//'
}

dayflow_allowed_base_branch() {
  [[ "$1" == "develop" || "$1" == "integration/private-two-person-cutover" ]]
}

dayflow_integration_base_branch() {
  local description="$1"
  local values count value
  values="$(printf '%s\n' "$description" | sed -nE 's/^[[:space:]]*[-*]?[[:space:]]*Integration Base:[[:space:]]*(.*[^[:space:]])[[:space:]]*$/\1/p')"
  count="$(printf '%s\n' "$description" | sed -nE '/^[[:space:]]*[-*]?[[:space:]]*Integration Base([[:space:]]*:|[[:space:]]*$)/p' | wc -l | tr -d ' ')"
  if [[ "$count" == "0" ]]; then
    printf 'develop\n'
    return 0
  fi
  [[ "$count" == "1" && "$(printf '%s\n' "$values" | wc -l | tr -d ' ')" == "1" ]] || {
    dayflow_error 'Integration Base must appear once as an inline field'
    return 1
  }
  value="$values"
  [[ "$value" == "integration/private-two-person-cutover" ]] || {
    dayflow_error 'Integration Base is not an allowed temporary integration branch'
    return 1
  }
  printf '%s\n' "$value"
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
  dayflow_integration_base_branch "$description" >/dev/null || return 1
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

dayflow_git_publish() {
  local worktree="$1"
  shift
  GH_CONFIG_DIR="$DAYFLOW_GH_CONFIG_DIR" git \
    -c credential.helper= \
    -c "credential.helper=!${DAYFLOW_GH_BIN} auth git-credential" \
    -C "$worktree" "$@"
}

dayflow_validate_publication_capability() {
  local worktree="$1"
  local branch="$2"
  local repo permission
  repo="$(dayflow_github_repo)" || return 1
  dayflow_gh auth status >/dev/null 2>&1 || {
    dayflow_error 'GitHub CLI authentication is unavailable from the canonical DayFlow runtime'
    return 1
  }
  dayflow_gh repo view "$repo" --json nameWithOwner >/dev/null 2>&1 || {
    dayflow_error "GitHub repository is not accessible: $repo"
    return 1
  }
  permission="$(dayflow_gh api "repos/$repo" --jq '.permissions.push // false' 2>/dev/null)" || {
    dayflow_error "unable to verify GitHub publication permission for $repo"
    return 1
  }
  [[ "$permission" == "true" ]] || {
    dayflow_error "GitHub token does not have push permission for $repo"
    return 1
  }
  dayflow_git_publish "$worktree" push --dry-run origin "HEAD:refs/heads/$branch" >/dev/null 2>&1 || {
    dayflow_error 'Git transport publication preflight failed'
    return 1
  }
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

Edit and test only the issue-scoped files in the current isolated worktree. Do not run git add, git commit, git push, gh, Linear, Discord, or PR/lifecycle commands. The deterministic runner owns staging, commit, publication, draft PR proof, readiness, and lifecycle state after your session exits. Keep secrets and runtime artifacts out of the worktree.

Your final response must be one JSON object with this exact shape: {"summary":"short result","tests":[{"name":"focused test name","status":"passed"}]}. Include 1-8 tests you actually ran. Do not include commands for the lifecycle to execute; failed, skipped, missing, or malformed test evidence blocks publication.

Keep investigation narrow. Never print or request a full repository tree, full repository diff, whole large file, complete log, recursive source dump, or unrelated source. Use rg and bounded ranges, keep command output focused, and read only the issue references below plus files directly required to implement them. Do not start MCP servers or connectors.

Issue title: ${title}

Issue description:
${description}

Agent definition:
$(dayflow_agent_definition "$agent")

Narrow issue references:
$(dayflow_issue_references "$description" | sed 's/^/- /')
EOF
}

dayflow_review_prompt() {
  local issue_key="$1"
  local base_branch="$2"
  cat <<EOF
Review the current ${issue_key} branch against origin/${base_branch}. Follow the repository review-agent definition and the single narrow checklist below. Do not edit files. Return only the requested structured review result. Classify actionable findings as P0, P1, P2, or P3. P0-P2 block merge readiness. Never dump a whole repository, large file, log, or recursive diff, and do not start MCP servers or connectors.

Review agent definition:
$(dayflow_agent_definition review-agent)

Review checklist:
$(sed -n '1,260p' "$ROOT_DIR/docs/review-checklist.md")
EOF
}

dayflow_prepare_new_worktree() {
  local issue_key="$1"
  local branch="$2"
  local base_branch="$3"
  local worktree="$DAYFLOW_WORKTREE_ROOT/$issue_key"
  [[ ! -e "$worktree" ]] || {
    dayflow_error "new Todo issue already has a worktree: $worktree"
    return 1
  }
  dayflow_allowed_base_branch "$base_branch" || return 1
  git -C "$ROOT_DIR" fetch origin "$base_branch"
  if git -C "$ROOT_DIR" show-ref --verify --quiet "refs/heads/$branch"; then
    dayflow_error "new Todo issue already has local branch: $branch"
    return 1
  fi
  git -C "$ROOT_DIR" worktree add -b "$branch" "$worktree" "origin/$base_branch" >&2
  printf '%s\n' "$worktree"
}

dayflow_validate_resume_state() {
  local issue_key="$1"
  local expected_branch="$2"
  local expected_agent="$3"
  local expected_model="$4"
  local expected_reasoning="$5"
  local allow_dirty="${6:-false}"
  local state_file worktree branch session_id persisted_agent persisted_model persisted_reasoning persisted_base
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
  persisted_base="$(jq -r '.base_branch // "develop"' "$state_file")"
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
  [[ "$persisted_base" == "${7:-develop}" ]] || {
    dayflow_error "$issue_key resume base branch no longer matches Linear metadata"
    return 1
  }
  [[ "$allow_dirty" == "true" || -z "$(git -C "$worktree" status --porcelain --untracked-files=normal)" ]] || {
    dayflow_error "$issue_key resume worktree is dirty"
    return 1
  }
  printf '%s\n' "$worktree"
}

dayflow_is_pre_session_recovery() {
  local issue_key="$1"
  local state_file
  state_file="$(dayflow_state_file "$issue_key")"
  [[ -f "$state_file" ]] || return 1
  [[ "$(jq -r '.status // ""' "$state_file")" == "pre-session-blocked" ]] || return 1
  [[ -z "$(jq -r '.session_id // ""' "$state_file")" ]]
}

dayflow_validate_pre_session_recovery() {
  local issue_key="$1"
  local expected_branch="$2"
  local expected_agent="$3"
  local expected_model="$4"
  local expected_reasoning="$5"
  local state_file worktree branch persisted_agent persisted_model persisted_reasoning persisted_base commit_count base_branch
  state_file="$(dayflow_state_file "$issue_key")"
  dayflow_is_pre_session_recovery "$issue_key" || {
    dayflow_error "$issue_key is not in the recoverable pre-session state"
    return 1
  }

  worktree="$(jq -r '.worktree // ""' "$state_file")"
  persisted_agent="$(jq -r '.primary_agent // ""' "$state_file")"
  persisted_model="$(jq -r '.model // ""' "$state_file")"
  persisted_reasoning="$(jq -r '.reasoning // ""' "$state_file")"
  base_branch="${6:-develop}"
  persisted_base="$(jq -r '.base_branch // "develop"' "$state_file")"
  [[ "$worktree" == "$DAYFLOW_WORKTREE_ROOT/$issue_key" && -e "$worktree/.git" ]] || {
    dayflow_error "$issue_key pre-session recovery worktree is not owned by this issue"
    return 1
  }
  branch="$(git -C "$worktree" branch --show-current)"
  [[ "$branch" == "$expected_branch" ]] || {
    dayflow_error "$issue_key pre-session recovery branch mismatch: $branch"
    return 1
  }
  [[ "$persisted_agent" == "$expected_agent" && "$persisted_model" == "$expected_model" && "$persisted_reasoning" == "$expected_reasoning" ]] || {
    dayflow_error "$issue_key pre-session recovery ownership metadata no longer matches Linear routing"
    return 1
  }
  [[ "$persisted_base" == "$base_branch" ]] || {
    dayflow_error "$issue_key pre-session recovery base branch no longer matches Linear metadata"
    return 1
  }
  [[ -z "$(git -C "$worktree" status --porcelain --untracked-files=normal)" ]] || {
    dayflow_error "$issue_key pre-session recovery worktree is not clean"
    return 1
  }
  git -C "$ROOT_DIR" fetch origin "$base_branch" >/dev/null
  commit_count="$(git -C "$worktree" rev-list --count "origin/$base_branch..HEAD")"
  [[ "$commit_count" == "0" ]] && git -C "$worktree" merge-base --is-ancestor HEAD "origin/$base_branch" || {
    dayflow_error "$issue_key pre-session recovery branch contains unowned commits"
    return 1
  }
  printf '%s\n' "$worktree"
}

dayflow_jsonl_usage() {
  local log_file="$1"
  [[ -s "$log_file" ]] || {
    printf '%s\n' '{"input_tokens":0,"cached_input_tokens":0,"uncached_input_tokens":0,"output_tokens":0,"raw_total_tokens":0,"billable_tokens":0}'
    return
  }
  jq -R -s '
    split("\n") | map(fromjson? // empty)
    | [ .[]
      | (.usage // .token_usage // .response.usage // .event.usage // .item.usage // empty)
      | {
          input: (.input_tokens // .inputTokens // .prompt_tokens // .promptTokens // 0),
          cached: (.cached_input_tokens // .cachedInputTokens // .input_tokens_details.cached_tokens // .prompt_tokens_details.cached_tokens // 0),
          output: (.output_tokens // .outputTokens // .completion_tokens // .completionTokens // 0),
          total: (.total_tokens // .totalTokens // 0)
        }
    ] as $snapshots
    | ($snapshots | map(.input) | max // 0) as $input
    | ($snapshots | map(.cached) | max // 0) as $cached
    | ($snapshots | map(.output) | max // 0) as $output
    | ($snapshots | map(.total) | max // 0) as $reported_total
    | {
        input_tokens: $input,
        cached_input_tokens: ([$cached, $input] | min),
        uncached_input_tokens: ($input - ([$cached, $input] | min)),
        output_tokens: $output,
        raw_total_tokens: ([$reported_total, ($input + $output)] | max),
        billable_tokens: (($input - ([$cached, $input] | min)) + $output)
      }
  ' "$log_file" 2>/dev/null || printf '%s\n' '{"input_tokens":0,"cached_input_tokens":0,"uncached_input_tokens":0,"output_tokens":0,"raw_total_tokens":0,"billable_tokens":0}'
}

dayflow_jsonl_billable_tokens() {
  dayflow_jsonl_usage "$1" | jq -r '.billable_tokens'
}

dayflow_state_billable_tokens() {
  local issue_key="$1"
  local state_file
  state_file="$(dayflow_state_file "$issue_key")"
  [[ -f "$state_file" ]] || {
    printf '%s\n' '0'
    return
  }
  jq -er '
    if (.billable_tokens | type) == "number" and .billable_tokens >= 0 then .billable_tokens
    elif (.usage.billable_tokens | type) == "number" and .usage.billable_tokens >= 0 then .usage.billable_tokens
    elif ((.usage.uncached_input_tokens | type) == "number" and .usage.uncached_input_tokens >= 0
      and (.usage.output_tokens | type) == "number" and .usage.output_tokens >= 0) then
      (.usage.uncached_input_tokens + .usage.output_tokens)
    else empty
    end
  ' "$state_file"
}

dayflow_execution_phase_for_mode() {
  case "$1" in
    primary-new|primary-resume|primary-fresh) printf '%s\n' primary ;;
    review) printf '%s\n' review ;;
    remediation) printf '%s\n' remediation ;;
    *) return 1 ;;
  esac
}

dayflow_phase_execution_limit() {
  case "$1" in
    primary) printf '%s\n' "$DAYFLOW_PRIMARY_EXECUTION_LIMIT_SECONDS" ;;
    review) printf '%s\n' "$DAYFLOW_REVIEW_EXECUTION_LIMIT_SECONDS" ;;
    remediation) printf '%s\n' "$DAYFLOW_REMEDIATION_EXECUTION_LIMIT_SECONDS" ;;
    *) return 1 ;;
  esac
}

dayflow_phase_token_limit() {
  case "$1" in
    primary) printf '%s\n' "$DAYFLOW_PRIMARY_TOKEN_LIMIT" ;;
    review) printf '%s\n' "$DAYFLOW_REVIEW_TOKEN_LIMIT" ;;
    remediation) printf '%s\n' "$DAYFLOW_REMEDIATION_TOKEN_LIMIT" ;;
    *) return 1 ;;
  esac
}

dayflow_state_phase_billable_tokens() {
  local issue_key="$1"
  local phase="$2"
  local state_file
  state_file="$(dayflow_state_file "$issue_key")"
  [[ -f "$state_file" ]] || {
    printf '%s\n' '0'
    return
  }
  jq -er --arg phase "$phase" '
    .phase_usage[$phase].billable_tokens as $tokens
    | if ($tokens | type) == "number" and $tokens >= 0 then $tokens else 0 end
  ' "$state_file"
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

  target_pgid="${DAYFLOW_ACTIVE_CODEX_PGID:-}"
  runner_pgid=""
  if [[ ! "$target_pgid" =~ ^[0-9]+$ ]]; then
    runner_pgid="$(ps -o pgid= -p $$ 2>/dev/null | tr -d ' ' || true)"
    target_pgid="$(ps -o pgid= -p "$pid" 2>/dev/null | tr -d ' ' || true)"
  fi
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
  local common=(--json --ignore-user-config -m "$model" -c "model_reasoning_effort=\"$reasoning\"" -c 'approval_policy="never"' -c 'mcp_servers={}')
  local scrub=(env)
  local env_name
  while IFS='=' read -r env_name _; do
    case "$env_name" in
      LINEAR_*|GH_*|GITHUB_*|*DISCORD*|DAYFLOW_GH_*|DAYFLOW_NOTIFICATIONS_ENV_FILE)
        scrub+=(-u "$env_name")
        ;;
    esac
  done < <(env)

  case "$mode" in
    primary-new|primary-fresh)
      "${scrub[@]}" \
        "$DAYFLOW_CODEX_BIN" exec "${common[@]}" -s "$DAYFLOW_DEFAULT_SANDBOX" -C "$worktree" -o "$output_file" - <"$prompt_file"
      ;;
    primary-resume)
      (
        cd "$worktree"
        "${scrub[@]}" \
          "$DAYFLOW_CODEX_BIN" exec resume "${common[@]}" -c "sandbox_mode=\"$DAYFLOW_DEFAULT_SANDBOX\"" -o "$output_file" "$session_id" - <"$prompt_file"
      )
      ;;
    review)
      "${scrub[@]}" \
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
  local phase="${10:-}" phase_limit execution_limit_seconds phase_billable_tokens aggregate_billable_tokens
  local started_at now last_progress last_size=0 size elapsed invocation_billable_tokens pid rc=0 limit_reason=""
  local prompt_size invocation_usage input_tokens cached_input_tokens uncached_input_tokens output_tokens raw_total_tokens
  local restore_job_control=false

  DAYFLOW_EXECUTION_LATE_TOKEN_LIMIT="false"

  prompt_size="$(wc -c <"$prompt_file" | tr -d ' ')"
  if (( prompt_size > DAYFLOW_PROMPT_LIMIT_BYTES )); then
    DAYFLOW_EXECUTION_ERROR="prompt limit exceeded (${prompt_size}/${DAYFLOW_PROMPT_LIMIT_BYTES} bytes)"
    export DAYFLOW_EXECUTION_ERROR
    return 124
  fi

  if [[ -z "$phase" ]]; then
    phase="$(dayflow_execution_phase_for_mode "$mode")" || {
      DAYFLOW_EXECUTION_ERROR="unsupported execution phase for mode: $mode"
      export DAYFLOW_EXECUTION_ERROR
      return 124
    }
  fi
  phase_limit="$(dayflow_phase_token_limit "$phase")" || {
    DAYFLOW_EXECUTION_ERROR="unsupported execution phase: $phase"
    export DAYFLOW_EXECUTION_ERROR
    return 124
  }
  [[ "$phase_limit" =~ ^[0-9]+$ ]] || {
    DAYFLOW_EXECUTION_ERROR="invalid token limit for phase $phase"
    export DAYFLOW_EXECUTION_ERROR
    return 124
  }
  execution_limit_seconds="$(dayflow_phase_execution_limit "$phase")" || {
    DAYFLOW_EXECUTION_ERROR="unsupported execution phase: $phase"
    export DAYFLOW_EXECUTION_ERROR
    return 124
  }
  [[ "$execution_limit_seconds" =~ ^[0-9]+$ && "$execution_limit_seconds" -gt 0 ]] || {
    DAYFLOW_EXECUTION_ERROR="invalid execution limit for phase $phase"
    export DAYFLOW_EXECUTION_ERROR
    return 124
  }

  # A retry must never validate an output artifact left by an earlier execution.
  rm -f "$log_file" "$output_file"

  aggregate_billable_tokens="$(dayflow_state_billable_tokens "$issue_key")" || {
    DAYFLOW_EXECUTION_ERROR='billable token accounting is unavailable; refusing to launch'
    export DAYFLOW_EXECUTION_ERROR
    return 124
  }
  if (( aggregate_billable_tokens >= DAYFLOW_TOKEN_LIMIT )); then
    DAYFLOW_EXECUTION_ERROR="token limit reached before launch (${DAYFLOW_TOKEN_LIMIT})"
    export DAYFLOW_EXECUTION_ERROR
    return 124
  fi
  phase_billable_tokens="$(dayflow_state_phase_billable_tokens "$issue_key" "$phase")" || {
    DAYFLOW_EXECUTION_ERROR='phase token accounting is unavailable; refusing to launch'
    export DAYFLOW_EXECUTION_ERROR
    return 124
  }
  if (( phase_billable_tokens >= phase_limit )); then
    DAYFLOW_EXECUTION_ERROR="${phase} token limit reached before launch (${phase_limit})"
    export DAYFLOW_EXECUTION_ERROR
    return 124
  fi

  : >"$log_file"
  started_at="$(date +%s)"
  last_progress="$started_at"
  if [[ $- != *m* ]]; then
    set -m
    restore_job_control=true
  fi
  (
    trap - EXIT INT TERM
    dayflow_codex_command "$mode" "$worktree" "$model" "$reasoning" "$session_id" "$prompt_file" "$output_file"
  ) >"$log_file" 2>&1 &
  pid=$!
  if [[ "$restore_job_control" == "true" ]]; then
    set +m
  fi
  DAYFLOW_ACTIVE_CODEX_PID="$pid"
  DAYFLOW_ACTIVE_CODEX_PGID="$pid"

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
    invocation_billable_tokens="$(dayflow_jsonl_billable_tokens "$log_file")"
    aggregate_billable_tokens="$(dayflow_state_billable_tokens "$issue_key")" || {
      limit_reason='billable token accounting became unavailable'
      break
    }
    if (( size >= DAYFLOW_LOG_LIMIT_BYTES )); then
      limit_reason="command output limit exceeded (${DAYFLOW_LOG_LIMIT_BYTES} bytes)"
    elif (( aggregate_billable_tokens + invocation_billable_tokens >= DAYFLOW_TOKEN_LIMIT )); then
      limit_reason="token limit exceeded (${DAYFLOW_TOKEN_LIMIT})"
    elif (( phase_billable_tokens + invocation_billable_tokens >= phase_limit )); then
      limit_reason="${phase} token limit exceeded (${phase_limit})"
    elif (( now - last_progress >= DAYFLOW_STALL_LIMIT_SECONDS )); then
      limit_reason="no progress for ${DAYFLOW_STALL_LIMIT_SECONDS}s"
    elif (( elapsed >= execution_limit_seconds )); then
      limit_reason="execution limit exceeded (${execution_limit_seconds}s; phase=${phase})"
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

  invocation_usage="$(dayflow_jsonl_usage "$log_file")"
  invocation_billable_tokens="$(jq -r '.billable_tokens' <<<"$invocation_usage")"
  input_tokens="$(jq -r '.input_tokens' <<<"$invocation_usage")"
  cached_input_tokens="$(jq -r '.cached_input_tokens' <<<"$invocation_usage")"
  uncached_input_tokens="$(jq -r '.uncached_input_tokens' <<<"$invocation_usage")"
  output_tokens="$(jq -r '.output_tokens' <<<"$invocation_usage")"
  raw_total_tokens="$(jq -r '.raw_total_tokens' <<<"$invocation_usage")"
  aggregate_billable_tokens="$(dayflow_state_billable_tokens "$issue_key")" || {
    DAYFLOW_EXECUTION_ERROR='billable token accounting is unavailable after process exit'
    export DAYFLOW_EXECUTION_ERROR
    return 124
  }
  aggregate_billable_tokens=$((aggregate_billable_tokens + invocation_billable_tokens))
  phase_billable_tokens=$((phase_billable_tokens + invocation_billable_tokens))
  dayflow_state_update "$issue_key" \
    --argjson billable "$aggregate_billable_tokens" \
    --argjson invocation_billable "$invocation_billable_tokens" \
    --argjson input "$input_tokens" \
    --argjson cached "$cached_input_tokens" \
    --argjson uncached "$uncached_input_tokens" \
    --argjson output "$output_tokens" \
    --argjson raw_total "$raw_total_tokens" \
    --arg phase "$phase" \
    --argjson phase_billable "$phase_billable_tokens" \
    --argjson phase_invocation "$invocation_billable_tokens" \
    --arg at "$(dayflow_now_iso)" \
    '.billable_tokens = $billable
     | .usage = ((.usage // {input_tokens: 0, cached_input_tokens: 0, uncached_input_tokens: 0, output_tokens: 0, raw_total_tokens: 0, billable_tokens: 0, invocations: 0})
       | .input_tokens += $input
       | .cached_input_tokens += $cached
       | .uncached_input_tokens += $uncached
       | .output_tokens += $output
       | .raw_total_tokens += $raw_total
       | .billable_tokens += $invocation_billable
       | .invocations += 1)
     | .phase_usage = ((.phase_usage // {})
       | .[$phase] = ((.[$phase] // {billable_tokens: 0, invocations: 0})
         | .billable_tokens = $phase_billable
         | .invocations += 1
         | .last_invocation_billable_tokens = $phase_invocation))
     | del(.tokens_used)
     | .updated_at = $at'

  if [[ -z "$limit_reason" && "$rc" == "0" ]] && (( aggregate_billable_tokens >= DAYFLOW_TOKEN_LIMIT )); then
    limit_reason="token limit exceeded after process exit (${DAYFLOW_TOKEN_LIMIT})"
    if [[ "$mode" =~ ^primary-(new|fresh|resume)$ ]] \
      && [[ -n "$(dayflow_jsonl_session_id "$log_file")" ]] \
      && dayflow_validate_test_evidence "$output_file" >/dev/null 2>&1; then
      DAYFLOW_EXECUTION_LATE_TOKEN_LIMIT="true"
    else
      rc=124
    fi
  elif [[ -z "$limit_reason" && "$rc" == "0" ]] && (( phase_billable_tokens >= phase_limit )); then
    limit_reason="${phase} token limit exceeded after process exit (${phase_limit})"
    if [[ "$mode" =~ ^primary-(new|fresh|resume)$ ]] \
      && [[ -n "$(dayflow_jsonl_session_id "$log_file")" ]] \
      && dayflow_validate_test_evidence "$output_file" >/dev/null 2>&1; then
      DAYFLOW_EXECUTION_LATE_TOKEN_LIMIT="true"
    else
      rc=124
    fi
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
  if [[ "$DAYFLOW_EXECUTION_LATE_TOKEN_LIMIT" == "true" ]]; then
    dayflow_state_update "$issue_key" --arg reason "$DAYFLOW_EXECUTION_ERROR" --arg phase "$phase" --arg at "$(dayflow_now_iso)" '
      .late_token_limit = {reason: $reason, phase: $phase, reported_at: $at}
      | .updated_at = $at'
  fi
  export DAYFLOW_EXECUTION_ERROR
  export DAYFLOW_EXECUTION_LATE_TOKEN_LIMIT
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

dayflow_update_pr() {
  local repo="$1"
  local pr_number="$2"
  local title="$3"
  local body_file="$4"
  local body
  body="$(<"$body_file")"
  dayflow_gh api -X PATCH "repos/$repo/pulls/$pr_number" \
    -f title="$title" \
    -f body="$body" >/dev/null
}

dayflow_path_matches_scope() {
  local path="$1"
  local scope="$2"
  [[ "$path" == "$scope" || "$path" == "$scope/"* ]]
}

dayflow_validate_changed_paths() {
  local issue_json="$1"
  local worktree="$2"
  local description scopes path scope matched
  description="$(jq -r '.description // ""' <<<"$issue_json")"
  scopes="$(dayflow_write_scopes "$description")"
  if dayflow_parallel_safe "$description" && [[ -z "$scopes" ]]; then
    dayflow_error 'Parallel Safe issues require a non-empty Write Scope'
    return 1
  fi
  [[ -n "$scopes" ]] || return 0

  while IFS= read -r path; do
    [[ -n "$path" ]] || continue
    matched=false
    while IFS= read -r scope; do
      [[ -n "$scope" ]] || continue
      if dayflow_path_matches_scope "$path" "$scope"; then
        matched=true
        break
      fi
    done <<<"$scopes"
    [[ "$matched" == "true" ]] || {
      dayflow_error "changed path is outside declared Write Scope: $path"
      return 1
    }
  done < <({
    git -C "$worktree" diff --name-only
    git -C "$worktree" diff --cached --name-only
    git -C "$worktree" ls-files --others --exclude-standard
  } | awk 'NF && !seen[$0]++')
}

dayflow_validate_test_evidence() {
  local output_file="$1"
  jq -ce 'select(
    type == "object"
    and ((keys | sort) == ["summary", "tests"])
    and (.summary | type == "string" and length >= 1 and length <= 500)
    and (.tests | type == "array" and length >= 1 and length <= 8)
    and all(.tests[];
      type == "object"
      and ((keys | sort) == ["name", "status"])
      and (.name | type == "string" and length >= 1 and length <= 160)
      and .status == "passed"))
  ' "$output_file"
}

dayflow_store_test_evidence() {
  local issue_key="$1"
  local output_file="$2"
  local review_context="$3"
  local evidence
  evidence="$(dayflow_validate_test_evidence "$output_file")" || {
    dayflow_error 'primary output lacks valid passed test evidence'
    return 1
  }
  dayflow_state_update "$issue_key" --argjson evidence "$evidence" --arg context "$review_context" --arg at "$(dayflow_now_iso)" '
    .test_evidence = $evidence
    | .publication = {phase: "edited", review_context: $context}
    | .status = "publication-retry"
    | .updated_at = $at
    | del(.last_error)'
}

dayflow_is_publication_recovery() {
  local issue_key="$1"
  local state_file
  state_file="$(dayflow_state_file "$issue_key")"
  [[ -f "$state_file" ]] || return 1
  [[ "$(jq -r '.status // ""' "$state_file")" == "publication-retry" ]]
}

dayflow_is_token_accounting_recovery() {
  local issue_key="$1"
  local state_file
  state_file="$(dayflow_state_file "$issue_key")"
  [[ -f "$state_file" ]] || return 1
  [[ "$(jq -r '.status // ""' "$state_file")" == "token-accounting-recovery" ]]
}

dayflow_reconcile_token_accounting() {
  local issue_key="$1"
  local state_file status last_error billable log_file output_file session_id evidence worktree branch persisted_branch usage raw_total
  local -a primary_logs=()

  state_file="$(dayflow_state_file "$issue_key")"
  [[ -f "$state_file" ]] || return 1
  status="$(jq -r '.status // ""' "$state_file")"
  last_error="$(jq -r '.last_error // ""' "$state_file")"
  [[ "$status" == "blocked" && "$last_error" == token\ limit\ exceeded* ]] || return 1
  while IFS= read -r log_file; do
    output_file="${log_file%.jsonl}.out"
    [[ -f "$output_file" ]] && primary_logs+=("$log_file")
  done < <(find "$DAYFLOW_LOG_ROOT" -maxdepth 1 -type f -name "${issue_key}-*-primary.jsonl" -print 2>/dev/null | sort)
  [[ "${#primary_logs[@]}" == "1" ]] || {
    dayflow_error "$issue_key token recovery requires exactly one retained primary log and output"
    return 2
  }
  log_file="${primary_logs[0]}"
  output_file="${log_file%.jsonl}.out"
  session_id="$(dayflow_jsonl_session_id "$log_file")"
  [[ -n "$session_id" ]] || {
    dayflow_error "$issue_key token recovery requires the retained primary session id"
    return 2
  }
  evidence="$(dayflow_validate_test_evidence "$output_file")" || {
    dayflow_error "$issue_key token recovery primary output lacks valid passed test evidence"
    return 2
  }
  worktree="$(jq -r '.worktree // ""' "$state_file")"
  persisted_branch="$(jq -r '.branch // ""' "$state_file")"
  [[ "$worktree" == "$DAYFLOW_WORKTREE_ROOT/$issue_key" && -e "$worktree/.git" && -n "$persisted_branch" ]] || {
    dayflow_error "$issue_key token recovery worktree is not owned by this issue"
    return 2
  }
  branch="$(git -C "$worktree" branch --show-current)"
  [[ "$branch" == "$persisted_branch" ]] || {
    dayflow_error "$issue_key token recovery branch does not match persisted ownership"
    return 2
  }
  usage="$(dayflow_jsonl_usage "$log_file")"
  billable="$(jq -r '.billable_tokens' <<<"$usage")"
  raw_total="$(jq -r '.raw_total_tokens' <<<"$usage")"
  (( billable < DAYFLOW_TOKEN_LIMIT )) || return 1
  jq -e --argjson retained "$usage" '
    (.primary_agent | type) == "string" and (.primary_agent | length) > 0
    and (.model | type) == "string" and (.model | length) > 0
    and (.reasoning | type) == "string" and (.reasoning | length) > 0
    and (.base_branch | type) == "string" and (.base_branch | length) > 0
    and (.usage.input_tokens | type) == "number" and .usage.input_tokens >= 0
    and (.usage.cached_input_tokens | type) == "number" and .usage.cached_input_tokens >= 0
    and (.usage.uncached_input_tokens | type) == "number" and .usage.uncached_input_tokens >= 0
    and (.usage.output_tokens | type) == "number" and .usage.output_tokens >= 0
    and (.usage.cached_input_tokens <= .usage.input_tokens)
    and (.usage.uncached_input_tokens == (.usage.input_tokens - .usage.cached_input_tokens))
    and (.usage.input_tokens == $retained.input_tokens)
    and (.usage.cached_input_tokens == $retained.cached_input_tokens)
    and (.usage.uncached_input_tokens == $retained.uncached_input_tokens)
    and (.usage.output_tokens == $retained.output_tokens)
    and (if (.billable_tokens | type) == "number" then .billable_tokens == $retained.billable_tokens else true end)
    and (if (.usage.billable_tokens | type) == "number" then .usage.billable_tokens == $retained.billable_tokens else true end)
  ' "$state_file" >/dev/null || {
    dayflow_error "$issue_key token recovery usage does not match the retained primary log"
    return 2
  }
  dayflow_allowed_base_branch "$(jq -r '.base_branch' "$state_file")" || return 2
  dayflow_state_update "$issue_key" \
    --arg session "$session_id" \
    --argjson evidence "$evidence" \
    --argjson billable "$billable" \
    --argjson raw_total "$raw_total" \
    --arg at "$(dayflow_now_iso)" \
    '.billable_tokens = $billable
     | .usage.raw_total_tokens = $raw_total
     | .usage.billable_tokens = $billable
     | .session_id = $session
     | .test_evidence = $evidence
     | .publication = {phase: "edited", review_context: "Recovered retained primary output after cached-context token accounting correction."}
     | .status = "token-accounting-recovery"
     | .last_error = "Recovered false token-limit block; retained primary output is ready for deterministic publication."
     | .token_accounting_reconciled_at = $at
     | del(.tokens_used)'
  return 0
}

dayflow_mark_publication_retry() {
  local issue_key="$1"
  local reason="$2"
  dayflow_state_update "$issue_key" --arg reason "$reason" --arg at "$(dayflow_now_iso)" \
    '.status = "publication-retry" | .last_error = $reason | .updated_at = $at'
}

dayflow_defer_owned_recovery() {
  local issue_key="$1"
  local recovery_status="$2"
  local reason="$3"
  dayflow_state_update "$issue_key" --arg status "$recovery_status" --arg reason "$reason" --arg at "$(dayflow_now_iso)" \
    '.status = $status | .last_error = $reason | .updated_at = $at'
  dayflow_notify "DayFlow ${issue_key} recovery deferred" "$reason" 15158332 || true
}

dayflow_mark_running() {
  local issue_key="$1"
  local issue_id="$2"
  local title="$3"
  local primary="$4"
  local model="$5"
  local reasoning="$6"
  local branch="$7"
  local worktree="$8"
  local base_branch="$9"
  dayflow_state_update "$issue_key" \
    --arg issue "$issue_key" --arg id "$issue_id" --arg title "$title" --arg agent "$primary" \
    --arg model "$model" --arg reasoning "$reasoning" --arg branch "$branch" --arg worktree "$worktree" --arg base "$base_branch" \
    --arg at "$(dayflow_now_iso)" \
    '. + {issue: $issue, issue_id: $id, title: $title, primary_agent: $agent, model: $model, reasoning: $reasoning, branch: $branch, base_branch: $base, worktree: $worktree, status: "running", updated_at: $at}
     | .billable_tokens = (
         if (.billable_tokens | type) == "number" and .billable_tokens >= 0 then .billable_tokens
         elif (.usage.billable_tokens | type) == "number" and .usage.billable_tokens >= 0 then .usage.billable_tokens
         elif ((.usage.uncached_input_tokens | type) == "number" and .usage.uncached_input_tokens >= 0
           and (.usage.output_tokens | type) == "number" and .usage.output_tokens >= 0) then
           (.usage.uncached_input_tokens + .usage.output_tokens)
         else 0
         end)
     | del(.tokens_used)'
}

dayflow_record_fresh_session() {
  local issue_key="$1"
  local log_file="$2"
  local session_id
  session_id="$(dayflow_jsonl_session_id "$log_file")"
  [[ -n "$session_id" ]] || {
    dayflow_error 'Codex completed without a new session id.'
    return 1
  }
  dayflow_state_update "$issue_key" --arg session "$session_id" --arg at "$(dayflow_now_iso)" '
    .session_id = $session
    | .session_history = (((.session_history // []) + [$session]) | unique | .[-8:])
    | .updated_at = $at'
}

dayflow_mark_publication_unsafe() {
  local issue_key="$1"
  local reason="$2"
  dayflow_state_update "$issue_key" --arg reason "$reason" --arg at "$(dayflow_now_iso)" \
    '.publication.failure = "unsafe" | .last_error = $reason | .updated_at = $at'
  dayflow_error "$reason"
  return 1
}

dayflow_write_pr_proof() {
  local issue_key="$1"
  local title="$2"
  local worktree="$3"
  local body_file="$4"
  local review_context="$5"
  local base_branch="$6"
  local short_title files shortstat evidence
  short_title="$(printf '%s' "$title" | sed -E 's/^\[[^]]+\][[:space:]]*//')"
  files="$(git -C "$worktree" diff --name-only "origin/$base_branch...HEAD" | head -n 100)"
  shortstat="$(git -C "$worktree" diff --shortstat "origin/$base_branch...HEAD" | sed -E 's/^[[:space:]]+//')"
  [[ -n "$shortstat" ]] || shortstat='No textual diff statistics available.'
  evidence="$(jq -c '.test_evidence' "$(dayflow_state_file "$issue_key")")"
  {
    printf '# %s: %s\n\n' "$issue_key" "$short_title"
    printf '## Changed files\n\n'
    printf '%s\n' "$files" | sed 's/^/- `/' | sed 's/$/`/'
    printf '\n## Behavior implemented\n\n- Issue-scoped changes were produced by the bounded primary edit/test session and published deterministically by the DayFlow runner.\n'
    printf '\n## Tests run\n\n'
    jq -r '.tests[] | "- " + .name + " (`" + .status + "`)"' <<<"$evidence"
    printf '\n## Review feedback addressed\n\n- %s\n' "$review_context"
    printf '\n## Complexity snapshot\n\n- %s\n' "$shortstat"
    printf '\n## Risks or follow-ups\n\n- Automated review and CI remain required before merge readiness.\n'
    printf '\n## Next suggested issue\n\n- Dispatch the next dependency-eligible Linear Todo issue after this PR merges.\n'
  } >"$body_file"
}

dayflow_publish_issue_changes() {
  local issue_json="$1"
  local branch="$2"
  local worktree="$3"
  local review_context="${4:-Not applicable before automated review.}"
  local issue_key title description base_branch commit_title body_file repo prs pr_number phase local_head remote_head remote_sha expected_subject pr_json
  issue_key="$(jq -r '.identifier' <<<"$issue_json")"
  title="$(jq -r '.title' <<<"$issue_json")"
  description="$(jq -r '.description // ""' <<<"$issue_json")"
  base_branch="$(dayflow_integration_base_branch "$description")" || return 1
  commit_title="$(printf '%s' "$title" | sed -E 's/^\[[^]]+\][[:space:]]*//' | cut -c1-68)"
  expected_subject="feat(${issue_key}): ${commit_title}"
  [[ "$worktree" == "$DAYFLOW_WORKTREE_ROOT/$issue_key" && "$(git -C "$worktree" branch --show-current)" == "$branch" ]] || {
    dayflow_mark_publication_unsafe "$issue_key" 'publication worktree or branch ownership mismatch'
    return
  }
  [[ -z "$(git -C "$worktree" diff --cached --name-only)" ]] || {
    dayflow_mark_publication_unsafe "$issue_key" 'model session modified the Git index; publication fails closed'
    return
  }
  phase="$(dayflow_state_value "$issue_key" '.publication.phase // ""')"
  case "$phase" in edited|committed|pushed|pr-created) ;; *) dayflow_mark_publication_unsafe "$issue_key" 'publication phase is missing or invalid'; return ;; esac
  if [[ -n "$(git -C "$worktree" status --porcelain --untracked-files=normal)" ]]; then
    [[ "$phase" == "edited" ]] || { dayflow_mark_publication_unsafe "$issue_key" 'published worktree became dirty'; return; }
    dayflow_validate_changed_paths "$issue_json" "$worktree" || { dayflow_mark_publication_unsafe "$issue_key" 'changed paths violate publication ownership'; return; }
    git -C "$worktree" diff --check || { dayflow_mark_publication_unsafe "$issue_key" 'publication diff validation failed'; return; }
    git -C "$worktree" add -A || return 1
    git -C "$worktree" diff --cached --quiet && { dayflow_error 'no staged issue changes remain after deterministic staging'; return 1; }
    git -C "$worktree" commit -m "$expected_subject" >/dev/null || return 1
  elif [[ "$phase" == "edited" ]]; then
    [[ "$(git -C "$worktree" log -1 --format=%s)" == "$expected_subject" ]] || {
      dayflow_mark_publication_unsafe "$issue_key" 'clean publication recovery does not match the deterministic commit'
      return
    }
  fi
  local_head="$(git -C "$worktree" rev-parse HEAD)"
  if [[ "$phase" == "edited" ]]; then
    dayflow_state_update "$issue_key" --arg head "$local_head" --arg at "$(dayflow_now_iso)" \
      '.publication.phase = "committed" | .publication.head_sha = $head | .updated_at = $at'
    phase=committed
  else
    [[ "$(dayflow_state_value "$issue_key" '.publication.head_sha // ""')" == "$local_head" ]] || {
      dayflow_mark_publication_unsafe "$issue_key" 'publication HEAD differs from persisted publication head'
      return
    }
  fi

  remote_head="$(git -C "$worktree" ls-remote --heads origin "refs/heads/$branch")"
  remote_sha="$(awk 'NR == 1 {print $1}' <<<"$remote_head")"
  if [[ -n "$remote_sha" && "$remote_sha" != "$local_head" ]] && \
     ! { [[ "$phase" == "committed" ]] && git -C "$worktree" merge-base --is-ancestor "$remote_sha" "$local_head"; }; then
    dayflow_mark_publication_unsafe "$issue_key" 'remote publication branch differs from local HEAD; refusing non-fast-forward recovery'
    return
  fi
  if [[ "$remote_sha" != "$local_head" ]]; then
    dayflow_git_publish "$worktree" push -u origin "HEAD:refs/heads/$branch" >/dev/null || return 1
  fi
  if [[ "$phase" == "committed" ]]; then
    dayflow_state_update "$issue_key" --arg at "$(dayflow_now_iso)" '.publication.phase = "pushed" | .updated_at = $at'
    phase=pushed
  fi

  body_file="$DAYFLOW_LOG_ROOT/${issue_key}-pr-body.md"
  review_context="$(dayflow_state_value "$issue_key" '.publication.review_context // "Not applicable before automated review."')"
  dayflow_write_pr_proof "$issue_key" "$title" "$worktree" "$body_file" "$review_context" "$base_branch"
  repo="$(dayflow_github_repo)"
  prs="$(dayflow_pr_for_branch "$branch" open)" || return 1
  pr_number="$(jq -r '.[0].number // empty' <<<"$prs")"
  if [[ -n "$pr_number" ]]; then
    pr_json="$(jq -ce --arg branch "$branch" --arg base "$base_branch" --arg head "$local_head" '.[0] | select(.headRefName == $branch and .baseRefName == $base and .headRefOid == $head)' <<<"$prs")" || {
      dayflow_mark_publication_unsafe "$issue_key" 'existing PR does not match publication branch, base, and head'
      return
    }
    dayflow_update_pr "$repo" "$pr_number" "${issue_key}: ${commit_title}" "$body_file" || return 1
    if [[ "$(jq -r '.[0].isDraft // true' <<<"$prs")" != "true" ]]; then
      dayflow_gh pr ready -R "$repo" --undo "$pr_number" >/dev/null || return 1
    fi
  else
    dayflow_gh pr create -R "$repo" --draft --base "$base_branch" --head "$branch" \
      --title "${issue_key}: ${commit_title}" --body-file "$body_file" >/dev/null || return 1
  fi
  dayflow_state_update "$issue_key" --arg at "$(dayflow_now_iso)" '.publication.phase = "pr-created" | .updated_at = $at'
  dayflow_validate_delivery "$issue_key" "$branch" "$worktree" "$base_branch"
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
  local base_branch="$4"
  local current_branch commit_count local_head remote_head remote_sha pr_head prs pr_json body
  current_branch="$(git -C "$worktree" branch --show-current)"
  [[ "$current_branch" == "$branch" ]] || {
    dayflow_error "delivery branch mismatch: $current_branch"
    return 1
  }
  [[ -z "$(git -C "$worktree" status --porcelain --untracked-files=normal)" ]] || {
    dayflow_error 'delivery worktree is dirty'
    return 1
  }
  dayflow_allowed_base_branch "$base_branch" || return 1
  commit_count="$(git -C "$worktree" rev-list --count "origin/$base_branch..HEAD")"
  (( commit_count > 0 )) || {
    dayflow_error "delivery has no commits beyond origin/$base_branch"
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
  pr_json="$(jq -ce --arg base "$base_branch" '.[0] | select(.baseRefName == $base)' <<<"$prs")" || {
    dayflow_error "delivery has no open PR targeting $base_branch"
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

dayflow_ensure_pr_draft() {
  local pr_json="$1"
  local pr_number
  [[ "$(jq -r '.isDraft' <<<"$pr_json")" == "true" ]] && return 0
  pr_number="$(jq -r '.number' <<<"$pr_json")"
  dayflow_gh pr ready -R "$(dayflow_github_repo)" --undo "$pr_number" >/dev/null
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

dayflow_current_requested_changes() {
  local pr_number="$1"
  local repo detail
  repo="$(dayflow_github_repo)"
  detail="$(dayflow_gh pr view -R "$repo" "$pr_number" --json reviews,commits)"
  jq -ce '
    ((.commits | last | .committedDate) // "") as $latest
    | (.reviews // [] | map(select(.submittedAt != null and .author.login != null and .state != "COMMENTED"))
      | sort_by(.submittedAt) | group_by(.author.login) | map(last)
      | map(select(.submittedAt >= $latest and .state == "CHANGES_REQUESTED"))
      | map({author: .author.login, submitted_at: .submittedAt, body: ((.body // "")[:2000])})
      | .[:8]) as $reviews
    | select(($reviews | length) > 0)
    | {reviews: $reviews}
  ' <<<"$detail"
}

dayflow_has_requested_changes() {
  dayflow_current_requested_changes "$1" >/dev/null
}

dayflow_record_merge_ready() {
  local issue_key="$1"
  local pr_number="$2"
  local pr_url="$3"
  local head_sha="$4"
  local existing tmp
  dayflow_acquire_merge_ready_lock || return 1
  if ! existing="$(jq -r --arg key "$issue_key" --arg pr "$pr_number" '.[$key].head_sha? // .[$pr].head_sha? // ""' "$DAYFLOW_MERGE_READY_STORE")"; then
    dayflow_release_merge_ready_lock
    return 1
  fi
  if [[ "$existing" == "$head_sha" ]]; then
    dayflow_release_merge_ready_lock
    return 0
  fi
  if ! dayflow_notify "DayFlow ${issue_key} merge-ready" "PR #${pr_number} is ready to merge.\n${pr_url}" 5763719; then
    dayflow_release_merge_ready_lock
    return 1
  fi
  tmp="${DAYFLOW_MERGE_READY_STORE}.tmp.$$"
  if ! jq --arg key "$issue_key" --arg sha "$head_sha" --argjson pr "$pr_number" --arg at "$(dayflow_now_iso)" \
    '.[$key] = {head_sha: $sha, pr_number: $pr, notified_at: $at}' "$DAYFLOW_MERGE_READY_STORE" >"$tmp"; then
    rm -f "$tmp"
    dayflow_release_merge_ready_lock
    return 1
  fi
  if ! mv "$tmp" "$DAYFLOW_MERGE_READY_STORE"; then
    rm -f "$tmp"
    dayflow_release_merge_ready_lock
    return 1
  fi
  dayflow_release_merge_ready_lock
}

dayflow_reconcile_one() {
  local issue_key="$1"
  local state_file issue_json issue_id branch expected_base persisted_base prs pr_json pr_number pr_url head_sha reviewed_head_sha
  local is_draft pr_state current_state base_branch head_branch merge_state requested_changes
  state_file="$(dayflow_state_file "$issue_key")"
  [[ -f "$state_file" ]] || {
    dayflow_error "no local state for $issue_key"
    return 1
  }
  issue_json="$(dayflow_linear_issue "$issue_key")" || return 1
  issue_id="$(jq -r '.id' <<<"$issue_json")"
  current_state="$(jq -r '.state.name' <<<"$issue_json")"
  expected_base="$(dayflow_integration_base_branch "$(jq -r '.description // ""' <<<"$issue_json")")" || return 1
  branch="$(jq -r '.branch // ""' "$state_file")"
  persisted_base="$(jq -r '.base_branch // "develop"' "$state_file")"
  [[ "$persisted_base" == "$expected_base" ]] || {
    dayflow_error "$issue_key persisted base branch no longer matches Linear metadata"
    return 1
  }
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

  [[ "$base_branch" == "$expected_base" && "$head_branch" == "$branch" ]] || {
    dayflow_error "$issue_key PR is not the tracked base delivery"
    return 1
  }

  if [[ "$pr_state" == "MERGED" ]]; then
    if [[ -z "$reviewed_head_sha" || "$head_sha" != "$reviewed_head_sha" ]]; then
      dayflow_state_update "$issue_key" --arg head "$head_sha" --arg reviewed "$reviewed_head_sha" --arg at "$(dayflow_now_iso)" \
        '.status = "merged-review-mismatch" | .last_error = "merged PR head does not match the persisted reviewed head" | .merged_head_sha = $head | .reviewed_head_sha = $reviewed | .updated_at = $at'
      dayflow_error "$issue_key merged PR head does not match the persisted reviewed head"
      return 1
    fi
    if ! dayflow_linear_set_state "$issue_id" "$DAYFLOW_STATE_DONE_NAME"; then
      dayflow_error "$issue_key Linear rejected the Done transition"
      return 1
    fi
    dayflow_state_update "$issue_key" --arg at "$(dayflow_now_iso)" '.status = "done" | .updated_at = $at'
    return 0
  fi

  if requested_changes="$(dayflow_current_requested_changes "$pr_number")"; then
    if [[ "$is_draft" != "true" ]]; then
      dayflow_gh pr ready -R "$(dayflow_github_repo)" --undo "$pr_number" >/dev/null
    fi
    dayflow_linear_set_state "$issue_id" "$DAYFLOW_STATE_IN_PROGRESS_NAME"
    dayflow_state_update "$issue_key" --argjson feedback "$requested_changes" --arg head "$head_sha" --arg at "$(dayflow_now_iso)" '
      .status = "review-changes"
      | .reviewed_head_sha = $head
      | .requested_changes = ($feedback + {reviewed_head_sha: $head})
      | .updated_at = $at'
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
  local issue_json issue_id title description linear_state primary model_route model reasoning branch base_branch worktree session_id mode execution_phase
  local timestamp prompt_file log_file output_file pr_json pr_number review_prompt review_log review_output
  local review_round=1 findings_comment remediation_prompt remediation_log remediation_output repo
  local pre_session_recovery=false publication_recovery=false requested_changes_recovery=false token_accounting_recovery=false recovery_status=""

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
  base_branch="$(dayflow_integration_base_branch "$description")" || return 1
  model_route="$(dayflow_model_for_agent "$primary")"
  read -r model reasoning <<<"$model_route"
  branch="$(dayflow_branch_name "$issue_key" "$title")"
  if dayflow_is_pre_session_recovery "$issue_key"; then
    pre_session_recovery=true
  fi
  if dayflow_is_publication_recovery "$issue_key"; then
    publication_recovery=true
  fi
  if dayflow_is_token_accounting_recovery "$issue_key"; then
    token_accounting_recovery=true
  fi
  if [[ -f "$(dayflow_state_file "$issue_key")" && "$(dayflow_state_value "$issue_key" '.status // ""')" == "review-changes" ]]; then
    requested_changes_recovery=true
  fi
  if [[ "$publication_recovery" == "true" ]]; then
    recovery_status="publication-retry"
  elif [[ "$token_accounting_recovery" == "true" ]]; then
    recovery_status="token-accounting-recovery"
  elif [[ "$requested_changes_recovery" == "true" ]]; then
    recovery_status="review-changes"
  fi

  if [[ "$DAYFLOW_DRY_RUN" == "true" ]]; then
    if [[ "$publication_recovery" == "true" || "$requested_changes_recovery" == "true" || "$token_accounting_recovery" == "true" ]]; then
      dayflow_validate_resume_state "$issue_key" "$branch" "$primary" "$model" "$reasoning" true "$base_branch" >/dev/null || return 1
    elif [[ "$pre_session_recovery" == "true" ]]; then
      case "$linear_state" in
        "$DAYFLOW_STATE_TODO_NAME"|"$DAYFLOW_STATE_BLOCKED_NAME"|"$DAYFLOW_STATE_IN_PROGRESS_NAME")
          dayflow_validate_pre_session_recovery "$issue_key" "$branch" "$primary" "$model" "$reasoning" "$base_branch" >/dev/null || return 1
          ;;
        *) dayflow_error "pre-session recovery is not runnable from issue state: $linear_state"; return 1 ;;
      esac
    else
      case "$linear_state" in
        "$DAYFLOW_STATE_TODO_NAME") ;;
        "$DAYFLOW_STATE_IN_PROGRESS_NAME"|"$DAYFLOW_STATE_IN_REVIEW_NAME")
          dayflow_validate_resume_state "$issue_key" "$branch" "$primary" "$model" "$reasoning" false "$base_branch" >/dev/null || return 1
          ;;
        *) dayflow_error "issue state is not runnable: $linear_state"; return 1 ;;
      esac
    fi
    jq -n --arg issue "$issue_key" --arg state "$linear_state" --arg agent "$primary" \
      --arg model "$model" --arg reasoning "$reasoning" --arg branch "$branch" --arg base "$base_branch" \
      --argjson recovery "$pre_session_recovery" \
      '{dry_run: true, issue: $issue, state: $state, primary_agent: $agent, model: $model, reasoning: $reasoning, branch: $branch, base_branch: $base, pre_session_recovery: $recovery}'
    return 0
  fi

  dayflow_acquire_lock "$issue_key" || return 1
  dayflow_install_cleanup_traps
  if [[ "$publication_recovery" == "true" ]]; then
    case "$linear_state" in
      "$DAYFLOW_STATE_TODO_NAME"|"$DAYFLOW_STATE_BLOCKED_NAME"|"$DAYFLOW_STATE_IN_PROGRESS_NAME"|"$DAYFLOW_STATE_IN_REVIEW_NAME") ;;
      *) dayflow_error "publication recovery is not runnable from issue state: $linear_state"; return 1 ;;
    esac
    worktree="$(dayflow_validate_resume_state "$issue_key" "$branch" "$primary" "$model" "$reasoning" true "$base_branch")" || return 1
    session_id="$(dayflow_state_value "$issue_key" '.session_id')"
    mode="primary-resume"
  elif [[ "$token_accounting_recovery" == "true" ]]; then
    case "$linear_state" in
      "$DAYFLOW_STATE_BLOCKED_NAME"|"$DAYFLOW_STATE_IN_PROGRESS_NAME") ;;
      *) dayflow_error "token-accounting recovery is not runnable from issue state: $linear_state"; return 1 ;;
    esac
    worktree="$(dayflow_validate_resume_state "$issue_key" "$branch" "$primary" "$model" "$reasoning" true "$base_branch")" || return 1
    session_id="$(dayflow_state_value "$issue_key" '.session_id')"
    mode="primary-resume"
  elif [[ "$requested_changes_recovery" == "true" ]]; then
    case "$linear_state" in
      "$DAYFLOW_STATE_TODO_NAME"|"$DAYFLOW_STATE_IN_PROGRESS_NAME"|"$DAYFLOW_STATE_IN_REVIEW_NAME") ;;
      *) dayflow_error "requested-changes recovery is not runnable from issue state: $linear_state"; return 1 ;;
    esac
    worktree="$(dayflow_validate_resume_state "$issue_key" "$branch" "$primary" "$model" "$reasoning" true "$base_branch")" || return 1
    session_id=""
    mode="primary-fresh"
    execution_phase="remediation"
  elif dayflow_is_pre_session_recovery "$issue_key"; then
    case "$linear_state" in
      "$DAYFLOW_STATE_TODO_NAME"|"$DAYFLOW_STATE_BLOCKED_NAME"|"$DAYFLOW_STATE_IN_PROGRESS_NAME") ;;
      *) dayflow_error "pre-session recovery is not runnable from issue state: $linear_state"; return 1 ;;
    esac
    worktree="$(dayflow_validate_pre_session_recovery "$issue_key" "$branch" "$primary" "$model" "$reasoning" "$base_branch")" || return 1
    session_id=""
    mode="primary-new"
  else
    case "$linear_state" in
      "$DAYFLOW_STATE_TODO_NAME")
        worktree="$(dayflow_prepare_new_worktree "$issue_key" "$branch" "$base_branch")" || return 1
        session_id=""
        mode="primary-new"
        ;;
      "$DAYFLOW_STATE_IN_PROGRESS_NAME"|"$DAYFLOW_STATE_IN_REVIEW_NAME")
        worktree="$(dayflow_validate_resume_state "$issue_key" "$branch" "$primary" "$model" "$reasoning" false "$base_branch")" || return 1
        session_id=""
        mode="primary-fresh"
        ;;
      *)
        dayflow_error "issue state is not runnable: $linear_state"
        return 1
        ;;
    esac
  fi

  if [[ -z "$recovery_status" ]]; then
    dayflow_mark_running "$issue_key" "$issue_id" "$title" "$primary" "$model" "$reasoning" "$branch" "$worktree" "$base_branch"
  fi
  if ! dayflow_validate_publication_capability "$worktree" "$branch"; then
    if [[ -n "$recovery_status" ]]; then
      dayflow_defer_owned_recovery "$issue_key" "$recovery_status" 'GitHub publication capability preflight failed during owned recovery.'
    else
      dayflow_state_update "$issue_key" --arg at "$(dayflow_now_iso)" \
        '.status = "pre-session-blocked" | .last_error = "GitHub publication capability preflight failed before Codex launch" | .updated_at = $at | del(.session_id)'
      dayflow_linear_set_state "$issue_id" "$DAYFLOW_STATE_BLOCKED_NAME" || true
      dayflow_notify_state "$issue_key" "$DAYFLOW_STATE_BLOCKED_NAME" 'GitHub publication capability preflight failed before Codex launch; clean workspace preserved.'
    fi
    return 1
  fi
  if ! dayflow_linear_set_state "$issue_id" "$DAYFLOW_STATE_IN_PROGRESS_NAME"; then
    if [[ -n "$recovery_status" ]]; then
      dayflow_defer_owned_recovery "$issue_key" "$recovery_status" 'Linear In Progress transition failed during owned recovery.'
    else
      dayflow_state_update "$issue_key" --arg at "$(dayflow_now_iso)" \
        '.status = "pre-session-blocked" | .last_error = "Linear In Progress transition failed before Codex launch" | .updated_at = $at | del(.session_id)'
      dayflow_linear_set_state "$issue_id" "$DAYFLOW_STATE_BLOCKED_NAME" || true
      dayflow_notify_state "$issue_key" "$DAYFLOW_STATE_BLOCKED_NAME" "Linear In Progress transition failed before Codex launch; workspace preserved."
    fi
    return 1
  fi
  if [[ -n "$recovery_status" ]]; then
    dayflow_mark_running "$issue_key" "$issue_id" "$title" "$primary" "$model" "$reasoning" "$branch" "$worktree" "$base_branch"
  fi
  if [[ "$publication_recovery" != "true" && "$token_accounting_recovery" != "true" ]]; then
    dayflow_notify_state "$issue_key" "$DAYFLOW_STATE_IN_PROGRESS_NAME" "Primary agent ${primary} started with ${model}/${reasoning}."
  fi

  timestamp="$(date -u +%Y%m%dT%H%M%SZ)"
  prompt_file="$DAYFLOW_LOG_ROOT/${issue_key}-${timestamp}-primary.prompt"
  log_file="$DAYFLOW_LOG_ROOT/${issue_key}-${timestamp}-primary.jsonl"
  output_file="$DAYFLOW_LOG_ROOT/${issue_key}-${timestamp}-primary.out"
  if [[ "$publication_recovery" != "true" && "$token_accounting_recovery" != "true" ]]; then
    if [[ "$requested_changes_recovery" == "true" ]]; then
      {
        printf 'Address only the current GitHub requested changes below in a fresh, bounded session. Make a concrete issue-scoped worktree change, run focused tests, and return the required structured test-evidence JSON. Do not stage, commit, push, use gh, or change lifecycle state.\n\n'
        jq '.requested_changes' "$(dayflow_state_file "$issue_key")"
      } >"$prompt_file"
    else
      dayflow_issue_prompt "$issue_json" "$primary" >"$prompt_file"
    fi
    if ! dayflow_execute_bounded "$issue_key" "$mode" "$worktree" "$model" "$reasoning" "$session_id" "$prompt_file" "$log_file" "$output_file" "$execution_phase"; then
      dayflow_block_issue "$issue_json" "$DAYFLOW_EXECUTION_ERROR"
      return 1
    fi
    if [[ "$mode" == "primary-new" || "$mode" == "primary-fresh" ]]; then
      if ! dayflow_record_fresh_session "$issue_key" "$log_file"; then
        dayflow_block_issue "$issue_json" 'Codex completed without a new session id.'
        return 1
      fi
      session_id="$(dayflow_state_value "$issue_key" '.session_id')"
    fi
    if [[ "$requested_changes_recovery" == "true" && -z "$(git -C "$worktree" status --porcelain --untracked-files=normal)" ]]; then
      dayflow_block_issue "$issue_json" 'Requested-changes remediation produced no worktree change.'
      return 1
    fi
    if ! dayflow_store_test_evidence "$issue_key" "$output_file" "$([[ "$requested_changes_recovery" == "true" ]] && printf 'Current GitHub requested changes were addressed in a fresh bounded primary execution.' || printf 'Not applicable before automated review.')"; then
      dayflow_block_issue "$issue_json" 'Primary execution returned missing, malformed, or failed test evidence.'
      return 1
    fi
  fi

  if ! pr_json="$(dayflow_publish_issue_changes "$issue_json" "$branch" "$worktree")"; then
    if [[ "$(dayflow_state_value "$issue_key" '.publication.failure // ""')" == "unsafe" ]]; then
      dayflow_block_issue "$issue_json" 'Deterministic publication integrity validation failed.'
    else
      dayflow_mark_publication_retry "$issue_key" 'Deterministic publication failed after the primary edit/test session.'
    fi
    return 1
  fi
  pr_number="$(jq -r '.number' <<<"$pr_json")"
  if ! dayflow_ensure_pr_draft "$pr_json"; then
    dayflow_block_issue "$issue_json" 'Unable to return the delivery PR to draft before automated review.'
    return 1
  fi
  pr_json="$(jq '.isDraft = true' <<<"$pr_json")"
  dayflow_state_update "$issue_key" --arg at "$(dayflow_now_iso)" \
    '.status = "reviewing" | del(.reviewed_head_sha, .unreviewed_head_sha) | .updated_at = $at'

  while (( review_round <= 2 )); do
    review_prompt="$DAYFLOW_LOG_ROOT/${issue_key}-${timestamp}-review-${review_round}.prompt"
    review_log="$DAYFLOW_LOG_ROOT/${issue_key}-${timestamp}-review-${review_round}.jsonl"
    review_output="$DAYFLOW_LOG_ROOT/${issue_key}-${timestamp}-review-${review_round}.json"
    dayflow_review_prompt "$issue_key" "$base_branch" >"$review_prompt"
    if ! dayflow_execute_bounded "$issue_key" review "$worktree" gpt-5.6-terra high "" "$review_prompt" "$review_log" "$review_output"; then
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
      printf 'Address only the P0-P2 review findings below, then re-run focused tests. Edit/test only: do not stage, commit, push, use gh, update proof, or change lifecycle state. Do not dump whole files, logs, trees, or repository diffs. The deterministic runner owns publication.\n\n'
      jq '.' "$review_output"
    } >"$remediation_prompt"
    if ! dayflow_execute_bounded "$issue_key" primary-fresh "$worktree" "$model" "$reasoning" "" "$remediation_prompt" "$remediation_log" "$remediation_output" remediation; then
      dayflow_block_issue "$issue_json" "$DAYFLOW_EXECUTION_ERROR"
      return 1
    fi
    if ! dayflow_record_fresh_session "$issue_key" "$remediation_log"; then
      dayflow_block_issue "$issue_json" 'Codex remediation completed without a new session id.'
      return 1
    fi
    if ! dayflow_store_test_evidence "$issue_key" "$remediation_output" 'Automated P0-P2 findings were addressed in one bounded remediation session.'; then
      dayflow_block_issue "$issue_json" 'Review remediation returned missing, malformed, or failed test evidence.'
      return 1
    fi
    pr_json="$(dayflow_publish_issue_changes "$issue_json" "$branch" "$worktree" 'Automated P0-P2 findings were addressed in one bounded remediation session.')" || {
      if [[ "$(dayflow_state_value "$issue_key" '.publication.failure // ""')" == "unsafe" ]]; then
        dayflow_block_issue "$issue_json" 'Deterministic remediation publication integrity validation failed.'
      else
        dayflow_mark_publication_retry "$issue_key" 'Deterministic publication failed after review remediation.'
      fi
      return 1
    }
    review_round=$((review_round + 1))
  done

  pr_json="$(dayflow_validate_delivery "$issue_key" "$branch" "$worktree" "$base_branch")" || {
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
  local state_file target rc=0 recovery_rc
  dayflow_install_cleanup_traps
  if [[ -n "$issue_key" ]]; then
    dayflow_validate_issue_key "$issue_key" || return 2
    dayflow_acquire_lock "$issue_key" || return 1
    if dayflow_reconcile_token_accounting "$issue_key"; then
      rc=0
    else
      recovery_rc=$?
      if [[ "$recovery_rc" == "1" ]]; then
        if dayflow_reconcile_one "$issue_key"; then rc=0; else rc=$?; fi
      else
        rc="$recovery_rc"
      fi
    fi
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
    if dayflow_reconcile_token_accounting "$target"; then
      :
    else
      recovery_rc=$?
      if [[ "$recovery_rc" == "1" ]]; then
        if ! dayflow_reconcile_one "$target"; then rc=1; fi
      else
        rc=1
      fi
    fi
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

  dayflow_require_commands bash git jq sed awk mktemp "$DAYFLOW_CURL_BIN" "$DAYFLOW_PERL_BIN" || return 1

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
