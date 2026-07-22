#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/lib/dayflow_runner.sh
source "$SCRIPT_DIR/lib/dayflow_runner.sh"

dayflow_runner_main "$@"
