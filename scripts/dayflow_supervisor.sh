#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "${BASH_SOURCE[0]%/*}" && pwd)"
CANONICAL_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

dayflow_supervisor_file_owner_mode() {
  local result
  if result="$(/usr/bin/stat -f '%u %Lp' "$1" 2>/dev/null)"; then
    printf '%s\n' "$result"
  elif result="$(/usr/bin/stat -c '%u %a' "$1" 2>/dev/null)"; then
    printf '%s\n' "$result"
  else
    return 1
  fi
}

if [[ "${1:-}" == "launchd-once" ]]; then
  env_file="$CANONICAL_ROOT/.dayflow/supervisor.env"
  if [[ ! -f "$env_file" || -L "$env_file" ]]; then
    printf 'dayflow-supervisor: launchd environment file is missing or invalid: %s\n' "$env_file" >&2
    exit 1
  fi
  if ! read -r env_owner env_mode < <(dayflow_supervisor_file_owner_mode "$env_file"); then
    printf 'dayflow-supervisor: unable to inspect launchd environment file security\n' >&2
    exit 1
  fi
  if [[ "$env_owner" != "$UID" || "$env_mode" != "600" ]]; then
    printf 'dayflow-supervisor: launchd environment file must be owned by the current user with mode 0600\n' >&2
    exit 1
  fi
  if ! /usr/bin/grep -Eq '^export (LINEAR_API_KEY|PATH)=' "$env_file" ||
     /usr/bin/grep -Evq '^export (LINEAR_API_KEY|PATH|DAYFLOW_SUPERVISOR_MAX_PARALLEL)=.*$|^$' "$env_file"; then
    printf 'dayflow-supervisor: launchd environment file is malformed\n' >&2
    exit 1
  fi
  # shellcheck disable=SC1090
  source "$env_file"
  [[ -n "${LINEAR_API_KEY:-}" && -n "${PATH:-}" ]] || {
    printf 'dayflow-supervisor: launchd environment is missing required values\n' >&2
    exit 1
  }
  [[ -z "${DAYFLOW_SUPERVISOR_MAX_PARALLEL:-}" || "$DAYFLOW_SUPERVISOR_MAX_PARALLEL" =~ ^[12]$ ]] || {
    printf 'dayflow-supervisor: launchd maximum parallel value must be 1 or 2\n' >&2
    exit 1
  }
  export DAYFLOW_ROOT_DIR="$CANONICAL_ROOT"
  unset DAYFLOW_RUNTIME_DIR DAYFLOW_WORKTREE_ROOT DAYFLOW_STATE_ROOT DAYFLOW_LOG_ROOT
  set -- once
fi

# shellcheck source=scripts/lib/dayflow_supervisor.sh
source "$SCRIPT_DIR/lib/dayflow_supervisor.sh"

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  dayflow_supervisor_main "$@"
fi
