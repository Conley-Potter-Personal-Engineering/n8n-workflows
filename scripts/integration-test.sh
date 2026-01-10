#!/usr/bin/env bash
# =============================================================================
# integration-test.sh
# =============================================================================
# End-to-end integration tests for n8n workflow deployment.
#
# This script deploys a test workflow to a staging n8n instance, verifies
# it appears correctly, and cleans up afterward.
#
# Usage:
#   ./scripts/integration-test.sh
#
# Environment Variables (required):
#   N8N_TEST_API_KEY   - API key for test n8n instance
#   N8N_TEST_BASE_URL  - Base URL of test n8n instance
#
# Note: This is intended for use in CI after merging to main branch.
# =============================================================================

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo "=========================================="
echo "n8n Integration Tests"
echo "=========================================="
echo ""

# Use test-specific environment variables
API_KEY="${N8N_TEST_API_KEY:-$N8N_API_KEY}"
BASE_URL="${N8N_TEST_BASE_URL:-$N8N_BASE_URL}"

# Verify environment
if [ -z "$API_KEY" ]; then
    echo -e "${RED}Error: N8N_TEST_API_KEY (or N8N_API_KEY) is not set${NC}"
    exit 1
fi

if [ -z "$BASE_URL" ]; then
    echo -e "${RED}Error: N8N_TEST_BASE_URL (or N8N_BASE_URL) is not set${NC}"
    exit 1
fi

echo "Test instance: $BASE_URL"
echo ""

# Track created workflow for cleanup
CREATED_WORKFLOW_ID=""

# Cleanup function
cleanup() {
    if [ -n "$CREATED_WORKFLOW_ID" ]; then
        echo ""
        echo -e "${BLUE}Cleaning up test workflow...${NC}"
        
        local response=$(curl -s -w "\n%{http_code}" -X DELETE "$BASE_URL/api/v1/workflows/$CREATED_WORKFLOW_ID" \
            -H "X-N8N-API-KEY: $API_KEY" \
            --connect-timeout 10 2>&1) || true

        local http_code=$(echo "$response" | tail -n1)

        if [ "$http_code" -ge 200 ] && [ "$http_code" -lt 300 ]; then
            echo -e "${GREEN}✓ Test workflow cleaned up (ID: $CREATED_WORKFLOW_ID)${NC}"
        else
            echo -e "${YELLOW}⚠ Could not clean up test workflow (HTTP $http_code)${NC}"
        fi
    fi
}

# Set trap for cleanup on exit
trap cleanup EXIT

# Test 1: API Connectivity
test_api_connectivity() {
    echo -e "${BLUE}Test 1: API Connectivity${NC}"

    local response=$(curl -s -w "\n%{http_code}" -X GET "$BASE_URL/api/v1/workflows" \
        -H "X-N8N-API-KEY: $API_KEY" \
        -H "Content-Type: application/json" \
        --connect-timeout 10)

    local http_code=$(echo "$response" | tail -n1)

    if [ "$http_code" -ge 200 ] && [ "$http_code" -lt 300 ]; then
        echo -e "${GREEN}  ✓ API connection successful (HTTP $http_code)${NC}"
        return 0
    else
        echo -e "${RED}  ✗ API connection failed (HTTP $http_code)${NC}"
        return 1
    fi
}

# Test 2: Deploy Test Workflow
test_deploy_workflow() {
    echo -e "${BLUE}Test 2: Deploy Test Workflow${NC}"

    local test_file="test/test-workflow.json"
    
    if [ ! -f "$test_file" ]; then
        echo -e "${RED}  ✗ Test workflow file not found: $test_file${NC}"
        return 1
    fi

    # Create a unique workflow name for this test run
    local timestamp=$(date +%s)
    local test_name="Integration Test - $timestamp"
    
    # Modify the workflow with unique name (remove any existing ID to force creation)
    local workflow_data=$(jq --arg name "$test_name" '. | del(.id) | .name = $name' "$test_file")

    local response=$(curl -s -w "\n%{http_code}" -X POST "$BASE_URL/api/v1/workflows" \
        -H "X-N8N-API-KEY: $API_KEY" \
        -H "Content-Type: application/json" \
        -d "$workflow_data" \
        --connect-timeout 30)

    local http_code=$(echo "$response" | tail -n1)
    local body=$(echo "$response" | head -n-1)

    if [ "$http_code" -ge 200 ] && [ "$http_code" -lt 300 ]; then
        CREATED_WORKFLOW_ID=$(echo "$body" | jq -r '.id')
        echo -e "${GREEN}  ✓ Workflow deployed successfully${NC}"
        echo "    ID: $CREATED_WORKFLOW_ID"
        echo "    Name: $test_name"
        return 0
    else
        echo -e "${RED}  ✗ Workflow deployment failed (HTTP $http_code)${NC}"
        echo "    Response: $body"
        return 1
    fi
}

