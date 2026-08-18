#!/usr/bin/env bash
set -euo pipefail

TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$TEST_DIR/../.." && pwd)"
QUEUE_FILE="$ROOT_DIR/docs/iteration-queue.md"
export DAYFLOW_ROOT_DIR="$ROOT_DIR"

# shellcheck source=scripts/tests/testlib.sh
source "$TEST_DIR/testlib.sh"
# shellcheck source=scripts/lib/dayflow_runner.sh
source "$ROOT_DIR/scripts/lib/dayflow_runner.sh"

brief_for_key() {
  local key="$1"
  awk -v heading="### $key " '
    index($0, heading) == 1 { found = 1; next }
    found && /^### DQ-[0-9][0-9] / { exit }
    found { print }
  ' "$QUEUE_FILE"
}

future_keys="$(sed -nE 's/^### (DQ-[0-9][0-9]) — .*/\1/p' "$QUEUE_FILE")"
expected_keys="$(for number in $(seq -w 1 12); do printf 'DQ-%s\n' "$number"; done)"

assert_eq "$expected_keys" "$future_keys" 'future document keys are unique and contiguous'
assert_eq '0' "$(printf '%s\n' "$future_keys" | sort | uniq -d | wc -l | tr -d ' ')" \
  'future document keys are not duplicated'

seen_dependencies=' CEN-44 '
for key in $future_keys; do
  brief="$(brief_for_key "$key")"
  title="$(sed -nE "s/^### $key — (.*)$/\1/p" "$QUEUE_FILE")"
  description="$(awk '/^Goal:$/ { found = 1 } found { print }' <<<"$brief")"
  issue_json="$(jq -cn --arg title "$title" --arg description "$description" \
    '{title: $title, description: $description}')"

  assert_success "$key satisfies runner admission" dayflow_validate_admission "$issue_json"
  assert_success "$key has explicit Inputs" test -n "$(dayflow_extract_section "$description" 'Inputs')"
  assert_success "$key has explicit One PR Scope" test -n "$(dayflow_extract_section "$description" 'One PR Scope')"
  assert_success "$key has explicit Execution Mode" test -n "$(dayflow_extract_section "$description" 'Execution Mode')"
  assert_success "$key has explicit Parallel Safe" test -n "$(dayflow_extract_section "$description" 'Parallel Safe')"
  assert_success "$key has explicit Write Scope" test -n "$(dayflow_extract_section "$description" 'Write Scope')"
  assert_success "$key has explicit Dependencies" test -n "$(dayflow_extract_section "$description" 'Dependencies')"

  while IFS= read -r write_scope; do
    normalized_scope="$(sed -E 's/^[[:space:]*-]+//; s/[`"]//g; s/[[:space:]]+$//' <<<"$write_scope")"
    [[ "$normalized_scope" =~ ^[A-Za-z0-9._/-]+(/\*\*)?$ ]] ||
      test_fail "$key has non-path Write Scope '$normalized_scope'"
  done < <(dayflow_extract_section "$description" 'Write Scope')

  dependencies="$(dayflow_extract_section "$description" 'Dependencies' |
    sed -E 's/^[[:space:]*-]+//; s/[`.]//g; s/[[:space:]]+$//')"
  for dependency in $dependencies; do
    case "$dependency" in
      CEN-44|DQ-[0-9][0-9]) ;;
      *) test_fail "$key has unresolvable dependency '$dependency'" ;;
    esac
    case "$seen_dependencies" in
      *" $dependency "*) ;;
      *) test_fail "$key dependency '$dependency' is not completed history or an earlier brief" ;;
    esac
  done
  seen_dependencies="$seen_dependencies$key "
done

dq01="$(brief_for_key DQ-01)"
assert_file_contains "$QUEUE_FILE" '7337c1d576a4b370cc1b43baf0444daef1d9ecd9' \
  'queue records the unreachable reviewed topology source'
assert_success 'DQ-01 starts from origin/develop' grep -Fq '`origin/develop`' <<<"$dq01"
assert_success 'DQ-01 does not claim CEN-35 as a delivered dependency' \
  test "$(dayflow_extract_section "$dq01" 'Dependencies' | sed -E 's/^[[:space:]*-]+//')" = 'CEN-44'
assert_success 'DQ-01 excludes unrelated stacked history' grep -Fq 'without importing unrelated stacked history' <<<"$dq01"

dq02="$(brief_for_key DQ-02)"
dq03="$(brief_for_key DQ-03)"
dq04="$(brief_for_key DQ-04)"
dq06="$(brief_for_key DQ-06)"
dq08="$(brief_for_key DQ-08)"
dq09="$(brief_for_key DQ-09)"
dq10="$(brief_for_key DQ-10)"
assert_success 'private deployment preserves rollback ingress before cutover' \
  rg -q 'is +not +removed by this brief' \
  <<<"$(dayflow_extract_section "$dq02" 'Done When' | tr '\n' ' ')"
assert_success 'replacement backend auth preserves legacy rollback paths' \
  rg -q 'are +not +used by replacement sessions' \
  <<<"$(dayflow_extract_section "$dq03" 'Done When' | tr '\n' ' ')"
assert_success 'fixed-boundary work preserves legacy sharing routes until cutover' \
  rg -q 'remain +rollback-only +until cutover' \
  <<<"$(dayflow_extract_section "$dq04" 'Done When' | tr '\n' ' ')"
assert_success 'replacement iOS brief records the cutover gate' \
  rg -q '`replacement-ios-auth-cutover` +gate complete' \
  <<<"$(dayflow_extract_section "$dq06" 'Done When' | tr '\n' ' ')"
assert_success 'server retirement depends on completed replacement client work' \
  grep -Fq -- '- DQ-07' <<<"$(dayflow_extract_section "$dq08" 'Dependencies')"
assert_success 'public-ingress retirement follows server retirement' \
  grep -Fq -- '- DQ-08' <<<"$(dayflow_extract_section "$dq09" 'Dependencies')"
assert_success 'legacy iOS retirement follows server and ingress retirement' \
  grep -Fq -- '- DQ-09' <<<"$(dayflow_extract_section "$dq10" 'Dependencies')"

finish_tests 'iteration_queue_test'
