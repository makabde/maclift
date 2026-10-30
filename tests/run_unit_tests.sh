#!/usr/bin/env bash
#
# Run all unit tests
#

set -euo pipefail

# Get script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Colors
readonly GREEN='\033[0;32m'
readonly RED='\033[0;31m'
readonly BLUE='\033[0;34m'
readonly NC='\033[0m'

# Counters
TOTAL_TESTS=0
PASSED_TESTS=0
FAILED_TESTS=0

echo ""
echo -e "${BLUE}════════════════════════════════════════════════════════════════${NC}"
echo -e "${BLUE}  Running Unit Tests${NC}"
echo -e "${BLUE}════════════════════════════════════════════════════════════════${NC}"
echo ""

# Find and run all test files in unit/ directory
for test_file in "$SCRIPT_DIR/unit"/test_*.sh; do
  if [ -f "$test_file" ]; then
    echo -e "${BLUE}Running: $(basename "$test_file")${NC}"
    TOTAL_TESTS=$((TOTAL_TESTS + 1))

    if bash "$test_file"; then
      PASSED_TESTS=$((PASSED_TESTS + 1))
      echo -e "${GREEN}✓ PASSED: $(basename "$test_file")${NC}"
    else
      FAILED_TESTS=$((FAILED_TESTS + 1))
      echo -e "${RED}✗ FAILED: $(basename "$test_file")${NC}"
    fi

    echo ""
  fi
done

# Print summary
echo ""
echo -e "${BLUE}════════════════════════════════════════════════════════════════${NC}"
echo -e "${BLUE}  Unit Test Summary${NC}"
echo -e "${BLUE}════════════════════════════════════════════════════════════════${NC}"
echo -e "Total test suites: $TOTAL_TESTS"
echo -e "${GREEN}Passed: $PASSED_TESTS${NC}"
echo -e "${RED}Failed: $FAILED_TESTS${NC}"

if [ $FAILED_TESTS -gt 0 ]; then
  echo ""
  echo -e "${RED}❌ UNIT TESTS FAILED${NC}"
  exit 1
else
  echo ""
  echo -e "${GREEN}✅ ALL UNIT TESTS PASSED${NC}"
  exit 0
fi
