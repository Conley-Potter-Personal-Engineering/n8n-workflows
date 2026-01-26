# Scriptwriter Agent Workflow

## Overview
Invokes the Scriptwriter Agent HTTP endpoint to generate video scripts using trend and pattern context. This workflow handles input validation, retries, event emission, and response formatting while keeping all business logic in the backend service.

## Workflow File
- `workflows/scriptwriter-agent-workflow.json`

## Trigger
- **Webhook**: `POST /webhook/scriptwriter-agent`
- **Response mode**: Responds via Respond to Webhook nodes

## Input contract
### Required fields
- `product_id` (string, UUID)

### Optional fields
- `correlation_id` (string, UUID) - If not provided, will be auto-generated
- `experiment_id` (string, UUID)
- `context` (object)
  - `trend_snapshot_id` (string)
  - `creative_pattern_id` (string)
  - `creative_variables` (object)

### Auto-generated fields
- `workflow_id` (string, UUID) - Always generated internally; must not be provided as input

### Example payload
```json
{
  "product_id": "prod_123",
  "experiment_id": "exp_456",
  "correlation_id": "corr_789",
  "context": {
    "trend_snapshot_id": "trend_abc",
    "creative_pattern_id": "pattern_xyz",
    "creative_variables": {
      "hook_style": "problem-solution"
    }
  }
}
```

## Processing Steps
1. Validate required fields and return a 400 error if missing.
2. Emit `workflow.stage.start` system event (best-effort; does not block execution).
3. Invoke Scriptwriter Agent with retry and timeout handling.
4. On success, emit `workflow.stage.success` and return normalized response.
5. On failure, emit `workflow.stage.error` and return error response.
6. Error Trigger catches unhandled exceptions and emits `workflow.stage.error`.

## External Calls
- `POST ${ACE_BACKEND_URL}/api/system-events`
- `POST ${ACE_BACKEND_URL}/api/agents/scriptwriter/run`

## Retry and Timeout
- Scriptwriter Agent timeout: **120 seconds**
- Retry policy: **2 retries** with exponential backoff (30s, 60s)

## Success Response
```json
{
  "success": true,
  "data": {
    "script_id": "script_123",
    "script": "...",
    "workflow_id": "wf_auto_generated",
    "correlation_id": "corr_789_or_auto_generated"
  }
}
```

## Error Response
```json
{
  "success": false,
  "error": {
    "code": "SCRIPTWRITER_FAILED",
    "message": "error.message"
  },
  "workflow_id": "wf_auto_generated",
  "correlation_id": "corr_789_or_auto_generated"
}
```

## System Events Emitted
- `workflow.stage.start`
- `workflow.stage.success`
- `workflow.stage.error`

All events include `correlation_id` and `workflow_id`.

## Environment Variables
- `ACE_BACKEND_URL`
- `ACE_API_KEY`

## Notes
- Workflow is stateless; all domain logic lives in the backend agent.
- `context.creative_variables` defaults to `{}` if not provided.

## Validation
Local test suite output:

```
==========================================
n8n Workflows - Local Test Suite
==========================================

Checking prerequisites...

✓ jq installed
✓ Node.js installed (v23.9.0)

[1] Bash Workflow Validation (validate-workflows.sh)
Loading environment from credentials/.env file...
==========================================
n8n Workflow Validator
==========================================


Validating: scriptwriter-agent-workflow.json
  ✓ Valid JSON syntax
  ✓ Has name: Scriptwriter Agent Workflow
  ✓ Has nodes: 25 node(s)
  ✓ Has connections
  ✓ All node IDs are unique
  ✓ No obvious hardcoded secrets
  ✓ Webhook path follows convention: scriptwriter-agent
  ✓ Has Error Trigger node
  PASSED

==========================================
Validation Summary
==========================================
  Total:    1
  Passed:   1
  Failed:   0
  Warnings: 0
==========================================
    ✓ Passed

[2] Node.js Workflow Validation (validate-workflows.js)
==========================================
n8n Workflow Validator (Node.js)
==========================================

Validating: scriptwriter-agent-workflow.json
  ✓ Valid JSON syntax
  ✓ Has name: Scriptwriter Agent Workflow
  ✓ Has nodes: 25 node(s)
  ✓ Has connections
  ✓ All nodes have required fields
  ✓ All node IDs are unique
  ✓ No obvious hardcoded secrets
  PASSED

==========================================
Validation Summary
==========================================
  Total:    1
  Passed:   1
  Failed:   0
  Warnings: 0
==========================================
    ✓ Passed

[3] Test Fixture Validation
==========================================
n8n Workflow Validator (Node.js)
==========================================

Validating: test-workflow.json
  ✓ Valid JSON syntax
  ✓ Has name: Test Workflow - Ping API
  ✓ Has nodes: 2 node(s)
  ✓ Has connections
  ✓ All nodes have required fields
  ✓ All node IDs are unique
  ✓ No obvious hardcoded secrets
  PASSED

==========================================
Validation Summary
==========================================
  Total:    1
  Passed:   1
  Failed:   0
  Warnings: 0
==========================================
    ✓ Passed

[4] Deployment Script (dry run)
==========================================
n8n Deployment Test Script
==========================================

Running in DRY_RUN mode - no actual API calls will be made

✓ N8N_API_KEY is set
✓ N8N_BASE_URL is set: https://n8n.conleypotter.com

Testing authentication header construction...
✓ Auth header constructed correctly
  Header: X-N8N-API-KEY: eyJhbGci...

Testing API request formatting...
  Using test file: test/test-workflow.json
✓ Test file is valid JSON
✓ Workflow name: Test Workflow - Ping API
✓ No workflow ID (will use POST)

Testing API connectivity...
⚠ Skipping actual API call in dry run mode
✓ Would connect to: https://n8n.conleypotter.com/api/v1/workflows

Testing error handling...
✓ Invalid JSON correctly detected
✓ Missing name field correctly detected

==========================================
Deployment Test Summary
==========================================
All tests passed!
    ✓ Passed

==========================================
Local Test Summary
==========================================
  Total:  4
  Passed: 4
  Failed: 0
==========================================

All local tests passed!
```
