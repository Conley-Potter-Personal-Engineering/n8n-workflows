# n8n-workflows

Version-controlled n8n workflow definitions for ACE system orchestration.

## 🏗️ Architecture Context

n8n serves as the **orchestration layer** in the ACE architecture, handling:

- **Orchestration**: Coordinating multi-step workflows
- **Sequencing**: Managing the order of operations
- **Retries**: Handling transient failures with exponential backoff
- **External API Calls**: Integrating with TikTok, YouTube, and other platforms

The **ACE backend** handles:

- **Business Logic**: All domain-specific processing
- **LLM Calls**: AI/ML inference requests
- **Persistence**: Database operations via Supabase
- **Scoring**: Content quality and performance metrics

> [!IMPORTANT]
> Agents are stateless HTTP services. All domain logic lives in the backend, **not** in workflow Code nodes.

### Observability Requirements

All workflows must:
- Emit `system_events` for observability
- Include `correlation_id` for request tracing
- Include `workflow_id` for workflow identification

## 📁 Repository Structure

```
n8n-workflows/
├── workflows/          # n8n workflow JSON files
│   └── .gitkeep
├── credentials/        # Credential templates (NO actual secrets)
│   └── README.md
├── scripts/            # Utility scripts for workflow management
│   └── .gitkeep
├── .github/
│   └── workflows/      # CI/CD pipeline definitions
├── .gitignore
└── README.md
```

## 🔄 Workflow Development Process

### 1. Generate Workflow JSON

Use coding models to generate n8n workflow JSON files. See [Prompting Coding Models to Generate n8n Workflows](https://www.notion.so/Prompting-Coding-Models-to-Generate-n8n-Workflows-b90925b54b1040c6a9f5ba02b236fb64) for best practices.

### 2. Save to Repository

Save the generated workflow JSON to the `workflows/` directory:

```bash
workflows/my-new-workflow.json
```

### 3. Open Pull Request

Create a PR with:
- Clear description of workflow purpose
- Test plan documenting how the workflow was validated
- Any affected API contracts or dependencies

### 4. Review Process

Reviewers should verify:
- JSON structure is valid
- API contracts match backend expectations
- Error handling and retry logic are present
- `system_events` are emitted at key stages
- `correlation_id` and `workflow_id` are included

### 5. Merge & Deploy

Once approved, merge to `main`. CI automatically deploys the workflow to the n8n instance.

## ⚙️ Prerequisites

Before working with this repository, ensure you have:

1. **n8n Instance**: Running on Digital Ocean with API access enabled
2. **GitHub Actions**: Enabled for automated deployments
3. **Backend API**: ACE backend endpoints exposed and accessible

## 🔐 Environment Variables

Set these environment variables in your n8n instance:

| Variable | Description |
|----------|-------------|
| `ACE_BACKEND_URL` | Base URL for the ACE backend API |
| `ACE_API_KEY` | API key for authenticating with ACE backend |
| `TIKTOK_ACCESS_TOKEN` | OAuth token for TikTok API access |
| `SUPABASE_URL` | Supabase project URL |
| `SUPABASE_KEY` | Supabase service role key |

> [!CAUTION]
> Never commit actual credentials or secrets to this repository. All secrets should be configured directly in the n8n instance.

## 🧪 Testing

### Local Tests

Run the full local test suite:

```bash
./scripts/local-test.sh
```

This runs:
1. **Bash Validation** - `scripts/validate-workflows.sh`
2. **Node.js Validation** - `scripts/validate-workflows.js`
3. **Test Fixture Validation** - Validates `test/test-workflow.json`
4. **Deployment Dry Run** - `scripts/test-deploy.sh` (no API calls)

### Individual Test Scripts

```bash
# Validate all workflows (Bash)
./scripts/validate-workflows.sh

# Validate all workflows (Node.js)
node scripts/validate-workflows.js

# Validate a specific workflow
node scripts/validate-workflows.js workflows/my-workflow.json

# Test deployment script (dry run)
DRY_RUN=true ./scripts/test-deploy.sh

# Run integration tests (requires test n8n instance)
N8N_TEST_API_KEY=xxx N8N_TEST_BASE_URL=https://test.n8n.io ./scripts/integration-test.sh
```

### Mock API Server

For local testing without a real n8n instance:

```bash
# Start mock server on port 5678
node test/mock-api.js

# In another terminal, run tests against mock
N8N_BASE_URL=http://localhost:5678 N8N_API_KEY=test-key ./scripts/test-deploy.sh
```

### Environment Variables for Testing

| Variable | Description |
|----------|-------------|
| `DRY_RUN` | Set to `true` to skip API calls in test scripts |
| `N8N_TEST_API_KEY` | API key for test n8n instance (integration tests) |
| `N8N_TEST_BASE_URL` | URL of test n8n instance (integration tests) |

### CI/CD Test Workflow

The `.github/workflows/test.yml` runs on:
- **Pull requests** to `main`/`master`: Validation + dry-run tests
- **Push to any branch**: If changes in `workflows/`, `scripts/`, or `test/`
- **Merge to main**: Full integration tests (if secrets configured)

GitHub Secrets needed for integration tests:
- `N8N_TEST_API_KEY` - Test n8n instance API key
- `N8N_TEST_BASE_URL` - Test n8n instance URL

### Manual Testing Instructions

#### Import Workflow Locally

1. Open your local n8n instance
2. Navigate to **Workflows** → **Import from File**
3. Select the workflow JSON from `workflows/`
4. The workflow will appear in your workflow list

#### Test Webhook Triggers

1. Activate the imported workflow
2. Copy the webhook URL from the Webhook node
3. Send a test request:

```bash
curl -X POST https://your-n8n-instance.com/webhook/your-webhook-id \
  -H "Content-Type: application/json" \
  -d '{"test": true, "correlation_id": "test-123"}'
```

#### Verify system_events Logging

1. Execute the workflow
2. Check the ACE backend logs or Supabase `system_events` table
3. Verify events contain:
   - `event_type`: workflow stage (e.g., `workflow.stage.start`)
   - `correlation_id`: matching your request
   - `workflow_id`: identifier for the workflow
   - `payload`: relevant context data

## 🚀 CI/CD

Automated deployment is configured via GitHub Actions. On merge to `main`:

1. Workflow JSON is validated
2. n8n API is called to update/create the workflow
3. Deployment status is reported back to the PR

See `.github/workflows/deploy.yml` for implementation details.

## 📚 Reference Documentation

- [ACE Architecture: Introduction of n8n Orchestration Layer](https://www.notion.so/ACE-Architecture-Update-Introduction-of-n8n-Orchestration-Layer-2d6be295a73e8010928cc2c66990a82d)
- [Prompting Coding Models to Generate n8n Workflows](https://www.notion.so/Prompting-Coding-Models-to-Generate-n8n-Workflows-b90925b54b1040c6a9f5ba02b236fb64)
- Backend API Documentation (link to your API docs)

## 🤝 Contributing

1. Create a feature branch from `main`
2. Generate or modify workflow JSON
3. Test locally using the instructions above
4. Open a PR with description and test plan
5. Address review feedback
6. Merge once approved

---

**Questions?** Check the reference documentation or reach out to the team.
