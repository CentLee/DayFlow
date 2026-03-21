#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="/Users/kakao_ent/Documents/DayFlow"
WORKSPACE_ROOT="$ROOT_DIR/.symphony/workspaces"
PROJECT_ID="fdeb5f63-05f2-4ab2-bb9d-a12dc0084b9f"
MAX_EMPTY_SPIN_SECONDS="${MAX_EMPTY_SPIN_SECONDS:-120}"

if [[ -z "${LINEAR_API_KEY:-}" ]]; then
  echo "LINEAR_API_KEY is required" >&2
  exit 1
fi

if ! command -v jq >/dev/null 2>&1; then
  echo "jq is required" >&2
  exit 1
fi

linear_query() {
  local query="$1"
  curl -s https://api.linear.app/graphql \
    -H "Content-Type: application/json" \
    -H "Authorization: ${LINEAR_API_KEY}" \
    --data "$(jq -n --arg query "$query" '{query: $query}')"
}

active_count=$(
  linear_query "query { project(id: \"${PROJECT_ID}\") { issues(first: 100) { nodes { id identifier state { name } } } } }" |
    jq '[.data.project.issues.nodes[] | select(.state.name == "Todo" or .state.name == "In Progress")] | length'
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
