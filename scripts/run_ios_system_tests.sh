#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
IOS_DIR="${ROOT_DIR}/apps/ios"
COMPOSE_FILE="${ROOT_DIR}/infra/docker/docker-compose.system.yml"
DOCKER_BIN="${DOCKER_BIN:-}"
XCODEGEN_BIN="${XCODEGEN_BIN:-}"
XCODEBUILD_BIN="${XCODEBUILD_BIN:-}"
XCRUN_BIN="${XCRUN_BIN:-}"
TIMEOUT_BIN="${TIMEOUT_BIN:-}"
SHLOCK_BIN="${SHLOCK_BIN:-}"
JQ_BIN="${JQ_BIN:-jq}"
REQUIRED_XCODEGEN_VERSION="2.45.3"
API_BASE_URL=""
TEST_OWNER_EMAIL="${DAYFLOW_IOS_TEST_OWNER_EMAIL:-owner@dayflow.local}"
TEST_OWNER_PASSWORD="${DAYFLOW_IOS_TEST_OWNER_PASSWORD:-secret1234}"
COMPOSE_PROJECT_NAME="${COMPOSE_PROJECT_NAME:-dayflow-ios-system-$$}"
KEEP_STACK="${KEEP_IOS_SYSTEM_TEST_STACK:-0}"
KEEP_ARTIFACTS="${KEEP_IOS_SYSTEM_TEST_ARTIFACTS:-0}"
LOCK_WAIT_SECONDS="${IOS_SYSTEM_TEST_LOCK_WAIT_SECONDS:-120}"
DOCKER_TIMEOUT_SECONDS="${IOS_SYSTEM_TEST_DOCKER_TIMEOUT_SECONDS:-300}"
SIMULATOR_BOOT_TIMEOUT_SECONDS="${IOS_SYSTEM_TEST_SIMULATOR_BOOT_TIMEOUT_SECONDS:-120}"
UNIT_TIMEOUT_SECONDS="${IOS_SYSTEM_TEST_UNIT_TIMEOUT_SECONDS:-300}"
UI_TIMEOUT_SECONDS="${IOS_SYSTEM_TEST_UI_TIMEOUT_SECONDS:-300}"
RUN_ROOT="${TMPDIR:-/tmp}"
RUN_ROOT="${RUN_ROOT%/}"
[[ -n "$RUN_ROOT" ]] || RUN_ROOT="/"
IOS_SYSTEM_LOCK_FILE="${RUN_ROOT}/dayflow-ios-system.lock"
SIMULATOR_UDID=""
BOOTED_BY_SCRIPT=0
API_HTTP_STATUS=""
API_HOST_PORT=""
LOCK_HELD=0
STACK_STARTED=0

find_command() {
  local configured="$1"
  shift
  local candidate
  if [[ -n "$configured" ]]; then
    [[ -x "$configured" || -n "$(command -v "$configured" 2>/dev/null)" ]] || {
      echo "Configured command is unavailable: $configured" >&2
      exit 1
    }
    printf '%s\n' "$configured"
    return
  fi
  for candidate in "$@"; do
    if [[ -x "$candidate" ]]; then
      printf '%s\n' "$candidate"
      return
    fi
    if command -v "$candidate" >/dev/null 2>&1; then
      command -v "$candidate"
      return
    fi
  done
  echo "Required command was not found. Set the matching *_BIN variable." >&2
  exit 1
}

require_positive_integer() {
  local name="$1"
  local value="$2"
  if [[ ! "$value" =~ ^[1-9][0-9]*$ ]]; then
    echo "${name} must be a positive integer." >&2
    exit 1
  fi
}

run_with_watchdog() {
  local seconds="$1"
  shift
  "$TIMEOUT_BIN" --signal=TERM --kill-after=10s "${seconds}s" "$@"
}

acquire_ios_system_lock() {
  local attempt
  local owner_pid

  for ((attempt = 1; attempt <= LOCK_WAIT_SECONDS; attempt++)); do
    if "$SHLOCK_BIN" -p "$$" -f "$IOS_SYSTEM_LOCK_FILE"; then
      LOCK_HELD=1
      return
    fi
    sleep 1
  done

  owner_pid="$(sed -n '1p' "$IOS_SYSTEM_LOCK_FILE" 2>/dev/null || true)"
  echo "Timed out waiting for the iOS system-test lock held by PID ${owner_pid:-unknown}." >&2
  return 1
}

