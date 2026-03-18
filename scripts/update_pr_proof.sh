#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="/Users/kakao_ent/Documents/DayFlow"
PROOF_SCRIPT="$ROOT_DIR/scripts/collect_pr_proof.sh"
REPO_SLUG="CentLee/DayFlow"

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

prs_json=$(GH_CONFIG_DIR="${GH_CONFIG_DIR:-$ROOT_DIR/.symphony/gh}" gh pr list --state open --limit 100 --json number,baseRefName)

while IFS= read -r pr_row; do
  pr_number=$(jq -r '.number' <<<"$pr_row")
  if [[ "$(jq -r '.baseRefName' <<<"$pr_row")" != "develop" ]]; then
    continue
  fi

  GH_CONFIG_DIR="${GH_CONFIG_DIR:-$ROOT_DIR/.symphony/gh}" "$PROOF_SCRIPT" "$pr_number" >"$tmp_file"
  jq -Rs '{body: .}' <"$tmp_file" >"$json_file"
  GH_CONFIG_DIR="${GH_CONFIG_DIR:-$ROOT_DIR/.symphony/gh}" gh api "repos/${REPO_SLUG}/pulls/${pr_number}" -X PATCH --input "$json_file" >/dev/null
  echo "updated proof-of-work for PR #${pr_number}"
done < <(jq -c '.[]' <<<"$prs_json")
