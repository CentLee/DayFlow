#!/usr/bin/env bash

DAYFLOW_SUPERVISOR_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/lib/dayflow_runner.sh
source "$DAYFLOW_SUPERVISOR_LIB_DIR/dayflow_runner.sh"

DAYFLOW_SUPERVISOR_MAX_PARALLEL_EXPLICIT="${DAYFLOW_SUPERVISOR_MAX_PARALLEL+x}"
DAYFLOW_SUPERVISOR_ROOT="${DAYFLOW_SUPERVISOR_ROOT:-$DAYFLOW_RUNTIME_DIR/supervisor}"
DAYFLOW_SUPERVISOR_CLAIM_ROOT="${DAYFLOW_SUPERVISOR_CLAIM_ROOT:-$DAYFLOW_SUPERVISOR_ROOT/claims}"
DAYFLOW_SUPERVISOR_LOCK_DIR="${DAYFLOW_SUPERVISOR_LOCK_DIR:-$DAYFLOW_SUPERVISOR_ROOT/once.lock}"
DAYFLOW_SUPERVISOR_SNAPSHOT="${DAYFLOW_SUPERVISOR_SNAPSHOT:-$DAYFLOW_SUPERVISOR_ROOT/queue.json}"
DAYFLOW_SUPERVISOR_RUNNER_BIN="${DAYFLOW_SUPERVISOR_RUNNER_BIN:-$ROOT_DIR/scripts/dayflow_runner.sh}"
DAYFLOW_SUPERVISOR_MAX_PARALLEL="${DAYFLOW_SUPERVISOR_MAX_PARALLEL:-1}"
DAYFLOW_SUPERVISOR_MAX_ISSUES="${DAYFLOW_SUPERVISOR_MAX_ISSUES:-100}"
DAYFLOW_SUPERVISOR_STALE_SECONDS="${DAYFLOW_SUPERVISOR_STALE_SECONDS:-300}"
DAYFLOW_SUPERVISOR_INTERVAL_SECONDS="${DAYFLOW_SUPERVISOR_INTERVAL_SECONDS:-60}"
DAYFLOW_SUPERVISOR_LAUNCHCTL_BIN="${DAYFLOW_SUPERVISOR_LAUNCHCTL_BIN:-launchctl}"
DAYFLOW_SUPERVISOR_PLIST_TEMPLATE="${DAYFLOW_SUPERVISOR_PLIST_TEMPLATE:-$ROOT_DIR/scripts/automation/com.dayflow.supervisor.plist.template}"
DAYFLOW_SUPERVISOR_PLIST="${DAYFLOW_SUPERVISOR_PLIST:-$DAYFLOW_SUPERVISOR_ROOT/com.dayflow.supervisor.plist}"
DAYFLOW_SUPERVISOR_ACTIVE_LOCK=""

dayflow_supervisor_error() {
  printf 'dayflow-supervisor: %s\n' "$*" >&2
}

dayflow_supervisor_initialize() {
  dayflow_initialize_runtime
  mkdir -p "$DAYFLOW_SUPERVISOR_ROOT" "$DAYFLOW_SUPERVISOR_CLAIM_ROOT"
  chmod 700 "$DAYFLOW_SUPERVISOR_ROOT" "$DAYFLOW_SUPERVISOR_CLAIM_ROOT" 2>/dev/null || true
}

dayflow_supervisor_validate_config() {
  [[ "$DAYFLOW_SUPERVISOR_MAX_PARALLEL" =~ ^[12]$ ]] || {
    dayflow_supervisor_error 'DAYFLOW_SUPERVISOR_MAX_PARALLEL must be 1 or 2'
    return 1
  }
  [[ "$DAYFLOW_SUPERVISOR_MAX_ISSUES" =~ ^[1-9][0-9]*$ ]] || {
    dayflow_supervisor_error 'DAYFLOW_SUPERVISOR_MAX_ISSUES must be a positive integer'
    return 1
  }
  [[ "$DAYFLOW_SUPERVISOR_STALE_SECONDS" =~ ^[1-9][0-9]*$ ]] || {
    dayflow_supervisor_error 'DAYFLOW_SUPERVISOR_STALE_SECONDS must be a positive integer'
    return 1
  }
}