release_ios_system_lock() {
  local owner_pid

  if [[ "$LOCK_HELD" != 1 ]]; then
    return
  fi
  LOCK_HELD=0

  if [[ ! -f "$IOS_SYSTEM_LOCK_FILE" || -L "$IOS_SYSTEM_LOCK_FILE" ]]; then
    echo "Refusing to remove an invalid iOS system-test lock file." >&2
    return
  fi
  owner_pid="$(LC_ALL=C tr -d '\n' <"$IOS_SYSTEM_LOCK_FILE")"
  if [[ ! "$owner_pid" =~ ^[0-9]+$ || "$owner_pid" != "$$" ]]; then
    echo "Refusing to remove an iOS system-test lock owned by another process." >&2
    return
  fi

  rm -f -- "$IOS_SYSTEM_LOCK_FILE"
}

test_lock_lifecycle() {
  local stale_pid

  SHLOCK_BIN="${SHLOCK_BIN:-/usr/bin/shlock}"
  IOS_SYSTEM_LOCK_FILE="${RUN_ROOT}/dayflow-ios-system-lock-test.$$"
  LOCK_WAIT_SECONDS=3
  LOCK_HELD=0

  acquire_ios_system_lock
  [[ -f "$IOS_SYSTEM_LOCK_FILE" && ! -L "$IOS_SYSTEM_LOCK_FILE" ]]
  [[ "$(LC_ALL=C tr -d '\n' <"$IOS_SYSTEM_LOCK_FILE")" == "$$" ]]
  release_ios_system_lock
  [[ ! -e "$IOS_SYSTEM_LOCK_FILE" ]]

  sleep 0.01 &
  stale_pid=$!
  wait "$stale_pid"
  "$SHLOCK_BIN" -p "$stale_pid" -f "$IOS_SYSTEM_LOCK_FILE"
  LOCK_HELD=1
  release_ios_system_lock 2>/dev/null
  [[ -f "$IOS_SYSTEM_LOCK_FILE" ]]
  [[ "$(LC_ALL=C tr -d '\n' <"$IOS_SYSTEM_LOCK_FILE")" == "$stale_pid" ]]
  acquire_ios_system_lock
  [[ "$(LC_ALL=C tr -d '\n' <"$IOS_SYSTEM_LOCK_FILE")" == "$$" ]]
  release_ios_system_lock
  [[ ! -e "$IOS_SYSTEM_LOCK_FILE" ]]

  echo "iOS system-test lock lifecycle passed."
}

print_log_tail() {
  local label="$1"
  local path="$2"
  if [[ -s "$path" ]]; then
    echo "${label} (last 120 lines):" >&2
    tail -n 120 "$path" | sed "s|${RUN_DIR}|<temporary-run>|g" >&2 || true
  fi
}

remove_run_dir() {
  case "$RUN_DIR" in
    "${RUN_ROOT}"/dayflow-ios-system.*)
      rm -rf -- "$RUN_DIR"
      ;;
    *)
      echo "Refusing to remove unexpected diagnostics directory." >&2
      return 1
      ;;
  esac
}

api_json_request() {
  local method="$1"
  local path="$2"
  local bearer_token="$3"
  local request_body="$4"
  local error_summary
  local curl_args=(
    curl
    --silent
    --show-error
    --retry 2
    --retry-delay 1
    --retry-connrefused
    --connect-timeout 5
    --max-time 20
    --output "$API_RESPONSE_FILE"
    --write-out "%{http_code}"
    --request "$method"
    --header "Accept: application/json"
  )

  if [[ -n "$bearer_token" ]]; then
    curl_args+=(--header "Authorization: Bearer ${bearer_token}")
  fi
  if [[ -n "$request_body" ]]; then
    curl_args+=(--header "Content-Type: application/json" --data-binary @-)
    if ! API_HTTP_STATUS="$("${curl_args[@]}" "${API_BASE_URL%/}/${path}" <<<"$request_body")"; then
      echo "API request failed: ${method} /${path}" >&2
      return 1
    fi
  elif ! API_HTTP_STATUS="$("${curl_args[@]}" "${API_BASE_URL%/}/${path}")"; then
    echo "API request failed: ${method} /${path}" >&2
    return 1
  fi

  if [[ ! "$API_HTTP_STATUS" =~ ^2[0-9][0-9]$ ]]; then
    if ! error_summary="$("$JQ_BIN" -c '.error // {message: "unexpected API response"}' "$API_RESPONSE_FILE" 2>/dev/null)"; then
      error_summary='{"message":"non-JSON API response"}'
    fi
    echo "API request returned ${API_HTTP_STATUS}: ${method} /${path}: ${error_summary:0:1000}" >&2
    return 1
  fi
  if ! "$JQ_BIN" -e . "$API_RESPONSE_FILE" >/dev/null 2>&1; then
    echo "API request returned invalid JSON: ${method} /${path}" >&2
    return 1
  fi
}

