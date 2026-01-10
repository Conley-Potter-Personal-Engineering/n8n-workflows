#!/usr/bin/env bash
# =============================================================================
# validate-workflows.sh
# =============================================================================
# Validate n8n workflow JSON files for correctness and best practices.
#
# Usage:
#   ./scripts/validate-workflows.sh                          # Validate all workflows
#   ./scripts/validate-workflows.sh workflows/example.json   # Validate specific workflow
#
# Validations performed:
#   - JSON syntax validity
#   - Required fields present (name, nodes, connections)
#   - Unique node IDs within workflow
#   - No hardcoded secrets/URLs
#   - Webhook paths follow naming convention
#   - Error Trigger node present (recommended)
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
    echo "Loading environment from credentials/.env file..."
    export $(grep -v '^#' credentials/.env | xargs)
elif [ -f ".env" ]; then
    echo "Loading environment from .env file..."
    export $(grep -v '^#' .env | xargs)
fi

# Counters
total=0
passed=0
failed=0
warnings=0

# Check for jq
if ! command -v jq &> /dev/null; then
    echo -e "${RED}Error: jq is required but not installed${NC}"
    echo "Install it with: brew install jq (macOS) or apt-get install jq (Ubuntu)"
    exit 1
fi

# Function to validate a single workflow
validate_workflow() {
    local workflow=$1
    local workflow_name=$(basename "$workflow")
    local errors=0
    local warns=0

    echo -e "${BLUE}Validating: $workflow_name${NC}"

    # 1. Check JSON validity
    if ! jq empty "$workflow" 2>/dev/null; then
        echo -e "  ${RED}✗ Invalid JSON syntax${NC}"
        return 1
    fi
    echo -e "  ${GREEN}✓ Valid JSON syntax${NC}"

    # 2. Check required fields
    local name=$(jq -r '.name // empty' "$workflow")
    local nodes=$(jq -r '.nodes // empty' "$workflow")
    local connections=$(jq -r '.connections // empty' "$workflow")

    if [ -z "$name" ]; then
        echo -e "  ${RED}✗ Missing required field: name${NC}"
        errors=$((errors + 1))
    else
        echo -e "  ${GREEN}✓ Has name: $name${NC}"
    fi

    if [ "$nodes" = "null" ] || [ -z "$nodes" ]; then
        echo -e "  ${RED}✗ Missing required field: nodes${NC}"
        errors=$((errors + 1))
    else
        node_count=$(jq '.nodes | length' "$workflow")
        echo -e "  ${GREEN}✓ Has nodes: $node_count node(s)${NC}"
    fi

    if [ "$connections" = "null" ]; then
        echo -e "  ${YELLOW}⚠ Missing connections field (may be intentional for single-node workflows)${NC}"
        warns=$((warns + 1))
    else
        echo -e "  ${GREEN}✓ Has connections${NC}"
    fi

    # 3. Check for unique node IDs
    local duplicate_ids=$(jq -r '[.nodes[].id] | group_by(.) | map(select(length > 1)) | flatten | unique | .[]' "$workflow" 2>/dev/null)
    if [ -n "$duplicate_ids" ]; then
        echo -e "  ${RED}✗ Duplicate node IDs found: $duplicate_ids${NC}"
        errors=$((errors + 1))
    else
        echo -e "  ${GREEN}✓ All node IDs are unique${NC}"
    fi

    # 4. Check for hardcoded secrets (basic pattern matching)
    local sensitive_patterns=(
        'api[_-]?key.*[=:]["\x27][a-zA-Z0-9]{20,}'
        'password["\x27]?\s*[=:]\s*["\x27][^"\x27]+'
        'secret["\x27]?\s*[=:]\s*["\x27][^"\x27]+'
        'token["\x27]?\s*[=:]\s*["\x27][a-zA-Z0-9]{20,}'
        'Bearer [a-zA-Z0-9_-]{20,}'
    )

    local has_hardcoded=false
    for pattern in "${sensitive_patterns[@]}"; do
        if grep -qiE "$pattern" "$workflow" 2>/dev/null; then
            has_hardcoded=true
            break
        fi
    done

    if [ "$has_hardcoded" = true ]; then
        echo -e "  ${RED}✗ Possible hardcoded secrets detected - use environment variables${NC}"
        errors=$((errors + 1))
    else
        echo -e "  ${GREEN}✓ No obvious hardcoded secrets${NC}"
    fi

    # 5. Check webhook paths naming convention (kebab-case, starts with /)
    local webhook_nodes=$(jq -r '.nodes[] | select(.type == "n8n-nodes-base.webhook") | .parameters.path // empty' "$workflow" 2>/dev/null)
    if [ -n "$webhook_nodes" ]; then
        while IFS= read -r path; do
            if [ -n "$path" ]; then
                # Check if path starts with / or is just the path segment
                if ! echo "$path" | grep -qE '^[a-z0-9/-]+$'; then
                    echo -e "  ${YELLOW}⚠ Webhook path may not follow kebab-case convention: $path${NC}"
                    warns=$((warns + 1))
                else
                    echo -e "  ${GREEN}✓ Webhook path follows convention: $path${NC}"
                fi
            fi
        done <<< "$webhook_nodes"
    fi

    # 6. Check for Error Trigger node (recommended for production workflows)
    local has_error_trigger=$(jq '.nodes[] | select(.type == "n8n-nodes-base.errorTrigger") | .id' "$workflow" 2>/dev/null)
    if [ -z "$has_error_trigger" ]; then
        echo -e "  ${YELLOW}⚠ No Error Trigger node found (recommended for production)${NC}"
        warns=$((warns + 1))
    else
        echo -e "  ${GREEN}✓ Has Error Trigger node${NC}"
    fi

    # Summary for this workflow
    if [ $errors -gt 0 ]; then
        echo -e "  ${RED}FAILED with $errors error(s)${NC}"
        return 1
    elif [ $warns -gt 0 ]; then
        echo -e "  ${YELLOW}PASSED with $warns warning(s)${NC}"
        warnings=$((warnings + warns))
        return 0
    else
        echo -e "  ${GREEN}PASSED${NC}"
        return 0
    fi
}

