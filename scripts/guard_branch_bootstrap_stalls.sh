#!/usr/bin/env bash
set -euo pipefail

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib/dayflow_harness.sh"

MAX_BRANCH_BOOTSTRAP_MINUTES="${MAX_BRANCH_BOOTSTRAP_MINUTES:-5}"
MIN_ACTIVE_RUNTIME_SECONDS="${MIN_ACTIVE_RUNTIME_SECONDS:-300}"

for workspace_dir in "$WORKSPACE_ROOT"/CEN-*; do
  [[ -d "$workspace_dir/.git" ]] || continue

  issue_key=$(basename "$workspace_dir")
  [[ "$issue_key" == *.stale.* ]] && continue

  branch=$(git -C "$workspace_dir" branch --show-current 2>/dev/null || true)
  if [[ -n "$branch" && "$branch" != "develop" ]]; then
    continue
  fi

  runtime_elapsed="$(runtime_elapsed_seconds)"
  if (( runtime_elapsed > 0 )) && (( runtime_elapsed < MIN_ACTIVE_RUNTIME_SECONDS )); then
    continue
  fi

  head=$(git -C "$workspace_dir" rev-parse HEAD 2>/dev/null || true)
  develop_head=$(git -C "$workspace_dir" rev-parse origin/develop 2>/dev/null || true)
  dirty=$(git -C "$workspace_dir" status --porcelain 2>/dev/null || true)
  [[ -z "$dirty" ]] || continue
  [[ -n "$head" && -n "$develop_head" && "$head" == "$develop_head" ]] || continue

  now=$(date +%s)
  modified=$(stat -f %m "$workspace_dir" 2>/dev/null || echo "$now")
  age_minutes=$(((now - modified) / 60))

  if (( age_minutes >= MAX_BRANCH_BOOTSTRAP_MINUTES )); then
    stale_dir="${workspace_dir}.stale.$(date +%s)"
    mv "$workspace_dir" "$stale_dir"
    echo "guard recovered branch bootstrap stall: $(basename "$workspace_dir") moved to $(basename "$stale_dir") after ${age_minutes}m on develop"
  fi
done