seed_budget_board() {
  local login_payload
  local owner_token
  local current_month_key
  local board_payload
  local saved_month_key

  login_payload="$("$JQ_BIN" -cn \
    --arg email "$TEST_OWNER_EMAIL" \
    --arg password "$TEST_OWNER_PASSWORD" \
    '{email: $email, password: $password}')"
  api_json_request "POST" "auth/login" "" "$login_payload"
  owner_token="$("$JQ_BIN" -er '.token | select(type == "string" and length > 0)' "$API_RESPONSE_FILE")" || {
    echo "Owner login response did not contain a valid token." >&2
    return 1
  }

  api_json_request "GET" "me" "$owner_token" ""
  current_month_key="$("$JQ_BIN" -er '.current_budget_month_key | select(type == "string")' "$API_RESPONSE_FILE")" || {
    echo "/me response did not contain current_budget_month_key." >&2
    return 1
  }
  if [[ ! "$current_month_key" =~ ^[0-9]{4}-(0[1-9]|1[0-2])$ ]]; then
    echo "/me returned an invalid current_budget_month_key." >&2
    return 1
  fi

  board_payload="$("$JQ_BIN" -cn --arg month_key "$current_month_key" '{
    month: {
      month_key: $month_key,
      base_budget_amount: 510,
      current_cash_amount: 300,
      saving_amount: 200,
      carry_over_amount: 0
    },
    summary: {
      fixed_cost_total: 0,
      variable_bucket_total: 0,
      free_cash_amount: 0
    },
    fixed_items: [{
      id: "e2e_fixed_housing",
      name: "Housing",
      kind: "fixed",
      amount: 153,
      enabled: true,
      billing_day_label: "20"
    }],
    variable_buckets: [{
      id: "e2e_bucket_living",
      name: "Living",
      planned_amount: 12,
      actual_amount: 0,
      formula_hint: "E2E seed"
    }],
    billing_reminders: [{
      id: "e2e_reminder_internet",
      name: "Internet",
      kind: "reminder",
      amount: 0,
      enabled: false,
      billing_day_label: "25"
    }]
  }')"
  api_json_request "PUT" "budget/months/${current_month_key}" "$owner_token" "$board_payload"
  saved_month_key="$("$JQ_BIN" -er '.month.month_key | select(type == "string")' "$API_RESPONSE_FILE")" || {
    echo "Budget seed response did not contain month.month_key." >&2
    return 1
  }
  if [[ "$saved_month_key" != "$current_month_key" ]]; then
    echo "Budget seed response returned an unexpected month key." >&2
    return 1
  fi

  api_json_request "GET" "budget/months/${current_month_key}" "$owner_token" ""
  if ! "$JQ_BIN" -e --arg month_key "$current_month_key" '
    .month.month_key == $month_key
    and any(.fixed_items[]?;
      .id == "e2e_fixed_housing"
      and .name == "Housing"
      and .amount == 153
      and .enabled == true
    )
  ' "$API_RESPONSE_FILE" >/dev/null; then
    echo "Persisted budget board did not contain the deterministic Housing seed." >&2
    return 1
  fi

  echo "Seeded deterministic budget board for ${current_month_key}."
}

if [[ "${1:-}" == "--test-lock-lifecycle" ]]; then
  test_lock_lifecycle
  exit
fi

