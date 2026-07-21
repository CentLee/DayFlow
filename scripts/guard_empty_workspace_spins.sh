#!/usr/bin/env bash
set -euo pipefail

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib/dayflow_harness.sh"

MAX_EMPTY_SPIN_SECONDS="${MAX_EMPTY_SPIN_SECONDS:-120}"

require_linear_api_key
require_cmds jq

active_count=$(
  project_issues_json |
    jq --arg todo "$DAYFLOW_STATE_TODO_NAME" --arg in_progress "$DAYFLOW_STATE_IN_PROGRESS_NAME" \
      '[.[] | select(.state.name == $todo or .state.name == $in_progress)] | length'
)

if (( active_count == 0 )); then
  exit 0
fi

workspace_count=$(
  find "$WORKSPACE_ROOT" -mindepth 1 -maxdepth 1 -type d ! -name '*.stale.*' | wc -l | tr -d ' '
)
if (( workspace_count > 0 )); then
  exit 0
fi

pid="${IMPLEMENTATION_SYMPHONY_PID:-}"
if [[ -z "$pid" ]] || ! kill -0 "$pid" >/dev/null 2>&1; then
  exit 0
fi

elapsed=$(ps -o etimes= -p "$pid" 2>/dev/null | tr -d ' ' || echo 0)
if [[ -z "$elapsed" ]]; then
  elapsed=0
fi

if (( elapsed >= MAX_EMPTY_SPIN_SECONDS )); then
  echo "guard flagged empty workspace spin: ${active_count} active issue(s), 0 workspaces, runtime ${elapsed}s"
fi