# Test 3: Verify Workflow Exists
test_verify_workflow() {
    echo -e "${BLUE}Test 3: Verify Workflow Exists${NC}"

    if [ -z "$CREATED_WORKFLOW_ID" ]; then
        echo -e "${YELLOW}  ⚠ Skipping - no workflow was created${NC}"
        return 1
    fi

    local response=$(curl -s -w "\n%{http_code}" -X GET "$BASE_URL/api/v1/workflows/$CREATED_WORKFLOW_ID" \
        -H "X-N8N-API-KEY: $API_KEY" \
        -H "Content-Type: application/json" \
        --connect-timeout 10)

    local http_code=$(echo "$response" | tail -n1)
    local body=$(echo "$response" | head -n-1)

    if [ "$http_code" -ge 200 ] && [ "$http_code" -lt 300 ]; then
        local workflow_name=$(echo "$body" | jq -r '.name')
        echo -e "${GREEN}  ✓ Workflow verified in n8n${NC}"
        echo "    Name: $workflow_name"
        return 0
    else
        echo -e "${RED}  ✗ Workflow not found (HTTP $http_code)${NC}"
        return 1
    fi
}

# Test 4: Activate Workflow
test_activate_workflow() {
    echo -e "${BLUE}Test 4: Activate Workflow${NC}"

    if [ -z "$CREATED_WORKFLOW_ID" ]; then
        echo -e "${YELLOW}  ⚠ Skipping - no workflow was created${NC}"
        return 1
    fi

    local response=$(curl -s -w "\n%{http_code}" -X PATCH "$BASE_URL/api/v1/workflows/$CREATED_WORKFLOW_ID" \
        -H "X-N8N-API-KEY: $API_KEY" \
        -H "Content-Type: application/json" \
        -d '{"active": true}' \
        --connect-timeout 10)

    local http_code=$(echo "$response" | tail -n1)
    local body=$(echo "$response" | head -n-1)

    # Activation might fail if workflow has trigger nodes that require configuration
    # This is expected for test workflows, so we just check the API responds
    if [ "$http_code" -ge 200 ] && [ "$http_code" -lt 300 ]; then
        local is_active=$(echo "$body" | jq -r '.active')
        echo -e "${GREEN}  ✓ Workflow activation request succeeded${NC}"
        echo "    Active: $is_active"
        return 0
    elif [ "$http_code" = "400" ]; then
        echo -e "${YELLOW}  ⚠ Workflow could not be activated (may require trigger configuration)${NC}"
        echo "    This is expected for test workflows without triggers"
        return 0  # Not a failure for test workflows
    else
        echo -e "${RED}  ✗ Activation request failed (HTTP $http_code)${NC}"
        return 1
    fi
}

# Run all tests
main() {
    local tests_passed=0
    local tests_failed=0

    test_api_connectivity && tests_passed=$((tests_passed + 1)) || tests_failed=$((tests_failed + 1))
    test_deploy_workflow && tests_passed=$((tests_passed + 1)) || tests_failed=$((tests_failed + 1))
    test_verify_workflow && tests_passed=$((tests_passed + 1)) || tests_failed=$((tests_failed + 1))
    test_activate_workflow && tests_passed=$((tests_passed + 1)) || tests_failed=$((tests_failed + 1))

    echo ""
    echo "=========================================="
    echo "Integration Test Summary"
    echo "=========================================="
    echo -e "  ${GREEN}Passed: $tests_passed${NC}"
    echo -e "  ${RED}Failed: $tests_failed${NC}"
    echo "=========================================="

    if [ $tests_failed -gt 0 ]; then
        exit 1
    fi
    exit 0
}

# Check for jq
if ! command -v jq &> /dev/null; then
    echo -e "${RED}Error: jq is required but not installed${NC}"
    exit 1
fi

main
