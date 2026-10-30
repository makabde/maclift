#!/usr/bin/env bash
#
# Simple Test Framework for Shell Scripts
# Provides assertion functions and test suite management
#

set -euo pipefail

# Colors for output
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly NC='\033[0m' # No Color

# Test counters
TESTS_RUN=0
TESTS_PASSED=0
TESTS_FAILED=0
CURRENT_SUITE=""

#
# Start a new test suite
#
test_suite() {
  local suite_name=$1
  # shellcheck disable=SC2034 # read by suites that source this framework
  CURRENT_SUITE="$suite_name"
  echo ""
  echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
  echo -e "${BLUE}Test Suite: $suite_name${NC}"
  echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
}

#
# Assert that two values are equal
#
assert_equals() {
  local expected=$1
  local actual=$2
  local message=${3:-"Values should be equal"}

  TESTS_RUN=$((TESTS_RUN + 1))

  if [ "$expected" = "$actual" ]; then
    TESTS_PASSED=$((TESTS_PASSED + 1))
    echo -e "${GREEN}✓${NC} $message"
    return 0
  else
    TESTS_FAILED=$((TESTS_FAILED + 1))
    echo -e "${RED}✗${NC} $message"
    echo -e "  ${YELLOW}Expected:${NC} $expected"
    echo -e "  ${YELLOW}Actual:${NC}   $actual"
    return 1
  fi
}

#
# Assert that two values are NOT equal
#
assert_not_equals() {
  local not_expected=$1
  local actual=$2
  local message=${3:-"Values should not be equal"}

  TESTS_RUN=$((TESTS_RUN + 1))

  if [ "$not_expected" != "$actual" ]; then
    TESTS_PASSED=$((TESTS_PASSED + 1))
    echo -e "${GREEN}✓${NC} $message"
    return 0
  else
    TESTS_FAILED=$((TESTS_FAILED + 1))
    echo -e "${RED}✗${NC} $message"
    echo -e "  ${YELLOW}Should not equal:${NC} $not_expected"
    return 1
  fi
}

#
# Assert that a command succeeds (exit code 0)
#
assert_command_succeeds() {
  local command=$1
  local message=${2:-"Command should succeed"}

  TESTS_RUN=$((TESTS_RUN + 1))

  if eval "$command" >/dev/null 2>&1; then
    TESTS_PASSED=$((TESTS_PASSED + 1))
    echo -e "${GREEN}✓${NC} $message"
    return 0
  else
    TESTS_FAILED=$((TESTS_FAILED + 1))
    echo -e "${RED}✗${NC} $message"
    echo -e "  ${YELLOW}Command:${NC} $command"
    return 1
  fi
}

#
# Assert that a command fails (exit code non-zero)
#
assert_command_fails() {
  local command=$1
  local message=${2:-"Command should fail"}

  TESTS_RUN=$((TESTS_RUN + 1))

  if ! eval "$command" >/dev/null 2>&1; then
    TESTS_PASSED=$((TESTS_PASSED + 1))
    echo -e "${GREEN}✓${NC} $message"
    return 0
  else
    TESTS_FAILED=$((TESTS_FAILED + 1))
    echo -e "${RED}✗${NC} $message"
    echo -e "  ${YELLOW}Command:${NC} $command"
    return 1
  fi
}

#
# Assert that a file exists
#
assert_file_exists() {
  local file_path=$1
  local message=${2:-"File should exist: $file_path"}

  TESTS_RUN=$((TESTS_RUN + 1))

  if [ -f "$file_path" ]; then
    TESTS_PASSED=$((TESTS_PASSED + 1))
    echo -e "${GREEN}✓${NC} $message"
    return 0
  else
    TESTS_FAILED=$((TESTS_FAILED + 1))
    echo -e "${RED}✗${NC} $message"
    return 1
  fi
}

#
# Assert that a directory exists
#
assert_dir_exists() {
  local dir_path=$1
  local message=${2:-"Directory should exist: $dir_path"}

  TESTS_RUN=$((TESTS_RUN + 1))

  if [ -d "$dir_path" ]; then
    TESTS_PASSED=$((TESTS_PASSED + 1))
    echo -e "${GREEN}✓${NC} $message"
    return 0
  else
    TESTS_FAILED=$((TESTS_FAILED + 1))
    echo -e "${RED}✗${NC} $message"
    return 1
  fi
}

#
# Assert that a string contains a substring
#
assert_contains() {
  local haystack=$1
  local needle=$2
  local message=${3:-"String should contain substring"}

  TESTS_RUN=$((TESTS_RUN + 1))

  # "--" so a needle may start with "-"; no -q, so grep reads all input and
  # echo never dies of SIGPIPE under pipefail.
  if printf '%s\n' "$haystack" | grep -- "$needle" >/dev/null; then
    TESTS_PASSED=$((TESTS_PASSED + 1))
    echo -e "${GREEN}✓${NC} $message"
    return 0
  else
    TESTS_FAILED=$((TESTS_FAILED + 1))
    echo -e "${RED}✗${NC} $message"
    echo -e "  ${YELLOW}Haystack:${NC} $haystack"
    echo -e "  ${YELLOW}Needle:${NC}   $needle"
    return 1
  fi
}

#
# Assert that a value is true (non-empty)
#
assert_true() {
  local value=$1
  local message=${2:-"Value should be true"}

  TESTS_RUN=$((TESTS_RUN + 1))

  if [ -n "$value" ]; then
    TESTS_PASSED=$((TESTS_PASSED + 1))
    echo -e "${GREEN}✓${NC} $message"
    return 0
  else
    TESTS_FAILED=$((TESTS_FAILED + 1))
    echo -e "${RED}✗${NC} $message"
    return 1
  fi
}

#
# Assert that a value is false (empty)
#
assert_false() {
  local value=$1
  local message=${2:-"Value should be false"}

  TESTS_RUN=$((TESTS_RUN + 1))

  if [ -z "$value" ]; then
    TESTS_PASSED=$((TESTS_PASSED + 1))
    echo -e "${GREEN}✓${NC} $message"
    return 0
  else
    TESTS_FAILED=$((TESTS_FAILED + 1))
    echo -e "${RED}✗${NC} $message"
    echo -e "  ${YELLOW}Value:${NC} $value"
    return 1
  fi
}

#
# Print test summary and exit with appropriate code
#
test_summary() {
  echo ""
  echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
  echo -e "${BLUE}Test Summary${NC}"
  echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
  echo -e "Tests run:    $TESTS_RUN"
  echo -e "${GREEN}Tests passed: $TESTS_PASSED${NC}"

  if [ $TESTS_FAILED -gt 0 ]; then
    echo -e "${RED}Tests failed: $TESTS_FAILED${NC}"
    echo ""
    echo -e "${RED}❌ TEST SUITE FAILED${NC}"
    exit 1
  else
    echo -e "${YELLOW}Tests failed: $TESTS_FAILED${NC}"
    echo ""
    echo -e "${GREEN}✅ ALL TESTS PASSED${NC}"
    exit 0
  fi
}

#
# Skip a test with a message
#
skip_test() {
  local message=$1
  echo -e "${YELLOW}⊘${NC} SKIPPED: $message"
}

#
# Print info message
#
test_info() {
  local message=$1
  echo -e "${BLUE}ℹ${NC}  $message"
}
