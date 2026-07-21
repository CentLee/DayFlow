#!/usr/bin/env bash
set -euo pipefail

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib/dayflow_harness.sh"
PROOF_SCRIPT="$ROOT_DIR/scripts/collect_pr_proof.sh"
MAX_RETRIES="${MAX_RETRIES:-3}"
RETRY_DELAY_SECONDS="${RETRY_DELAY_SECONDS:-2}"

if ! command -v jq >/dev/null 2>&1; then
  echo "jq is required" >&2
  exit 1
fi

if ! command -v gh >/dev/null 2>&1; then
  echo "gh is required" >&2
  exit 1
fi

tmp_file="$(mktemp)"
json_file="$(mktemp)"
trap 'rm -f "$tmp_file" "$json_file"' EXIT

retry() {
  local attempt=1
  while true; do
    if "$@"; then
      return 0
    fi
    if (( attempt >= MAX_RETRIES )); then
      return 1
    fi
    sleep "$RETRY_DELAY_SECONDS"
    attempt=$((attempt + 1))
  done
}

repo_slug="$(github_repo_slug)"
prs_json=$(retry env GH_CONFIG_DIR="${GH_CONFIG_DIR:-$ROOT_DIR/.symphony/gh}" gh pr list -R "$repo_slug" --state open --limit 100 --json number,baseRefName)

while IFS= read -r pr_row; do
  pr_number=$(jq -r '.number' <<<"$pr_row")
  if [[ "$(jq -r '.baseRefName' <<<"$pr_row")" != "develop" ]]; then
    continue
  fi

  retry env GH_CONFIG_DIR="${GH_CONFIG_DIR:-$ROOT_DIR/.symphony/gh}" "$PROOF_SCRIPT" "$pr_number" >"$tmp_file"
  jq -Rs '{body: .}' <"$tmp_file" >"$json_file"
  retry env GH_CONFIG_DIR="${GH_CONFIG_DIR:-$ROOT_DIR/.symphony/gh}" gh api "repos/${repo_slug}/pulls/${pr_number}" -X PATCH --input "$json_file" >/dev/null
  echo "updated proof-of-work for PR #${pr_number}"
done < <(jq -c '.[]' <<<"$prs_json")
