#!/usr/bin/env bash
# =============================================================================
# test-deploy.sh
# =============================================================================
# Test deployment script with dry-run and mock capabilities.
#
# Usage:
#   ./scripts/test-deploy.sh                    # Run with env vars
#   DRY_RUN=true ./scripts/test-deploy.sh       # Dry run mode (no API calls)
#
# Environment Variables:
#   N8N_API_KEY   - API key for n8n instance (required unless DRY_RUN=true)
#   N8N_BASE_URL  - Base URL of n8n instance (required unless DRY_RUN=true)
#   DRY_RUN       - Set to "true" to skip actual API calls
# =============================================================================

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Load .env file if it exists
if [ -f "credentials/.env" ]; then
    export $(grep -v '^#' credentials/.env | xargs 2>/dev/null) || true
elif [ -f ".env" ]; then
    export $(grep -v '^#' .env | xargs 2>/dev/null) || true
fi

echo "=========================================="
echo "n8n Deployment Test Script"
echo "=========================================="
echo ""

# Check if dry run mode
if [ "$DRY_RUN" = "true" ]; then
    echo -e "${YELLOW}Running in DRY_RUN mode - no actual API calls will be made${NC}"
    echo ""
fi

# Check for required environment variables
check_env_vars() {
    local missing=0

    if [ -z "$N8N_API_KEY" ]; then
        if [ "$DRY_RUN" = "true" ]; then
            echo -e "${YELLOW}⚠ N8N_API_KEY not set (OK in dry run mode)${NC}"
            N8N_API_KEY="dry-run-test-key"
        else
            echo -e "${RED}✗ N8N_API_KEY environment variable is not set${NC}"
            missing=1
        fi
    else
        echo -e "${GREEN}✓ N8N_API_KEY is set${NC}"
    fi

    if [ -z "$N8N_BASE_URL" ]; then
        if [ "$DRY_RUN" = "true" ]; then
            echo -e "${YELLOW}⚠ N8N_BASE_URL not set (OK in dry run mode)${NC}"
            N8N_BASE_URL="http://localhost:5678"
        else
            echo -e "${RED}✗ N8N_BASE_URL environment variable is not set${NC}"
            missing=1
        fi
    else
        echo -e "${GREEN}✓ N8N_BASE_URL is set: $N8N_BASE_URL${NC}"
    fi

    return $missing
}

# Test authentication header construction
test_auth_header() {
    echo ""
    echo -e "${BLUE}Testing authentication header construction...${NC}"

    local auth_header="X-N8N-API-KEY: $N8N_API_KEY"
    
    if [ -n "$N8N_API_KEY" ]; then
        echo -e "${GREEN}✓ Auth header constructed correctly${NC}"
        echo "  Header: X-N8N-API-KEY: ${N8N_API_KEY:0:8}..."
        return 0
    else
        echo -e "${RED}✗ Failed to construct auth header${NC}"
        return 1
    fi
}

# Test API request formatting
test_request_format() {
    echo ""
    echo -e "${BLUE}Testing API request formatting...${NC}"

    # Find a test workflow file
    local test_file=""
    if [ -f "test/test-workflow.json" ]; then
        test_file="test/test-workflow.json"
    elif [ -n "$(find workflows -name '*.json' -type f 2>/dev/null | head -1)" ]; then
        test_file=$(find workflows -name '*.json' -type f 2>/dev/null | head -1)
    fi

    if [ -z "$test_file" ]; then
        echo -e "${YELLOW}⚠ No workflow file found to test${NC}"
        return 0
    fi

    echo "  Using test file: $test_file"

    # Validate JSON
    if ! jq empty "$test_file" 2>/dev/null; then
        echo -e "${RED}✗ Test file is not valid JSON${NC}"
        return 1
    fi
    echo -e "${GREEN}✓ Test file is valid JSON${NC}"

    # Extract workflow name
    local workflow_name=$(jq -r '.name // "Unknown"' "$test_file")
    echo -e "${GREEN}✓ Workflow name: $workflow_name${NC}"

    # Check for workflow ID (determines PUT vs POST)
    local workflow_id=$(jq -r '.id // empty' "$test_file")
    if [ -n "$workflow_id" ]; then
        echo -e "${GREEN}✓ Workflow ID present: $workflow_id (will use PUT)${NC}"
    else
        echo -e "${GREEN}✓ No workflow ID (will use POST)${NC}"
    fi

    return 0
}

