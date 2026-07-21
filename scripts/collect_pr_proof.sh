#!/usr/bin/env bash
set -euo pipefail

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib/dayflow_harness.sh"

if ! command -v jq >/dev/null 2>&1; then
  echo "jq is required" >&2
  exit 1
fi

if ! command -v gh >/dev/null 2>&1; then
  echo "gh is required" >&2
  exit 1
fi

repo_slug="$(github_repo_slug)"
pr_number="${1:-}"
if [[ -z "$pr_number" ]]; then
  pr_number=$(GH_CONFIG_DIR="${GH_CONFIG_DIR:-$ROOT_DIR/.symphony/gh}" gh pr view -R "$repo_slug" --json number -q '.number')
fi

pr_json=$(GH_CONFIG_DIR="${GH_CONFIG_DIR:-$ROOT_DIR/.symphony/gh}" gh pr view -R "$repo_slug" "$pr_number" --json number,title,headRefName,baseRefName,files,comments)
checks_output=$(GH_CONFIG_DIR="${GH_CONFIG_DIR:-$ROOT_DIR/.symphony/gh}" gh pr checks -R "$repo_slug" "$pr_number" 2>&1 || true)

file_count=$(jq '.files | length' <<<"$pr_json")
additions=$(jq '[.files[].additions // 0] | add // 0' <<<"$pr_json")
deletions=$(jq '[.files[].deletions // 0] | add // 0' <<<"$pr_json")
changed_files=$(
  jq -r '
    .files
    | if length == 0 then "- none"
      else .[] | "- \(.path) (+\(.additions // 0)/-\(.deletions // 0))"
      end
  ' <<<"$pr_json"
)

feedback_summary=$(
  jq -r '
    .comments
    | map(select((.body | test("Findings"; "i")) or (.body | test("Merge Decision"; "i"))))
    | sort_by(.createdAt)
    | reverse
    | .[:3]
    | if length == 0 then "- none"
      else .[] | "- " + ((.body | split("\n")[0]) // "comment")
      end
  ' <<<"$pr_json"
)

tests_summary="- no checks reported"
if [[ -n "$checks_output" ]]; then
  tests_summary=$(while IFS= read -r line; do
    [[ -z "$line" ]] && continue
    printf -- "- %s\n" "$line"
  done <<<"$checks_output")
fi

cat <<EOF
## Summary

- PR #${pr_number}: $(jq -r '.title' <<<"$pr_json")
- Branch: \`$(jq -r '.headRefName' <<<"$pr_json")\` -> \`$(jq -r '.baseRefName' <<<"$pr_json")\`

## Changed files

${changed_files}

## Behavior implemented

- update this section with the user-visible or API-visible behavior delivered by the PR

## Tests run

${tests_summary}

## Review feedback addressed

${feedback_summary}

## Complexity snapshot

- files changed: ${file_count}
- line delta: +${additions} / -${deletions}

## Risks or follow-ups

- add any remaining contract, testing, or rollout risk here

## Next suggested issue

- add the next logical issue id or title here
EOF