DOCKER_BIN="$(find_command "$DOCKER_BIN" docker /Applications/Docker.app/Contents/Resources/bin/docker /usr/local/bin/docker)"
XCODEGEN_BIN="$(find_command "$XCODEGEN_BIN" xcodegen /opt/homebrew/bin/xcodegen /usr/local/bin/xcodegen)"
XCODEBUILD_BIN="$(find_command "$XCODEBUILD_BIN" xcodebuild /usr/bin/xcodebuild)"
XCRUN_BIN="$(find_command "$XCRUN_BIN" xcrun /usr/bin/xcrun)"
TIMEOUT_BIN="$(find_command "$TIMEOUT_BIN" timeout gtimeout /usr/local/bin/timeout /opt/homebrew/bin/gtimeout)"
SHLOCK_BIN="$(find_command "$SHLOCK_BIN" shlock /usr/bin/shlock)"
command -v "$JQ_BIN" >/dev/null 2>&1 || { echo "Required command was not found: $JQ_BIN" >&2; exit 1; }
if [[ -x /Applications/Docker.app/Contents/Resources/bin/docker-credential-desktop ]]; then
  export PATH="/Applications/Docker.app/Contents/Resources/bin:$PATH"
fi
if ! "$TIMEOUT_BIN" --version 2>/dev/null | head -n 1 | grep -q "GNU coreutils"; then
  echo "GNU timeout is required for process watchdogs." >&2
  exit 1
fi

XCODEGEN_VERSION="$("$XCODEGEN_BIN" version | awk 'NF { print $NF }' | tail -n 1)"
if [[ "$XCODEGEN_VERSION" != "$REQUIRED_XCODEGEN_VERSION" ]]; then
  echo "XcodeGen ${REQUIRED_XCODEGEN_VERSION} is required; found ${XCODEGEN_VERSION:-unknown}." >&2
  exit 1
fi

require_positive_integer "IOS_SYSTEM_TEST_LOCK_WAIT_SECONDS" "$LOCK_WAIT_SECONDS"
require_positive_integer "IOS_SYSTEM_TEST_DOCKER_TIMEOUT_SECONDS" "$DOCKER_TIMEOUT_SECONDS"
require_positive_integer "IOS_SYSTEM_TEST_SIMULATOR_BOOT_TIMEOUT_SECONDS" "$SIMULATOR_BOOT_TIMEOUT_SECONDS"
require_positive_integer "IOS_SYSTEM_TEST_UNIT_TIMEOUT_SECONDS" "$UNIT_TIMEOUT_SECONDS"
require_positive_integer "IOS_SYSTEM_TEST_UI_TIMEOUT_SECONDS" "$UI_TIMEOUT_SECONDS"
[[ "$KEEP_STACK" == 0 || "$KEEP_STACK" == 1 ]] || { echo "KEEP_IOS_SYSTEM_TEST_STACK must be 0 or 1." >&2; exit 1; }
[[ "$KEEP_ARTIFACTS" == 0 || "$KEEP_ARTIFACTS" == 1 ]] || { echo "KEEP_IOS_SYSTEM_TEST_ARTIFACTS must be 0 or 1." >&2; exit 1; }

RUN_DIR="$(mktemp -d "${RUN_ROOT}/dayflow-ios-system.XXXXXX")"
DERIVED_DATA_PATH="${RUN_DIR}/DerivedData"
UNIT_RESULT_BUNDLE="${RUN_DIR}/DayFlow-unit.xcresult"
UI_RESULT_BUNDLE="${RUN_DIR}/DayFlow-ui.xcresult"
XCODEBUILD_LOG="${RUN_DIR}/xcodebuild.log"
DOCKER_BUILD_LOG="${RUN_DIR}/docker-build.log"
DOCKER_LOG="${RUN_DIR}/docker.log"
SIMULATOR_LOG="${RUN_DIR}/simulator.log"
PROJECT_DRIFT_LOG="${RUN_DIR}/project-drift.log"
PROJECT_SNAPSHOT="${RUN_DIR}/DayFlow.xcodeproj.before"
API_RESPONSE_FILE="${RUN_DIR}/api-response.json"

