#!/usr/bin/env bash
# =============================================================================
# local-test.sh
# =============================================================================
# Run all local tests for n8n workflows.
#
# Usage:
#   ./scripts/local-test.sh
#
# Tests performed:
#   1. Validate all workflow JSON files
#   2. Run Node.js validation script
#   3. Test deployment script (dry run)
#
# Environment:
#   Tests run in dry-run mode by default (no API calls)
# =============================================================================

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo "=========================================="
echo "n8n Workflows - Local Test Suite"
echo "=========================================="
echo ""

# Track results
tests_run=0
tests_passed=0
tests_failed=0

# Helper function to run a test
run_test() {
    local test_name="$1"
    local test_command="$2"
    
    tests_run=$((tests_run + 1))
    echo -e "${BLUE}[$tests_run] $test_name${NC}"
    
    if eval "$test_command"; then
        echo -e "${GREEN}    ✓ Passed${NC}"
        tests_passed=$((tests_passed + 1))
        echo ""
        return 0
    else
        echo -e "${RED}    ✗ Failed${NC}"
        tests_failed=$((tests_failed + 1))
        echo ""
        return 1
    fi
}

# Test 1: Check required tools
echo -e "${BLUE}Checking prerequisites...${NC}"
echo ""

if ! command -v jq &> /dev/null; then
    echo -e "${RED}Error: jq is required but not installed${NC}"
    echo "Install it with: brew install jq (macOS) or apt-get install jq (Ubuntu)"
    exit 1
fi
echo -e "${GREEN}✓ jq installed${NC}"

if ! command -v node &> /dev/null; then
    echo -e "${RED}Error: Node.js is required but not installed${NC}"
    exit 1
fi
echo -e "${GREEN}✓ Node.js installed ($(node --version))${NC}"

echo ""

# Test 2: Bash validation script
run_test "Bash Workflow Validation (validate-workflows.sh)" \
    "./scripts/validate-workflows.sh" || true

# Test 3: Node.js validation script
run_test "Node.js Workflow Validation (validate-workflows.js)" \
    "node scripts/validate-workflows.js" || true

# Test 4: Validate test fixture
if [ -f "test/test-workflow.json" ]; then
    run_test "Test Fixture Validation" \
        "node scripts/validate-workflows.js test/test-workflow.json" || true
else
    echo -e "${YELLOW}⚠ Skipping test fixture validation (file not found)${NC}"
    echo ""
fi

# Test 5: Deployment script dry run
run_test "Deployment Script (dry run)" \
    "DRY_RUN=true ./scripts/test-deploy.sh" || true

# Summary
echo "=========================================="
echo "Local Test Summary"
echo "=========================================="
echo "  Total:  $tests_run"
echo -e "  ${GREEN}Passed: $tests_passed${NC}"
echo -e "  ${RED}Failed: $tests_failed${NC}"
echo "=========================================="

if [ $tests_failed -gt 0 ]; then
    echo ""
    echo -e "${RED}Some tests failed. Please fix the issues above.${NC}"
    exit 1
fi

echo ""
echo -e "${GREEN}All local tests passed!${NC}"
exit 0
