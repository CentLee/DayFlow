#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

required_files=(
  AGENTS.md
  docs/automation-model.md
  docs/local-runner.md
  docs/harness-engineering.md
  docs/failure-taxonomy.md
  docs/git-tracking-policy.md
  docs/review-checklist.md
  .codex/skills/dayflow-orchestrator/SKILL.md
  scripts/dayflow_runner.sh
  scripts/lib/dayflow_runner.sh
  scripts/dayflow_supervisor.sh
  scripts/lib/dayflow_supervisor.sh
  scripts/automation/com.dayflow.supervisor.plist.template
  scripts/schemas/dayflow-review.schema.json
  scripts/tests/run_dayflow_runner_tests.sh
  scripts/tests/dayflow_supervisor_test.sh
)

for path in "${required_files[@]}"; do
  [[ -f "$path" ]] || {
    printf 'missing required harness file: %s\n' "$path" >&2
    exit 1
  }
done

for script in scripts/*.sh scripts/lib/*.sh scripts/tests/*.sh scripts/tests/fakes/*; do
  bash -n "$script"
done

if [[ -e .gitmodules || -e vendor/symphony ]]; then
  printf 'removed runtime dependency is still present\n' >&2
  exit 1
fi

forbidden_pattern='vendor/symphony|run_symphony\.sh|(127\.0\.0\.1|localhost):4100|/api/v1/state|codex app-server|bin/symphony|WORKFLOW\.review\.md|WORKFLOW\.md'
if rg -n -i "$forbidden_pattern" README.md AGENTS.md docs scripts .codex .github \
  --glob '!scripts/audit_harness_drift.sh'; then
  printf 'obsolete runtime reference found\n' >&2
  exit 1
fi

if git ls-files | rg -q '^(\.dayflow|\.symphony)/'; then
  printf 'local runtime artifacts are tracked\n' >&2
  exit 1
fi

rg -q 'product-agent\|integration-agent\|review-agent' scripts/lib/dayflow_runner.sh
rg -q 'gpt-5\.6-sol high' scripts/lib/dayflow_runner.sh
rg -q 'backend-agent\|ios-agent' scripts/lib/dayflow_runner.sh
rg -q 'gpt-5\.6-terra medium' scripts/lib/dayflow_runner.sh
for supervisor_command in once start stop status reconcile cleanup; do
  rg -q "^    $supervisor_command\)" scripts/lib/dayflow_supervisor.sh
done
rg -q 'DAYFLOW_SUPERVISOR_MAX_PARALLEL.*:-1' scripts/lib/dayflow_supervisor.sh
rg -q 'select\(\.state == "Todo"\)' scripts/lib/dayflow_supervisor.sh
rg -q 'select\(all\(\.blockers\[\]\?; \.state == "Done"\)\)' scripts/lib/dayflow_supervisor.sh
rg -q 'CEN-28' scripts/lib/dayflow_supervisor.sh
rg -q 'dependency-aware' docs/local-runner.md docs/automation-model.md
rg -q '^\.dayflow/$' .gitignore
rg -q '^\.symphony/$' .gitignore

printf 'PASS: harness drift audit\n'
