#!/usr/bin/env node
/**
 * mock-api.js
 * =============================================================================
 * Simple HTTP server to mock n8n API responses for local testing.
 *
 * Usage:
 *   node test/mock-api.js         # Start server on port 5678
 *   node test/mock-api.js 3000    # Start server on custom port
 *
 * Endpoints:
 *   GET  /api/v1/workflows             - List all workflows
 *   GET  /api/v1/workflows/:id         - Get workflow by ID
 *   POST /api/v1/workflows             - Create workflow
 *   PUT  /api/v1/workflows/:id         - Update workflow
 *   DELETE /api/v1/workflows/:id       - Delete workflow
 * =============================================================================
 */

const http = require('http');
const url = require('url');

const PORT = process.argv[2] || 5678;

// In-memory workflow storage
const workflows = new Map();
let nextId = 1;

// Seed with a test workflow
workflows.set('test-workflow-1', {
  id: 'test-workflow-1',
  name: 'Test Workflow',
  nodes: [],
  connections: {},
  active: false,
  createdAt: new Date().toISOString(),
  updatedAt: new Date().toISOString()
});

/**
 * Parse JSON body from request
 */
function parseBody(req) {
  return new Promise((resolve, reject) => {
    let body = '';
    req.on('data', chunk => body += chunk);
    req.on('end', () => {
      try {
        resolve(body ? JSON.parse(body) : {});
      } catch (err) {
        reject(err);
      }
    });
    req.on('error', reject);
  });
}

/**
 * Send JSON response
 */
function sendJson(res, statusCode, data) {
  res.writeHead(statusCode, { 'Content-Type': 'application/json' });
  res.end(JSON.stringify(data, null, 2));
}

/**
 * Validate API key header
 */
function validateAuth(req, res) {
  const apiKey = req.headers['x-n8n-api-key'];
  if (!apiKey) {
    sendJson(res, 401, { error: 'Missing X-N8N-API-KEY header' });
    return false;
  }
  if (apiKey === 'invalid-key') {
    sendJson(res, 403, { error: 'Invalid API key' });
    return false;
  }
  return true;
}

/**
 * Handle requests
 */
async function handleRequest(req, res) {
  const parsedUrl = url.parse(req.url, true);
  const path = parsedUrl.pathname;
  const method = req.method;

  console.log(`[${new Date().toISOString()}] ${method} ${path}`);

  // CORS headers for local testing
  res.setHeader('Access-Control-Allow-Origin', '*');
  res.setHeader('Access-Control-Allow-Methods', 'GET, POST, PUT, DELETE, OPTIONS');
  res.setHeader('Access-Control-Allow-Headers', 'Content-Type, X-N8N-API-KEY');

  if (method === 'OPTIONS') {
    res.writeHead(204);
    res.end();
    return;
  }

  // Auth check (except for health endpoint)
  if (path !== '/health' && !validateAuth(req, res)) {
    return;
  }

  // Health check endpoint
  if (path === '/health') {
    sendJson(res, 200, { status: 'ok' });
    return;
  }

  // Workflow endpoints
  const workflowMatch = path.match(/^\/api\/v1\/workflows(?:\/(.+))?$/);

  if (!workflowMatch) {
    sendJson(res, 404, { error: 'Not found' });
    return;
  }

  const workflowId = workflowMatch[1];

  try {
    switch (method) {
      case 'GET':
        if (workflowId) {
          // Get single workflow
          const workflow = workflows.get(workflowId);
          if (!workflow) {
            sendJson(res, 404, { error: 'Workflow not found' });
          } else {
            sendJson(res, 200, workflow);
          }
        } else {
          // List all workflows
          sendJson(res, 200, { data: Array.from(workflows.values()) });
        }
        break;

      case 'POST':
        const newWorkflow = await parseBody(req);
        const id = `workflow-${nextId++}`;
        const created = {
          ...newWorkflow,
          id,
          createdAt: new Date().toISOString(),
          updatedAt: new Date().toISOString()
        };
        workflows.set(id, created);
        sendJson(res, 201, created);
        break;

      case 'PUT':
        if (!workflowId) {
          sendJson(res, 400, { error: 'Workflow ID required' });
          return;
        }
        if (!workflows.has(workflowId)) {
          sendJson(res, 404, { error: 'Workflow not found' });
          return;
        }
        const updateData = await parseBody(req);
        const updated = {
          ...workflows.get(workflowId),
          ...updateData,
          id: workflowId,
          updatedAt: new Date().toISOString()
        };
        workflows.set(workflowId, updated);
        sendJson(res, 200, updated);
        break;

      case 'DELETE':
        if (!workflowId) {
          sendJson(res, 400, { error: 'Workflow ID required' });
          return;
        }
        if (!workflows.has(workflowId)) {
          sendJson(res, 404, { error: 'Workflow not found' });
          return;
        }
        workflows.delete(workflowId);
        sendJson(res, 200, { success: true });
        break;

      default:
        sendJson(res, 405, { error: 'Method not allowed' });
    }
  } catch (err) {
    console.error('Error:', err);
    sendJson(res, 500, { error: err.message });
  }
}

// Create and start server
const server = http.createServer(handleRequest);

server.listen(PORT, () => {
  console.log(`Mock n8n API server running on http://localhost:${PORT}`);
  console.log('Available endpoints:');
  console.log('  GET    /health');
  console.log('  GET    /api/v1/workflows');
  console.log('  GET    /api/v1/workflows/:id');
  console.log('  POST   /api/v1/workflows');
  console.log('  PUT    /api/v1/workflows/:id');
  console.log('  DELETE /api/v1/workflows/:id');
  console.log('\nPress Ctrl+C to stop');
});