dayflow_supervisor_acquire_lock() {
  local existing_pid="" existing_identity=""
  if mkdir "$DAYFLOW_SUPERVISOR_LOCK_DIR" 2>/dev/null; then
    printf '%s\n' "$$" >"$DAYFLOW_SUPERVISOR_LOCK_DIR/pid"
    dayflow_process_start_identity "$$" >"$DAYFLOW_SUPERVISOR_LOCK_DIR/process-start"
    DAYFLOW_SUPERVISOR_ACTIVE_LOCK="$DAYFLOW_SUPERVISOR_LOCK_DIR"
    return 0
  fi
  [[ -f "$DAYFLOW_SUPERVISOR_LOCK_DIR/pid" ]] && existing_pid="$(<"$DAYFLOW_SUPERVISOR_LOCK_DIR/pid")"
  [[ -f "$DAYFLOW_SUPERVISOR_LOCK_DIR/process-start" ]] && existing_identity="$(<"$DAYFLOW_SUPERVISOR_LOCK_DIR/process-start")"
  if dayflow_pid_identity_matches "$existing_pid" "$existing_identity"; then
    dayflow_supervisor_error "another supervisor invocation is active under pid $existing_pid"
    return 1
  fi
  rm -f "$DAYFLOW_SUPERVISOR_LOCK_DIR/pid" "$DAYFLOW_SUPERVISOR_LOCK_DIR/process-start"
  rmdir "$DAYFLOW_SUPERVISOR_LOCK_DIR" 2>/dev/null || {
    dayflow_supervisor_error 'unable to recover stale supervisor lock'
    return 1
  }
  mkdir "$DAYFLOW_SUPERVISOR_LOCK_DIR"
  printf '%s\n' "$$" >"$DAYFLOW_SUPERVISOR_LOCK_DIR/pid"
  dayflow_process_start_identity "$$" >"$DAYFLOW_SUPERVISOR_LOCK_DIR/process-start"
  DAYFLOW_SUPERVISOR_ACTIVE_LOCK="$DAYFLOW_SUPERVISOR_LOCK_DIR"
}

dayflow_supervisor_release_lock() {
  if [[ -n "$DAYFLOW_SUPERVISOR_ACTIVE_LOCK" && -d "$DAYFLOW_SUPERVISOR_ACTIVE_LOCK" ]]; then
    rm -f "$DAYFLOW_SUPERVISOR_ACTIVE_LOCK/pid" "$DAYFLOW_SUPERVISOR_ACTIVE_LOCK/process-start"
    rmdir "$DAYFLOW_SUPERVISOR_ACTIVE_LOCK" 2>/dev/null || true
  fi
  DAYFLOW_SUPERVISOR_ACTIVE_LOCK=""
}

dayflow_supervisor_exit_cleanup() {
  local status=$?
  trap - EXIT INT TERM
  dayflow_supervisor_release_lock
  exit "$status"
}

dayflow_supervisor_install_traps() {
  trap dayflow_supervisor_exit_cleanup EXIT
  trap 'exit 130' INT
  trap 'exit 143' TERM
}

