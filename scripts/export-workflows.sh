#!/usr/bin/env bash
# =============================================================================
# export-workflows.sh
# =============================================================================
# Export n8n workflows from an n8n instance to the workflows/ directory.
#
# Usage:
#   ./scripts/export-workflows.sh                    # Export all workflows
#   ./scripts/export-workflows.sh 123                # Export workflow by ID
#   ./scripts/export-workflows.sh 123 456 789        # Export multiple workflows
#
# Environment Variables:
#   N8N_API_KEY   - API key for n8n instance (required)
#   N8N_BASE_URL  - Base URL of n8n instance (required)
#
# The script will also read from a .env file if present.
# =============================================================================

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Output directory
OUTPUT_DIR="workflows"

# Load .env file if it exists
if [ -f "credentials/.env" ]; then
    echo "Loading environment from credentials/.env file..."
    export $(grep -v '^#' credentials/.env | xargs)
elif [ -f ".env" ]; then
    echo "Loading environment from .env file..."
    export $(grep -v '^#' .env | xargs)
fi

# Check required environment variables
if [ -z "$N8N_API_KEY" ]; then
    echo -e "${RED}Error: N8N_API_KEY environment variable is not set${NC}"
    echo "Set it in your environment or create a .env file with:"
    echo "  N8N_API_KEY=your-api-key"
    echo "in your credentials/.env file."
    exit 1
fi

if [ -z "$N8N_BASE_URL" ]; then
    echo -e "${RED}Error: N8N_BASE_URL environment variable is not set${NC}"
    echo "Set it in your environment or create a .env file with:"
    echo "  N8N_BASE_URL=https://your-n8n-instance.com"
    echo "in your credentials/.env file."
    exit 1
fi

# Check for jq
if ! command -v jq &> /dev/null; then
    echo -e "${RED}Error: jq is required but not installed${NC}"
    echo "Install it with: brew install jq (macOS) or apt-get install jq (Ubuntu)"
    exit 1
fi

# Create output directory if it doesn't exist
mkdir -p "$OUTPUT_DIR"

# Function to convert string to kebab-case
to_kebab_case() {
    echo "$1" | tr '[:upper:]' '[:lower:]' | sed 's/[^a-z0-9]/-/g' | sed 's/--*/-/g' | sed 's/^-//' | sed 's/-$//'
}

# Function to export a single workflow
export_workflow() {
    local workflow_id=$1

    echo "Exporting workflow ID: $workflow_id"

    response=$(curl -s -w "\n%{http_code}" -X GET "$N8N_BASE_URL/api/v1/workflows/$workflow_id" \
        -H "X-N8N-API-KEY: $N8N_API_KEY" \
        -H "Content-Type: application/json")

    http_code=$(echo "$response" | tail -n1)
    body=$(echo "$response" | head -n-1)

    if [ "$http_code" -ge 200 ] && [ "$http_code" -lt 300 ]; then
        # Extract workflow name and convert to kebab-case
        workflow_name=$(echo "$body" | jq -r '.name // "unnamed-workflow"')
        filename=$(to_kebab_case "$workflow_name")
        output_file="$OUTPUT_DIR/${filename}.json"

        # Format and save JSON
        echo "$body" | jq '.' > "$output_file"
        echo -e "${GREEN}✓ Exported: $workflow_name -> $output_file${NC}"
        return 0
    else
        echo -e "${RED}✗ Failed to export workflow $workflow_id (HTTP $http_code)${NC}"
        echo "  Response: $body"
        return 1
    fi
}

# Function to export all workflows
export_all_workflows() {
    echo -e "${BLUE}Fetching all workflows from n8n...${NC}"

    response=$(curl -s -w "\n%{http_code}" -X GET "$N8N_BASE_URL/api/v1/workflows" \
        -H "X-N8N-API-KEY: $N8N_API_KEY" \
        -H "Content-Type: application/json")

    http_code=$(echo "$response" | tail -n1)
    body=$(echo "$response" | head -n-1)

    if [ "$http_code" -ge 200 ] && [ "$http_code" -lt 300 ]; then
        # Extract workflow IDs
        workflow_ids=$(echo "$body" | jq -r '.data[].id')
        
        if [ -z "$workflow_ids" ]; then
            echo -e "${YELLOW}No workflows found in n8n instance${NC}"
            return 0
        fi

        exported=0
        failed=0

        for id in $workflow_ids; do
            if export_workflow "$id"; then
                exported=$((exported + 1))
            else
                failed=$((failed + 1))
            fi
        done

        echo ""
        echo "=========================================="
        echo "Export Summary:"
        echo "  Exported: $exported"
        echo "  Failed: $failed"
        echo "=========================================="

        if [ $failed -gt 0 ]; then
            return 1
        fi
    else
        echo -e "${RED}✗ Failed to fetch workflows (HTTP $http_code)${NC}"
        echo "Response: $body"
        return 1
    fi
}

# Main logic
if [ $# -eq 0 ]; then
    # No arguments - export all workflows
    echo "No workflow IDs specified, exporting all workflows..."
    export_all_workflows
else
    # Export specific workflows
    exported=0
    failed=0

    for workflow_id in "$@"; do
        if export_workflow "$workflow_id"; then
            exported=$((exported + 1))
        else
            failed=$((failed + 1))
        fi
    done

    echo ""
    echo "=========================================="
    echo "Export Summary:"
    echo "  Exported: $exported"
    echo "  Failed: $failed"
    echo "=========================================="

    if [ $failed -gt 0 ]; then
        exit 1
    fi
fi

exit 0
