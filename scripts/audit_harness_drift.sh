#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="/Users/kakao_ent/Documents/DayFlow"

cd "$ROOT_DIR"

echo "== DayFlow Harness Drift Audit =="

echo
echo "-- Core files present --"
for path in \
  "WORKFLOW.md" \
  "docs/automation-model.md" \
  "docs/symphony-setup.md" \
  "docs/harness-engineering.md" \
  "docs/harness-skill-model.md" \
  ".codex/skills/dayflow-orchestrator/SKILL.md"
do
  if [[ -e "$path" ]]; then
    echo "OK   $path"
  else
    echo "MISS $path"
  fi
done

echo
echo "-- Agent files --"
find .codex/agents -maxdepth 1 -type f -name '*.md' | sort

echo
echo "-- Skill files --"
find .codex/skills -maxdepth 2 -type f -name 'SKILL.md' | sort

echo
echo "-- Workflow / docs keyword alignment --"
for keyword in \
  "Todo" \
  "In Progress" \
  "In Review" \
  "Blocked" \
  "Primary Agent" \
  "Done When" \
  "Out of Scope" \
  "review-agent"
do
  echo
  echo "keyword: $keyword"
  rg -n --fixed-strings "$keyword" \
    WORKFLOW.md \
    docs/automation-model.md \
    docs/symphony-setup.md \
    .codex/skills/dayflow-orchestrator/SKILL.md || true
done

echo
echo "-- Local-only files accidentally tracked? --"
git ls-files | rg '^\.symphony/' || true

echo
echo "-- HTML review artifacts present in docs? --"
find docs -maxdepth 1 -type f -name '*.html' | sort

echo
echo "-- Shell syntax check --"
for f in scripts/*.sh scripts/lib/*.sh; do
  bash -n "$f"
done
echo "OK   shell syntax"
