#!/usr/bin/env bash
# =============================================================================
# import-workflows.sh
# =============================================================================
# Import n8n workflow files to an n8n instance using the API.
#
# Usage:
#   ./scripts/import-workflows.sh <workflow-file>           # Import single workflow
#   ./scripts/import-workflows.sh workflows/*.json          # Import all workflows
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
NC='\033[0m' # No Color

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

# Check for workflow file arguments
if [ $# -eq 0 ]; then
    echo -e "${YELLOW}Usage: $0 <workflow-file> [workflow-file...]${NC}"
    echo ""
    echo "Examples:"
    echo "  $0 workflows/content-pipeline.json"
    echo "  $0 workflows/*.json"
    exit 1
fi

# Import workflows
imported=0
failed=0

for workflow in "$@"; do
    if [ ! -f "$workflow" ]; then
        echo -e "${YELLOW}Warning: File not found: $workflow${NC}"
        continue
    fi

    workflow_name=$(basename "$workflow")
    echo "Processing $workflow_name..."

    # Validate JSON
    if ! jq empty "$workflow" 2>/dev/null; then
        echo -e "${RED}✗ Invalid JSON: $workflow_name${NC}"
        failed=$((failed + 1))
        continue
    fi

    # Extract workflow ID if present (for updates)
    workflow_id=$(jq -r '.id // empty' "$workflow")
    display_name=$(jq -r '.name // "Unknown"' "$workflow")

    if [ -n "$workflow_id" ]; then
        # Update existing workflow
        echo "  Updating workflow: $display_name (ID: $workflow_id)"
        update_payload=$(jq 'del(.active)' "$workflow")
        response=$(curl -s -w "\n%{http_code}" -X PUT "$N8N_BASE_URL/api/v1/workflows/$workflow_id" \
            -H "X-N8N-API-KEY: $N8N_API_KEY" \
            -H "Content-Type: application/json" \
            -d "$update_payload")
    else
        # Create new workflow
        echo "  Creating new workflow: $display_name"
        response=$(curl -s -w "\n%{http_code}" -X POST "$N8N_BASE_URL/api/v1/workflows" \
            -H "X-N8N-API-KEY: $N8N_API_KEY" \
            -H "Content-Type: application/json" \
            -d @"$workflow")
    fi

    http_code=$(echo "$response" | tail -n1)
    body=$(echo "$response" | head -n-1)

    if [ "$http_code" -ge 200 ] && [ "$http_code" -lt 300 ]; then
        new_id=$(echo "$body" | jq -r '.id // "unknown"')
        echo -e "${GREEN}✓ Successfully imported: $display_name (ID: $new_id)${NC}"
        imported=$((imported + 1))
    else
        echo -e "${RED}✗ Failed to import: $workflow_name (HTTP $http_code)${NC}"
        echo "  Response: $body"
        failed=$((failed + 1))
    fi
done

# Summary
echo ""
echo "=========================================="
echo "Import Summary:"
echo "  Imported: $imported"
echo "  Failed: $failed"
echo "=========================================="

if [ $failed -gt 0 ]; then
    exit 1
fi

exit 0