dayflow_supervisor_fetch_issues() {
  local fixture_file="${DAYFLOW_SUPERVISOR_ISSUES_FILE:-}"
  local response query now tmp
  now="$(date +%s)"
  if [[ -n "$fixture_file" ]]; then
    jq -ce --argjson now "$now" '
      if type == "array" then {generated_epoch: $now, issues: .}
      else {generated_epoch: (.generated_epoch // $now), issues: (.issues // [])}
      end
      | .issues |= map({
          id: (.id // .identifier), identifier, title, description: (.description // ""),
          priority: (.priority // 0), updated_at: (.updated_at // .updatedAt // ""),
          state: (if (.state | type) == "object" then .state.name else .state end // ""), blockers: (.blockers // [])
        })
    ' "$fixture_file"
    return
  fi

  query="query { issues(first: ${DAYFLOW_SUPERVISOR_MAX_ISSUES}, filter: {team: {id: {eq: \"${DAYFLOW_LINEAR_TEAM_ID}\"}}}) { pageInfo { hasNextPage } nodes { id identifier title description priority updatedAt state { name } relations { nodes { type relatedIssue { identifier state { name } } } } inverseRelations { nodes { type relatedIssue { identifier state { name } } } } } } }"
  response="$(dayflow_linear_graphql "$query")" || return 1
  jq -e '(.errors // []) | length == 0' >/dev/null <<<"$response" || {
    jq -r '.errors[]?.message' <<<"$response" >&2
    return 1
  }
  jq -e '.data.issues.pageInfo.hasNextPage == false' >/dev/null <<<"$response" || {
    dayflow_supervisor_error "Linear issue result exceeds resource limit ${DAYFLOW_SUPERVISOR_MAX_ISSUES}"
    return 1
  }
  tmp="$(dayflow_supervisor_snapshot_from_response "$response" "$now")" || return 1
  printf '%s\n' "$tmp"
}

dayflow_supervisor_snapshot_from_response() {
  local response="$1"
  local now="$2"
  jq -ce --argjson now "$now" '
    {generated_epoch: $now, issues: [.data.issues.nodes[] | {
      id, identifier, title, description: (.description // ""), priority: (.priority // 0),
      updated_at: (.updatedAt // ""), state: (.state.name // ""),
      blockers: (
        [(.inverseRelations.nodes // [])[] | select(.type == "blocks") | {identifier: .relatedIssue.identifier, state: .relatedIssue.state.name}]
        + [(.relations.nodes // [])[] | select(.type == "blockedBy") | {identifier: .relatedIssue.identifier, state: .relatedIssue.state.name}]
      )
    }]}
  ' <<<"$response"
}

dayflow_supervisor_validate_snapshot() {
  local snapshot="$1"
  local now generated age count
  jq -e '.generated_epoch and (.issues | type == "array") and all(.issues[]; (.identifier | test("^CEN-[0-9]+$")) and (.state | length > 0) and (.blockers | type == "array"))' >/dev/null <<<"$snapshot" || {
    dayflow_supervisor_error 'Linear queue snapshot is malformed or incomplete'
    return 1
  }
  now="$(date +%s)"
  generated="$(jq -r '.generated_epoch' <<<"$snapshot")"
  [[ "$generated" =~ ^[0-9]+$ ]] || return 1
  age=$((now - generated))
  (( age >= 0 && age <= DAYFLOW_SUPERVISOR_STALE_SECONDS )) || {
    dayflow_supervisor_error "Linear queue snapshot is stale (${age}s)"
    return 1
  }
  count="$(jq '.issues | length' <<<"$snapshot")"
  (( count <= DAYFLOW_SUPERVISOR_MAX_ISSUES )) || {
    dayflow_supervisor_error "Linear queue snapshot exceeds resource limit ${DAYFLOW_SUPERVISOR_MAX_ISSUES}"
    return 1
  }
  jq -e 'all(.issues[].blockers[]?; (.identifier | test("^CEN-[0-9]+$")) and (.state | length > 0))' >/dev/null <<<"$snapshot" || {
    dayflow_supervisor_error 'dependency state is missing or stale'
    return 1
  }
}

dayflow_supervisor_graph_has_cycle() {
  local snapshot="$1"
  jq -e '
    [.issues[] | select(.state != "Done") | .identifier] as $nodes
    | [.issues[] as $issue | $issue.blockers[]? as $blocker
       | select($blocker.state != "Done" and ($nodes | index($blocker.identifier)) != null)
       | {from: $blocker.identifier, to: $issue.identifier}] as $edges
    | def cyclic($remaining):
        if ($remaining | length) == 0 then false
        else [$remaining[] as $node
          | select([$edges[]
              | select(.to == $node)
              | .from as $from
              | select(($remaining | index($from)) != null)] | length == 0)
          | $node] as $roots
          | if ($roots | length) == 0 then true else cyclic($remaining - $roots) end
        end;
      cyclic($nodes)
  ' >/dev/null <<<"$snapshot"
}

dayflow_supervisor_candidates() {
  local snapshot="$1"
  local issue_key
  while IFS= read -r issue_key; do
    dayflow_supervisor_resume_candidate_valid "$snapshot" "$issue_key" && printf '%s\n' "$issue_key"
  done < <(jq -r '
    [.issues[]
      | select(.state == "In Progress" or .state == "In Review")
      | select(all(.blockers[]?; .state == "Done"))
      | . + {sort_priority: (if .priority == 0 then 5 else .priority end), issue_number: (.identifier | sub("CEN-"; "") | tonumber)}]
    | sort_by(.sort_priority, .issue_number)
    | .[].identifier
  ' <<<"$snapshot")
  jq -r '
    [.issues[]
      | select(.state == "Todo")
      | select(all(.blockers[]?; .state == "Done"))
      | . + {sort_priority: (if .priority == 0 then 5 else .priority end), issue_number: (.identifier | sub("CEN-"; "") | tonumber)}]
    | sort_by(.sort_priority, .issue_number)
    | .[].identifier
  ' <<<"$snapshot"
}

dayflow_supervisor_resume_candidate_valid() {
  local snapshot="$1"
  local issue_key="$2"
  local state_file worktree branch current status
  state_file="$(dayflow_state_file "$issue_key")"
  [[ -f "$state_file" && ! -e "$DAYFLOW_SUPERVISOR_CLAIM_ROOT/$issue_key.json" ]] || return 1
  status="$(jq -r '.status // ""' "$state_file")"
  case "$status" in review-changes|publication-retry|token-accounting-recovery) ;; *) return 1 ;; esac
  jq -e --arg key "$issue_key" '
    any(.issues[]; .identifier == $key
      and (.state == "In Progress" or .state == "In Review")
      and all(.blockers[]?; .state == "Done"))
  ' >/dev/null <<<"$snapshot" || return 1
  worktree="$(jq -r '.worktree // ""' "$state_file")"
  branch="$(jq -r '.branch // ""' "$state_file")"
  [[ "$(jq -r '.issue // ""' "$state_file")" == "$issue_key" \
    && "$worktree" == "$DAYFLOW_WORKTREE_ROOT/$issue_key" \
    && -e "$worktree/.git" \
    && -n "$branch" \
    && -n "$(jq -r '.session_id // ""' "$state_file")" \
    && -n "$(jq -r '.primary_agent // ""' "$state_file")" \
    && -n "$(jq -r '.model // ""' "$state_file")" \
    && -n "$(jq -r '.reasoning // ""' "$state_file")" ]] || return 1
  current="$(git -C "$worktree" branch --show-current)"
  [[ "$current" == "$branch" && -z "$(git -C "$worktree" status --porcelain --untracked-files=normal)" ]] || return 1
  local issue_json
  issue_json="$(jq -c --arg key "$issue_key" '.issues[] | select(.identifier == $key)' <<<"$snapshot")"
  if dayflow_parallel_safe "$(jq -r '.description // ""' <<<"$issue_json")"; then
    [[ -n "$(dayflow_write_scopes "$(jq -r '.description // ""' <<<"$issue_json")")" ]] || return 1
  fi
}

dayflow_supervisor_enrich_issue() {
  local issue_json="$1"
  local description scopes parallel=false
  description="$(jq -r '.description // ""' <<<"$issue_json")"
  scopes="$(dayflow_write_scopes "$description")"
  if dayflow_parallel_safe "$description"; then parallel=true; fi
  jq -c --argjson parallel "$parallel" --arg scopes "$scopes" '
    . + {parallel_safe: $parallel, write_scopes: ($scopes | split("\n") | map(select(length > 0)))}
  ' <<<"$issue_json"
}

dayflow_supervisor_scopes_overlap() {
  local left="$1"
  local right="$2"
  local left_scope right_scope
  while IFS= read -r left_scope; do
    [[ -n "$left_scope" ]] || continue
    while IFS= read -r right_scope; do
      [[ -n "$right_scope" ]] || continue
      if dayflow_path_matches_scope "$left_scope" "$right_scope" || dayflow_path_matches_scope "$right_scope" "$left_scope"; then
        return 0
      fi
    done < <(jq -r '.write_scopes[]?' <<<"$right")
  done < <(jq -r '.write_scopes[]?' <<<"$left")
  return 1
}

dayflow_supervisor_parallel_compatible() {
  local candidate="$1"
  local peer="$2"
  jq -e '.parallel_safe == true and (.write_scopes | length > 0)' >/dev/null <<<"$candidate" || return 1
  jq -e '.parallel_safe == true and (.write_scopes | length > 0)' >/dev/null <<<"$peer" || return 1
  ! dayflow_supervisor_scopes_overlap "$candidate" "$peer"
}

dayflow_supervisor_reconcile_claims() {
  local claim issue_key pid process_start state_file status rc=0
  for claim in "$DAYFLOW_SUPERVISOR_CLAIM_ROOT"/CEN-*.json; do
    [[ -f "$claim" ]] || continue
    issue_key="$(jq -r '.identifier // ""' "$claim")"
    pid="$(jq -r '.pid // 0' "$claim")"
    process_start="$(jq -r '.process_start // ""' "$claim")"
    if dayflow_pid_identity_matches "$pid" "$process_start"; then
      continue
    fi
    state_file="$(dayflow_state_file "$issue_key")"
    status=""
    [[ -f "$state_file" ]] && status="$(jq -r '.status // ""' "$state_file")"
    case "$status" in
      blocked|done|in-review|in-review-ci-failed|in-review-ci-timeout|merge-ready|review-changes|review-required|publication-retry)
        rm -f "$claim"
        ;;
      *)
        dayflow_supervisor_error "stale claim for $issue_key has unsafe runner state: ${status:-missing}"
        rc=1
        ;;
    esac
  done
  return "$rc"
}

dayflow_supervisor_active_count() {
  local claim pid process_start count=0
  for claim in "$DAYFLOW_SUPERVISOR_CLAIM_ROOT"/CEN-*.json; do
    [[ -f "$claim" ]] || continue
    pid="$(jq -r '.pid // 0' "$claim")"
    process_start="$(jq -r '.process_start // ""' "$claim")"
    if dayflow_pid_identity_matches "$pid" "$process_start"; then
      count=$((count + 1))
    fi
  done
  printf '%s\n' "$count"
}

dayflow_supervisor_select() {
  local snapshot="$1"
  local selected_file="$2"
  local active_count available issue_key issue_json candidate peer compatible
  : >"$selected_file"
  active_count="$(dayflow_supervisor_active_count)"
  available=$((DAYFLOW_SUPERVISOR_MAX_PARALLEL - active_count))
  (( available > 0 )) || return 0

  while IFS= read -r issue_key; do
    [[ -n "$issue_key" ]] || continue
    issue_json="$(jq -c --arg key "$issue_key" '.issues[] | select(.identifier == $key)' <<<"$snapshot")"
    candidate="$(dayflow_supervisor_enrich_issue "$issue_json")"
    compatible=true
    if (( active_count > 0 )) || [[ -s "$selected_file" ]]; then
      while IFS= read -r peer; do
        [[ -n "$peer" ]] || continue
        if ! dayflow_supervisor_parallel_compatible "$candidate" "$peer"; then
          compatible=false
          break
        fi
      done < <({ for peer in "$DAYFLOW_SUPERVISOR_CLAIM_ROOT"/CEN-*.json; do [[ -f "$peer" ]] && jq -c '.' "$peer"; done; cat "$selected_file"; } 2>/dev/null)
    fi
    [[ "$compatible" == "true" ]] || continue
    printf '%s\n' "$candidate" >>"$selected_file"
    available=$((available - 1))
    (( available > 0 )) || break
  done < <(dayflow_supervisor_candidates "$snapshot")
}

dayflow_supervisor_dispatch() {
  local selected_file="$1"
  local issue pid process_start claim log_file rc=0 child_rc
  while IFS= read -r issue; do
    [[ -n "$issue" ]] || continue
    issue="$(jq -c '.' <<<"$issue")"
    claim="$DAYFLOW_SUPERVISOR_CLAIM_ROOT/$(jq -r '.identifier' <<<"$issue").json"
    [[ ! -e "$claim" ]] || {
      dayflow_supervisor_error "claim already exists: $claim"
      return 1
    }
    log_file="$DAYFLOW_SUPERVISOR_ROOT/$(jq -r '.identifier' <<<"$issue").runner.log"
    "$DAYFLOW_SUPERVISOR_RUNNER_BIN" run "$(jq -r '.identifier' <<<"$issue")" >"$log_file" 2>&1 &
    pid=$!
    process_start="$(dayflow_process_start_identity "$pid")"
    jq -n --argjson issue "$issue" --argjson pid "$pid" --arg process_start "$process_start" --argjson started "$(date +%s)" \
      '$issue + {pid: $pid, process_start: $process_start, started_epoch: $started}' >"$claim"
  done <"$selected_file"

  while IFS= read -r issue; do
    [[ -n "$issue" ]] || continue
    claim="$DAYFLOW_SUPERVISOR_CLAIM_ROOT/$(jq -r '.identifier' <<<"$issue").json"
    pid="$(jq -r '.pid' "$claim")"
    if wait "$pid"; then child_rc=0; else child_rc=$?; fi
    if (( child_rc != 0 )); then rc=1; fi
    if ! dayflow_supervisor_reconcile_claims; then rc=1; fi
  done <"$selected_file"
  return "$rc"
}

dayflow_supervisor_cleanup_completed() {
  local state_file issue_key worktree status branch base_branch status_json rc=0 fetched_bases=' '
  for state_file in "$DAYFLOW_STATE_ROOT"/CEN-*.json; do
    [[ -f "$state_file" ]] || continue
    issue_key="$(basename "$state_file" .json)"
    [[ "$issue_key" != "CEN-28" ]] || continue
    status="$(jq -r '.status // ""' "$state_file")"
    [[ "$status" == "done" ]] || continue
    worktree="$(jq -r '.worktree // ""' "$state_file")"
    branch="$(jq -r '.branch // ""' "$state_file")"
    base_branch="$(jq -r '.base_branch // "develop"' "$state_file")"
    dayflow_allowed_base_branch "$base_branch" || {
      dayflow_supervisor_error "$issue_key cleanup has an unsafe base branch"
      rc=1
      continue
    }
    [[ -n "$worktree" && -e "$worktree/.git" ]] || continue
    [[ "$worktree" == "$DAYFLOW_WORKTREE_ROOT/$issue_key" && "$worktree" != "$ROOT_DIR" ]] || {
      dayflow_supervisor_error "$issue_key cleanup path is not the exact owned worktree"
      rc=1
      continue
    }
    status_json="$(dayflow_status_issue "$issue_key")" || { rc=1; continue; }
    jq -e --arg branch "$branch" --arg base "$base_branch" --arg done "$DAYFLOW_STATE_DONE_NAME" '
      .linear_state == $done and .pull_request.state == "MERGED"
      and .pull_request.baseRefName == $base and .pull_request.headRefName == $branch
    ' >/dev/null <<<"$status_json" || {
      dayflow_supervisor_error "$issue_key cleanup lacks merged base PR and Linear Done proof"
      rc=1
      continue
    }
    [[ -z "$(git -C "$worktree" status --porcelain --untracked-files=normal)" ]] || {
      dayflow_supervisor_error "$issue_key completed worktree is dirty; preserving it"
      rc=1
      continue
    }
    if [[ "$fetched_bases" != *" ${base_branch} "* ]]; then
      git -C "$ROOT_DIR" fetch --prune origin "$base_branch" >/dev/null || return 1
      fetched_bases+="${base_branch} "
    fi
    git -C "$ROOT_DIR" worktree remove "$worktree" || { rc=1; continue; }
    dayflow_state_update "$issue_key" --arg at "$(dayflow_now_iso)" '.worktree_cleaned = true | .cleaned_at = $at'
  done
  return "$rc"
}

dayflow_supervisor_reconcile_locked() {
  "$DAYFLOW_SUPERVISOR_RUNNER_BIN" reconcile
}

dayflow_supervisor_once() {
  local snapshot selected_file rc=0
  dayflow_supervisor_initialize
  dayflow_supervisor_validate_config || return 1
  dayflow_supervisor_acquire_lock || return 1
  dayflow_supervisor_install_traps
  dayflow_supervisor_reconcile_claims || return 1
  dayflow_supervisor_reconcile_locked || return 1
  dayflow_supervisor_cleanup_completed || return 1
  snapshot="$(dayflow_supervisor_fetch_issues)" || return 1
  dayflow_supervisor_validate_snapshot "$snapshot" || return 1
  if dayflow_supervisor_graph_has_cycle "$snapshot"; then
    dayflow_supervisor_error 'Linear blocks graph contains a cycle'
    return 1
  fi
  printf '%s\n' "$snapshot" >"$DAYFLOW_SUPERVISOR_SNAPSHOT.tmp.$$"
  mv "$DAYFLOW_SUPERVISOR_SNAPSHOT.tmp.$$" "$DAYFLOW_SUPERVISOR_SNAPSHOT"
  selected_file="$DAYFLOW_SUPERVISOR_ROOT/selected.$$"
  dayflow_supervisor_select "$snapshot" "$selected_file"
  if [[ -s "$selected_file" ]]; then
    dayflow_supervisor_dispatch "$selected_file" || rc=1
  fi
  rm -f "$selected_file"
  return "$rc"
}

dayflow_supervisor_reconcile_command() {
  dayflow_supervisor_initialize
  dayflow_supervisor_acquire_lock || return 1
  dayflow_supervisor_install_traps
  dayflow_supervisor_reconcile_claims || return 1
  dayflow_supervisor_reconcile_locked
}

dayflow_supervisor_cleanup_command() {
  dayflow_supervisor_initialize
  dayflow_supervisor_acquire_lock || return 1
  dayflow_supervisor_install_traps
  dayflow_supervisor_reconcile_claims || return 1
  dayflow_supervisor_cleanup_completed
}

dayflow_supervisor_xml_escape() {
  sed -e 's/&/\&amp;/g' -e 's/</\&lt;/g' -e 's/>/\&gt;/g'
}

dayflow_supervisor_write_launchd_env() {
  local env_file="$DAYFLOW_CANONICAL_REPO_ROOT/.dayflow/supervisor.env"
  local tmp_file="$env_file.tmp.$$"
  [[ -n "${LINEAR_API_KEY:-}" ]] || {
    dayflow_supervisor_error 'LINEAR_API_KEY is required before start'
    return 1
  }
  [[ -n "${PATH:-}" ]] || {
    dayflow_supervisor_error 'PATH is required before start'
    return 1
  }
  mkdir -p "$DAYFLOW_CANONICAL_REPO_ROOT/.dayflow"
  chmod 700 "$DAYFLOW_CANONICAL_REPO_ROOT/.dayflow"
  (
    umask 077
    trap 'rm -f "$tmp_file"' EXIT
    {
      printf 'export LINEAR_API_KEY=%q\n' "$LINEAR_API_KEY"
      printf 'export PATH=%q\n' "$PATH"
      if [[ "$DAYFLOW_SUPERVISOR_MAX_PARALLEL_EXPLICIT" == "x" ]]; then
        printf 'export DAYFLOW_SUPERVISOR_MAX_PARALLEL=%q\n' "$DAYFLOW_SUPERVISOR_MAX_PARALLEL"
      fi
    } >"$tmp_file"
    chmod 600 "$tmp_file"
    mv -f "$tmp_file" "$env_file"
    trap - EXIT
  )
}

dayflow_supervisor_start() {
  local program working stdout stderr domain canonical_supervisor_root
  dayflow_supervisor_initialize
  dayflow_require_commands "$DAYFLOW_SUPERVISOR_LAUNCHCTL_BIN" id sed || return 1
  canonical_supervisor_root="$DAYFLOW_CANONICAL_REPO_ROOT/.dayflow/supervisor"
  mkdir -p "$canonical_supervisor_root"
  chmod 700 "$canonical_supervisor_root"
  DAYFLOW_SUPERVISOR_PLIST="$canonical_supervisor_root/com.dayflow.supervisor.plist"
  DAYFLOW_SUPERVISOR_PLIST_TEMPLATE="$DAYFLOW_CANONICAL_REPO_ROOT/scripts/automation/com.dayflow.supervisor.plist.template"
  [[ -x "$DAYFLOW_CANONICAL_REPO_ROOT/scripts/dayflow_supervisor.sh" && -f "$DAYFLOW_SUPERVISOR_PLIST_TEMPLATE" ]] || {
    dayflow_supervisor_error 'canonical supervisor program or plist template is unavailable'
    return 1
  }
  dayflow_supervisor_write_launchd_env || return 1
  program="$(printf '%s' "$DAYFLOW_CANONICAL_REPO_ROOT/scripts/dayflow_supervisor.sh" | dayflow_supervisor_xml_escape)"
  working="$(printf '%s' "$DAYFLOW_CANONICAL_REPO_ROOT" | dayflow_supervisor_xml_escape)"
  stdout="$(printf '%s' "$canonical_supervisor_root/launchd.stdout.log" | dayflow_supervisor_xml_escape)"
  stderr="$(printf '%s' "$canonical_supervisor_root/launchd.stderr.log" | dayflow_supervisor_xml_escape)"
  sed -e "s|__PROGRAM__|$program|g" -e "s|__WORKING_DIRECTORY__|$working|g" \
    -e "s|__INTERVAL__|$DAYFLOW_SUPERVISOR_INTERVAL_SECONDS|g" -e "s|__STDOUT__|$stdout|g" \
    -e "s|__STDERR__|$stderr|g" "$DAYFLOW_SUPERVISOR_PLIST_TEMPLATE" >"$DAYFLOW_SUPERVISOR_PLIST"
  domain="gui/$(id -u)"
  "$DAYFLOW_SUPERVISOR_LAUNCHCTL_BIN" bootstrap "$domain" "$DAYFLOW_SUPERVISOR_PLIST"
}

dayflow_supervisor_stop() {
  local domain="gui/$(id -u)"
  dayflow_require_commands "$DAYFLOW_SUPERVISOR_LAUNCHCTL_BIN" id || return 1
  "$DAYFLOW_SUPERVISOR_LAUNCHCTL_BIN" bootout "$domain/com.dayflow.supervisor"
}

dayflow_supervisor_status() {
  local snapshot='null' claims='[]' installed=false claim claim_files=()
  [[ -f "$DAYFLOW_SUPERVISOR_SNAPSHOT" ]] && snapshot="$(jq -c '.' "$DAYFLOW_SUPERVISOR_SNAPSHOT")"
  if [[ -d "$DAYFLOW_SUPERVISOR_CLAIM_ROOT" ]]; then
    for claim in "$DAYFLOW_SUPERVISOR_CLAIM_ROOT"/CEN-*.json; do
      [[ -f "$claim" ]] && claim_files+=("$claim")
    done
    if (( ${#claim_files[@]} > 0 )); then
      claims="$(jq -s '.' "${claim_files[@]}")" || return 1
    fi
  fi
  if command -v "$DAYFLOW_SUPERVISOR_LAUNCHCTL_BIN" >/dev/null 2>&1 && \
     "$DAYFLOW_SUPERVISOR_LAUNCHCTL_BIN" print "gui/$(id -u)/com.dayflow.supervisor" >/dev/null 2>&1; then
    installed=true
  fi
  jq -n --argjson installed "$installed" --argjson snapshot "$snapshot" --argjson claims "$claims" \
    '{launchd_loaded: $installed, snapshot: $snapshot, claims: $claims}'
}

dayflow_supervisor_usage() {
  printf '%s\n' 'Usage: scripts/dayflow_supervisor.sh {once|start|stop|status|reconcile|cleanup}'
}

dayflow_supervisor_main() {
  local command_name="${1:-}"
  [[ $# -eq 1 ]] || { dayflow_supervisor_usage; return 2; }
  dayflow_require_commands bash git jq sed awk "$DAYFLOW_CURL_BIN" || return 1
  case "$command_name" in
    once) dayflow_supervisor_once ;;
    start) dayflow_supervisor_start ;;
    stop) dayflow_supervisor_stop ;;
    status) dayflow_supervisor_status ;;
    reconcile) dayflow_supervisor_reconcile_command ;;
    cleanup) dayflow_supervisor_cleanup_command ;;
    *) dayflow_supervisor_usage; return 2 ;;
  esac
}