# Test API connectivity (dry run or real)
test_api_connectivity() {
    echo ""
    echo -e "${BLUE}Testing API connectivity...${NC}"

    if [ "$DRY_RUN" = "true" ]; then
        echo -e "${YELLOW}⚠ Skipping actual API call in dry run mode${NC}"
        echo -e "${GREEN}✓ Would connect to: $N8N_BASE_URL/api/v1/workflows${NC}"
        return 0
    fi

    # Test connection to n8n API
    local response
    local http_code

    response=$(curl -s -w "\n%{http_code}" -X GET "$N8N_BASE_URL/api/v1/workflows" \
        -H "X-N8N-API-KEY: $N8N_API_KEY" \
        -H "Content-Type: application/json" \
        --connect-timeout 10 \
        2>&1) || {
        echo -e "${RED}✗ Failed to connect to n8n API${NC}"
        echo "  Error: Connection failed"
        return 1
    }

    http_code=$(echo "$response" | tail -n1)
    local body=$(echo "$response" | head -n-1)

    if [ "$http_code" -ge 200 ] && [ "$http_code" -lt 300 ]; then
        echo -e "${GREEN}✓ Successfully connected to n8n API (HTTP $http_code)${NC}"
        local workflow_count=$(echo "$body" | jq '.data | length' 2>/dev/null || echo "?")
        echo "  Found $workflow_count workflow(s)"
        return 0
    elif [ "$http_code" = "401" ] || [ "$http_code" = "403" ]; then
        echo -e "${RED}✗ Authentication failed (HTTP $http_code)${NC}"
        echo "  Check your N8N_API_KEY"
        return 1
    else
        echo -e "${RED}✗ API request failed (HTTP $http_code)${NC}"
        echo "  Response: $body"
        return 1
    fi
}

# Test error handling
test_error_handling() {
    echo ""
    echo -e "${BLUE}Testing error handling...${NC}"

    # Test with invalid JSON
    local invalid_json='{"name": "test", "nodes": invalid}'
    if echo "$invalid_json" | jq empty 2>/dev/null; then
        echo -e "${RED}✗ Should have caught invalid JSON${NC}"
        return 1
    fi
    echo -e "${GREEN}✓ Invalid JSON correctly detected${NC}"

    # Test missing required fields
    local missing_name='{"nodes": [], "connections": {}}'
    local name=$(echo "$missing_name" | jq -r '.name // empty')
    if [ -z "$name" ]; then
        echo -e "${GREEN}✓ Missing name field correctly detected${NC}"
    fi

    return 0
}

# Main test sequence
main() {
    local errors=0

    if ! check_env_vars; then
        echo ""
        echo -e "${RED}Environment check failed${NC}"
        exit 1
    fi

    test_auth_header || errors=$((errors + 1))
    test_request_format || errors=$((errors + 1))
    test_api_connectivity || errors=$((errors + 1))
    test_error_handling || errors=$((errors + 1))

    echo ""
    echo "=========================================="
    echo "Deployment Test Summary"
    echo "=========================================="

    if [ $errors -eq 0 ]; then
        echo -e "${GREEN}All tests passed!${NC}"
        exit 0
    else
        echo -e "${RED}$errors test(s) failed${NC}"
        exit 1
    fi
}

# Check for jq
if ! command -v jq &> /dev/null; then
    echo -e "${RED}Error: jq is required but not installed${NC}"
    echo "Install it with: brew install jq (macOS) or apt-get install jq (Ubuntu)"
    exit 1
fi

main