cleanup() {
  local exit_status=$?
  rm -f "$API_RESPONSE_FILE"
  if [[ $exit_status -ne 0 && "$STACK_STARTED" == 1 ]]; then
    run_with_watchdog 30 "$DOCKER_BIN" compose -p "$COMPOSE_PROJECT_NAME" -f "$COMPOSE_FILE" logs >"$DOCKER_LOG" 2>&1 || true
  fi
  if [[ -n "$SIMULATOR_UDID" ]]; then
    run_with_watchdog 30 "$XCRUN_BIN" simctl uninstall "$SIMULATOR_UDID" com.kakaoent.dayflow >/dev/null 2>&1 || true
    if [[ "$BOOTED_BY_SCRIPT" == 1 ]]; then
      run_with_watchdog 30 "$XCRUN_BIN" simctl shutdown "$SIMULATOR_UDID" >/dev/null 2>&1 || true
    fi
  fi
  if [[ "$KEEP_STACK" != 1 && "$STACK_STARTED" == 1 ]]; then
    if ! run_with_watchdog 30 "$DOCKER_BIN" compose -p "$COMPOSE_PROJECT_NAME" -f "$COMPOSE_FILE" down -v --remove-orphans --rmi local >/dev/null 2>&1; then
      echo "Docker cleanup did not complete within its watchdog." >&2
    fi
  fi
  release_ios_system_lock

  if [[ $exit_status -ne 0 ]]; then
    echo "iOS system test failed." >&2
    print_log_tail "Docker build log" "$DOCKER_BUILD_LOG"
    print_log_tail "Simulator log" "$SIMULATOR_LOG"
    print_log_tail "xcodebuild log" "$XCODEBUILD_LOG"
    print_log_tail "Docker runtime log" "$DOCKER_LOG"
  else
    echo "iOS system test passed."
    if [[ "$KEEP_STACK" == 1 ]]; then
      LAN_IP=""
      for interface in en0 en1; do
        LAN_IP="$(ipconfig getifaddr "$interface" 2>/dev/null || true)"
        if [[ "$LAN_IP" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
          break
        fi
        LAN_IP=""
      done
      [[ -n "$LAN_IP" ]] || LAN_IP="<mac-lan-ip>"
      echo "Docker stack retained."
      echo "Compose project: $COMPOSE_PROJECT_NAME"
      echo "Retained API host port: $API_HOST_PORT"
      echo "iPhone Debug DAYFLOW_API_BASE_URL=http://${LAN_IP}:${API_HOST_PORT}/v1"
      echo "Cleanup command: \"$DOCKER_BIN\" compose -p \"$COMPOSE_PROJECT_NAME\" -f \"$COMPOSE_FILE\" down -v --remove-orphans --rmi local"
    fi
  fi

  if [[ "$KEEP_ARTIFACTS" == 1 ]]; then
    echo "iOS system-test artifacts retained in: $RUN_DIR"
  else
    remove_run_dir || true
  fi
  exit "$exit_status"
}
trap cleanup EXIT

export COMPOSE_PROJECT_NAME
export DAYFLOW_IOS_TEST_OWNER_EMAIL="$TEST_OWNER_EMAIL"
export DAYFLOW_IOS_TEST_OWNER_PASSWORD="$TEST_OWNER_PASSWORD"
export DAYFLOW_API_HOST_PORT=0
export DAYFLOW_POSTGRES_HOST_PORT=0

if [[ -d "${IOS_DIR}/DayFlow.xcodeproj" ]]; then
  cp -R "${IOS_DIR}/DayFlow.xcodeproj" "$PROJECT_SNAPSHOT"
fi
"$XCODEGEN_BIN" generate --spec "${IOS_DIR}/project.yml" --project "$IOS_DIR"
if [[ -d "$PROJECT_SNAPSHOT" ]]; then
  if ! diff -ruN "$PROJECT_SNAPSHOT" "${IOS_DIR}/DayFlow.xcodeproj" >"$PROJECT_DRIFT_LOG" 2>&1; then
    echo "Generated DayFlow.xcodeproj differs from its pre-generation snapshot." >&2
    print_log_tail "Project drift" "$PROJECT_DRIFT_LOG"
    exit 1
  fi
else
  cp -R "${IOS_DIR}/DayFlow.xcodeproj" "$PROJECT_SNAPSHOT"
  "$XCODEGEN_BIN" generate --spec "${IOS_DIR}/project.yml" --project "$IOS_DIR"
  if ! diff -ruN "$PROJECT_SNAPSHOT" "${IOS_DIR}/DayFlow.xcodeproj" >"$PROJECT_DRIFT_LOG" 2>&1; then
    echo "Generated DayFlow.xcodeproj is not deterministic." >&2
    print_log_tail "Project drift" "$PROJECT_DRIFT_LOG"
    exit 1
  fi
fi

acquire_ios_system_lock
STACK_STARTED=1
run_with_watchdog "$DOCKER_TIMEOUT_SECONDS" \
  "$DOCKER_BIN" compose -p "$COMPOSE_PROJECT_NAME" -f "$COMPOSE_FILE" up -d --build \
  >"$DOCKER_BUILD_LOG" 2>&1

API_PORT_MAPPING="$(run_with_watchdog 30 \
  "$DOCKER_BIN" compose -p "$COMPOSE_PROJECT_NAME" -f "$COMPOSE_FILE" port api 8080 | tail -n 1)"
API_HOST_PORT="${API_PORT_MAPPING##*:}"
if [[ ! "$API_HOST_PORT" =~ ^[1-9][0-9]*$ ]]; then
  echo "Docker Compose returned an invalid API host port." >&2
  exit 1
fi
API_BASE_URL="http://127.0.0.1:${API_HOST_PORT}/v1"
DAYFLOW_API_BASE_URL="$API_BASE_URL"
export DAYFLOW_API_BASE_URL

for _ in $(seq 1 60); do
  if curl -fsS --connect-timeout 2 --max-time 5 "${API_BASE_URL%/v1}/healthz" >/dev/null 2>&1; then
    break
  fi
  sleep 2
done
curl -fsS --connect-timeout 2 --max-time 5 "${API_BASE_URL%/v1}/healthz" >/dev/null
seed_budget_board

SIMULATOR_UDID="$($XCRUN_BIN simctl list devices available -j | "$JQ_BIN" -r '
  .devices
  | to_entries[]
  | select(.key | test("com\\.apple\\.CoreSimulator\\.SimRuntime\\.iOS-(17-[5-9]|1[89]-|[2-9][0-9]-)"))
  | .value[]
  | select(.state == "Booted")
  | .udid
' | head -n1)"
if [[ -z "$SIMULATOR_UDID" ]]; then
  SIMULATOR_UDID="$($XCRUN_BIN simctl list devices available -j | "$JQ_BIN" -r '
    .devices
    | to_entries[]
    | select(.key | test("com\\.apple\\.CoreSimulator\\.SimRuntime\\.iOS-(17-[5-9]|1[89]-|[2-9][0-9]-)"))
    | .value[]
    | .udid
  ' | head -n1)"
  [[ -n "$SIMULATOR_UDID" ]] || { echo "No available iOS 17.5-or-newer simulator was found." >&2; exit 1; }
  run_with_watchdog 30 "$XCRUN_BIN" simctl boot "$SIMULATOR_UDID" >"$SIMULATOR_LOG" 2>&1
  run_with_watchdog "$SIMULATOR_BOOT_TIMEOUT_SECONDS" \
    "$XCRUN_BIN" simctl bootstatus "$SIMULATOR_UDID" -b \
    >>"$SIMULATOR_LOG" 2>&1
  BOOTED_BY_SCRIPT=1
fi

"$XCRUN_BIN" simctl uninstall "$SIMULATOR_UDID" com.kakaoent.dayflow >/dev/null 2>&1 || true
DESTINATION="platform=iOS Simulator,id=${SIMULATOR_UDID}"

run_with_watchdog "$UNIT_TIMEOUT_SECONDS" "$XCODEBUILD_BIN" test \
  -project "${IOS_DIR}/DayFlow.xcodeproj" \
  -scheme DayFlow \
  -destination "$DESTINATION" \
  -destination-timeout 120 \
  -derivedDataPath "$DERIVED_DATA_PATH" \
  -resultBundlePath "$UNIT_RESULT_BUNDLE" \
  -only-testing:DayFlowTests \
  >"$XCODEBUILD_LOG" 2>&1

run_with_watchdog "$UI_TIMEOUT_SECONDS" "$XCODEBUILD_BIN" test \
  -project "${IOS_DIR}/DayFlow.xcodeproj" \
  -scheme DayFlow \
  -destination "$DESTINATION" \
  -destination-timeout 120 \
  -derivedDataPath "$DERIVED_DATA_PATH" \
  -resultBundlePath "$UI_RESULT_BUNDLE" \
  -only-testing:DayFlowUITests \
  >>"$XCODEBUILD_LOG" 2>&1