# Main logic
echo "=========================================="
echo "n8n Workflow Validator"
echo "=========================================="
echo ""

if [ $# -eq 0 ]; then
    # Validate all workflows in workflows/
    if [ ! -d "workflows" ]; then
        echo -e "${YELLOW}No workflows/ directory found${NC}"
        exit 0
    fi

    workflow_files=$(find workflows -name "*.json" -type f 2>/dev/null)
    if [ -z "$workflow_files" ]; then
        echo -e "${YELLOW}No workflow files found in workflows/${NC}"
        exit 0
    fi

    for workflow in $workflow_files; do
        total=$((total + 1))
        echo ""
        if validate_workflow "$workflow"; then
            passed=$((passed + 1))
        else
            failed=$((failed + 1))
        fi
    done
else
    # Validate specific workflows
    for workflow in "$@"; do
        if [ ! -f "$workflow" ]; then
            echo -e "${RED}Error: File not found: $workflow${NC}"
            failed=$((failed + 1))
            continue
        fi
        total=$((total + 1))
        echo ""
        if validate_workflow "$workflow"; then
            passed=$((passed + 1))
        else
            failed=$((failed + 1))
        fi
    done
fi

# Final summary
echo ""
echo "=========================================="
echo "Validation Summary"
echo "=========================================="
echo "  Total:    $total"
echo -e "  ${GREEN}Passed:   $passed${NC}"
echo -e "  ${RED}Failed:   $failed${NC}"
echo -e "  ${YELLOW}Warnings: $warnings${NC}"
echo "=========================================="

if [ $failed -gt 0 ]; then
    exit 1
fi

exit 0
