#!/usr/bin/env bash
set -euo pipefail

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib/dayflow_harness.sh"
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib/dayflow_notifications.sh"

require_linear_api_key
require_cmds jq python3

ISSUE_TITLE_PATTERN='^\[[^]]+\][[:space:]]+.+'

issue_table_json="$(project_issues_json)"

description_has_content() {
  local description="$1"
  local section="$2"

  DESCRIPTION="$description" python3 - "$section" <<'PY'
import os
import re
import sys

section = sys.argv[1]
description = os.environ.get("DESCRIPTION", "")
pattern = rf'(?ms)^{re.escape(section)}:\s*\n(.*?)(?=^[A-Z][A-Za-z -]+:\s*$|\Z)'
match = re.search(pattern, description)
if not match:
    raise SystemExit(1)

body = match.group(1).strip()
if not body or body.startswith("- [fill"):
    raise SystemExit(1)
PY
}

issue_is_admissible() {
  local title="$1"
  local description="$2"

  [[ "$title" =~ $ISSUE_TITLE_PATTERN ]] || return 1

  description_has_content "$description" "Goal" || return 1
  description_has_content "$description" "Primary Agent" || return 1
  description_has_content "$description" "Inputs" || return 1
  description_has_content "$description" "Done When" || return 1
  description_has_content "$description" "Out of Scope" || return 1
}

while IFS= read -r issue_row; do
  issue_id="$(jq -r '.id' <<<"$issue_row")"
  issue_key="$(jq -r '.identifier' <<<"$issue_row")"
  title="$(jq -r '.title // ""' <<<"$issue_row")"
  description="$(jq -r '.description // ""' <<<"$issue_row")"
  current_state="$(jq -r '.state.name' <<<"$issue_row")"

  [[ "$current_state" == "$DAYFLOW_STATE_TODO_NAME" ]] || continue

  if issue_is_admissible "$title" "$description"; then
    continue
  fi

  if move_issue_to_named_state "$issue_id" "$DAYFLOW_STATE_BLOCKED_NAME"; then
    notify_issue_state_change "$issue_key" "$DAYFLOW_STATE_BLOCKED_NAME" "Issue was blocked by admission validation because required metadata is incomplete."
    echo "admission blocked ${issue_key}: missing required issue metadata"
    continue
  fi

  echo "admission warning ${issue_key}: missing required issue metadata but no blocked state is configured"
done < <(jq -c '.[]' <<<"$issue_table_json")
