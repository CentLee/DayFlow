#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

required_files=(
  AGENTS.md
  docs/development-workflow.md
  docs/review-checklist.md
  .codex/skills/dayflow-orchestrator/SKILL.md
  .codex/skills/dayflow-implementation/SKILL.md
)

for path in "${required_files[@]}"; do
  [[ -f "$path" ]] || {
    printf 'missing required harness file: %s\n' "$path" >&2
    exit 1
  }
done

bash -n scripts/audit_harness_drift.sh scripts/github_merge_reconcile.sh

if [[ -e .gitmodules || -e vendor/symphony ]]; then
  printf 'removed runtime dependency is still present\n' >&2
  exit 1
fi

forbidden_pattern='vendor/symphony|run_symphony\.sh|(127\.0\.0\.1|localhost):4100|/api/v1/state|codex app-server|bin/symphony'
if rg -n -i "$forbidden_pattern" README.md AGENTS.md docs scripts .codex .github \
  --glob '!scripts/audit_harness_drift.sh'; then
  printf 'obsolete runtime reference found\n' >&2
  exit 1
fi

if git ls-files | rg -q '^(\.dayflow|\.symphony)/'; then
  printf 'local runtime artifacts are tracked\n' >&2
  exit 1
fi

rg -q 'direct PR workflow' AGENTS.md .codex/skills/dayflow-orchestrator/SKILL.md docs/development-workflow.md
rg -q 'gpt-5\.6-sol' .codex/agents/product-agent.md .codex/agents/integration-agent.md .codex/agents/review-agent.md
rg -q 'gpt-5\.6-terra' .codex/agents/backend-agent.md .codex/agents/ios-agent.md
rg -q '^\.dayflow/$' .gitignore
rg -q '^\.symphony/$' .gitignore

printf 'PASS: harness drift audit\n'
