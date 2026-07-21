#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
COMPOSE_FILE="${ROOT_DIR}/infra/docker/docker-compose.system.yml"
GO_BIN="${GO_BIN:-go}"
DOCKER_BIN="${DOCKER_BIN:-docker}"
BASE_URL="${DAYFLOW_SYSTEM_BASE_URL:-http://127.0.0.1:18080}"
KEEP_STACK="${KEEP_SYSTEM_TEST_STACK:-0}"
COMPOSE_PROJECT_NAME="${COMPOSE_PROJECT_NAME:-dayflow-system-$$}"

if [[ "${DOCKER_BIN}" == */* ]]; then
  export PATH="$(dirname "${DOCKER_BIN}"):${PATH}"
fi
export COMPOSE_PROJECT_NAME

cleanup() {
  if [[ "${KEEP_STACK}" == "1" ]]; then
    return
  fi
  "${DOCKER_BIN}" compose -f "${COMPOSE_FILE}" down -v --remove-orphans >/dev/null
}
trap cleanup EXIT

"${DOCKER_BIN}" compose -f "${COMPOSE_FILE}" up -d --build

for _ in $(seq 1 60); do
  if curl -fsS "${BASE_URL}/healthz" >/dev/null 2>&1; then
    break
  fi
  sleep 2
done

curl -fsS "${BASE_URL}/healthz" >/dev/null

(
  cd "${ROOT_DIR}/services/api"
  DAYFLOW_SYSTEM_BASE_URL="${BASE_URL}" "${GO_BIN}" test ./systemtest -count=1 -v
)
