#!/usr/bin/env bash
set -euo pipefail

TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

for test_script in \
  "$TEST_DIR/dayflow_runner_unit_test.sh" \
  "$TEST_DIR/dayflow_runner_integration_test.sh" \
  "$TEST_DIR/dayflow_runner_system_test.sh"
do
  "$test_script"
done
