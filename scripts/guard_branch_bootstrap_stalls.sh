#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="/Users/kakao_ent/Documents/DayFlow"
WORKSPACE_ROOT="$ROOT_DIR/.symphony/workspaces"
MAX_BRANCH_BOOTSTRAP_MINUTES="${MAX_BRANCH_BOOTSTRAP_MINUTES:-1}"

for workspace_dir in "$WORKSPACE_ROOT"/CEN-*; do
  [[ -d "$workspace_dir/.git" ]] || continue

  branch=$(git -C "$workspace_dir" branch --show-current 2>/dev/null || true)
  if [[ -n "$branch" && "$branch" != "develop" ]]; then
    continue
  fi

  now=$(date +%s)
  modified=$(stat -f %m "$workspace_dir" 2>/dev/null || echo "$now")
  age_minutes=$(((now - modified) / 60))

  if (( age_minutes >= MAX_BRANCH_BOOTSTRAP_MINUTES )); then
    stale_dir="${workspace_dir}.stale.$(date +%s)"
    mv "$workspace_dir" "$stale_dir"
    echo "guard recovered branch bootstrap stall: $(basename "$workspace_dir") moved to $(basename "$stale_dir") after ${age_minutes}m on develop"
  fi
done
