#!/usr/bin/env bash

TEST_COUNT=0

test_fail() {
  printf 'FAIL: %s\n' "$*" >&2
  exit 1
}

assert_eq() {
  local expected="$1"
  local actual="$2"
  local label="${3:-values differ}"
  TEST_COUNT=$((TEST_COUNT + 1))
  [[ "$expected" == "$actual" ]] || test_fail "$label: expected '$expected', got '$actual'"
}

assert_file_contains() {
  local file="$1"
  local pattern="$2"
  local label="${3:-missing pattern}"
  TEST_COUNT=$((TEST_COUNT + 1))
  rg -q -- "$pattern" "$file" || test_fail "$label: '$pattern' not found in $file"
}

assert_success() {
  local label="$1"
  shift
  TEST_COUNT=$((TEST_COUNT + 1))
  "$@" || test_fail "$label"
}

assert_failure() {
  local label="$1"
  shift
  TEST_COUNT=$((TEST_COUNT + 1))
  if "$@"; then
    test_fail "$label"
  fi
}

finish_tests() {
  printf 'PASS: %s (%d assertions)\n' "$1" "$TEST_COUNT"
}
