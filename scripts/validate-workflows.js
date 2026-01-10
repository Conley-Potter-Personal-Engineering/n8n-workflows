#!/usr/bin/env node
/**
 * validate-workflows.js
 * =============================================================================
 * Validate n8n workflow JSON files for correctness and best practices.
 *
 * Usage:
 *   node scripts/validate-workflows.js                      # Validate all workflows
 *   node scripts/validate-workflows.js workflows/test.json  # Validate specific file
 *
 * Validations performed:
 *   - JSON syntax validity
 *   - Required n8n schema fields (name, nodes, connections)
 *   - Node structure (id, name, type, position)
 *   - No hardcoded secrets (credentials are templates only)
 *   - Unique node IDs within workflow
 * =============================================================================
 */

const fs = require('fs');
const path = require('path');

// ANSI color codes
const colors = {
  red: '\x1b[31m',
  green: '\x1b[32m',
  yellow: '\x1b[33m',
  blue: '\x1b[34m',
  reset: '\x1b[0m'
};

// Counters
let total = 0;
let passed = 0;
let failed = 0;
let warnings = 0;

/**
 * Print colored output
 */
function print(message, color = 'reset') {
  console.log(`${colors[color] || colors.reset}${message}${colors.reset}`);
}

/**
 * Get all JSON files from a directory
 */
function getWorkflowFiles(dir) {
  if (!fs.existsSync(dir)) {
    return [];
  }

  return fs.readdirSync(dir)
    .filter(file => file.endsWith('.json'))
    .map(file => path.join(dir, file));
}

/**
 * Validate required n8n workflow fields
 */
function validateRequiredFields(workflow, filePath) {
  const errors = [];
  const warns = [];

  // Check name
  if (!workflow.name || typeof workflow.name !== 'string') {
    errors.push('Missing or invalid required field: name (string)');
  }

  // Check nodes
  if (!workflow.nodes || !Array.isArray(workflow.nodes)) {
    errors.push('Missing or invalid required field: nodes (array)');
  }

  // Check connections
  if (workflow.connections === undefined) {
    warns.push('Missing connections field (may be intentional for single-node workflows)');
  } else if (typeof workflow.connections !== 'object') {
    errors.push('Invalid connections field: must be an object');
  }

  // Check active field (optional but recommended)
  if (workflow.active !== undefined && typeof workflow.active !== 'boolean') {
    warns.push('Field "active" should be a boolean');
  }

  return { errors, warns };
}

/**
 * Validate node structure
 */
function validateNodes(workflow) {
  const errors = [];
  const warns = [];

  if (!workflow.nodes || !Array.isArray(workflow.nodes)) {
    return { errors, warns };
  }

  const nodeIds = new Set();
  const requiredNodeFields = ['id', 'name', 'type', 'position'];

  workflow.nodes.forEach((node, index) => {
    // Check required fields
    requiredNodeFields.forEach(field => {
      if (node[field] === undefined) {
        errors.push(`Node ${index} missing required field: ${field}`);
      }
    });

    // Check position structure
    if (node.position && !Array.isArray(node.position)) {
      errors.push(`Node "${node.name || index}" has invalid position (should be array [x, y])`);
    }

    // Check for duplicate IDs
    if (node.id) {
      if (nodeIds.has(node.id)) {
        errors.push(`Duplicate node ID found: ${node.id}`);
      }
      nodeIds.add(node.id);
    }
  });

  return { errors, warns };
}

/**
 * Check for hardcoded secrets/credentials
 */
function checkForSecrets(workflow, content) {
  const errors = [];
  const warns = [];

  const sensitivePatterns = [
    /api[_-]?key['""]?\s*[:=]\s*['""][a-zA-Z0-9]{20,}/gi,
    /password['""]?\s*[:=]\s*['""][^'""]+/gi,
    /secret['""]?\s*[:=]\s*['""][^'""]+/gi,
    /token['""]?\s*[:=]\s*['""][a-zA-Z0-9_-]{20,}/gi,
    /Bearer [a-zA-Z0-9_-]{20,}/g
  ];

  for (const pattern of sensitivePatterns) {
    if (pattern.test(content)) {
      errors.push('Possible hardcoded secrets detected - use environment variables or n8n credentials');
      break;
    }
  }

  // Check if credentials are using expressions (good) vs hardcoded values (bad)
  if (workflow.nodes) {
    workflow.nodes.forEach(node => {
      if (node.credentials) {
        Object.entries(node.credentials).forEach(([credType, credValue]) => {
          if (typeof credValue === 'object' && credValue.id) {
            // This is fine - referencing a credential by ID
          } else if (typeof credValue === 'string' && !credValue.startsWith('={{')) {
            warns.push(`Node "${node.name}": Credential "${credType}" may have hardcoded value`);
          }
        });
      }
    });
  }

  return { errors, warns };
}

/**
 * Validate a single workflow file
 */
function validateWorkflow(filePath) {
  const fileName = path.basename(filePath);
  print(`\nValidating: ${fileName}`, 'blue');

  let content;
  let workflow;

  // 1. Check file exists and is readable
  try {
    content = fs.readFileSync(filePath, 'utf8');
  } catch (err) {
    print(`  ✗ Cannot read file: ${err.message}`, 'red');
    return false;
  }

  // 2. Check JSON syntax
  try {
    workflow = JSON.parse(content);
    print('  ✓ Valid JSON syntax', 'green');
  } catch (err) {
    print(`  ✗ Invalid JSON syntax: ${err.message}`, 'red');
    return false;
  }

  let allErrors = [];
  let allWarns = [];

  // 3. Validate required fields
  const { errors: fieldErrors, warns: fieldWarns } = validateRequiredFields(workflow, filePath);
  allErrors = allErrors.concat(fieldErrors);
  allWarns = allWarns.concat(fieldWarns);

  if (workflow.name) {
    print(`  ✓ Has name: ${workflow.name}`, 'green');
  }

  if (workflow.nodes && Array.isArray(workflow.nodes)) {
    print(`  ✓ Has nodes: ${workflow.nodes.length} node(s)`, 'green');
  }

  if (workflow.connections !== undefined) {
    print('  ✓ Has connections', 'green');
  }

  // 4. Validate node structure
  const { errors: nodeErrors, warns: nodeWarns } = validateNodes(workflow);
  allErrors = allErrors.concat(nodeErrors);
  allWarns = allWarns.concat(nodeWarns);

  if (nodeErrors.length === 0 && workflow.nodes && workflow.nodes.length > 0) {
    print('  ✓ All nodes have required fields', 'green');
    print('  ✓ All node IDs are unique', 'green');
  }

  // 5. Check for hardcoded secrets
  const { errors: secretErrors, warns: secretWarns } = checkForSecrets(workflow, content);
  allErrors = allErrors.concat(secretErrors);
  allWarns = allWarns.concat(secretWarns);

  if (secretErrors.length === 0) {
    print('  ✓ No obvious hardcoded secrets', 'green');
  }

  // Print all errors and warnings
  allErrors.forEach(error => print(`  ✗ ${error}`, 'red'));
  allWarns.forEach(warn => print(`  ⚠ ${warn}`, 'yellow'));

  // Summary for this workflow
  if (allErrors.length > 0) {
    print(`  FAILED with ${allErrors.length} error(s)`, 'red');
    return false;
  } else if (allWarns.length > 0) {
    warnings += allWarns.length;
    print(`  PASSED with ${allWarns.length} warning(s)`, 'yellow');
    return true;
  } else {
    print('  PASSED', 'green');
    return true;
  }
}

/**
 * Main function
 */
function main() {
  console.log('==========================================');
  console.log('n8n Workflow Validator (Node.js)');
  console.log('==========================================');

  const args = process.argv.slice(2);
  let workflowFiles = [];

  if (args.length === 0) {
    // Validate all workflows in workflows/ directory
    const workflowsDir = path.join(process.cwd(), 'workflows');
    workflowFiles = getWorkflowFiles(workflowsDir);

    if (workflowFiles.length === 0) {
      print('\nNo workflow files found in workflows/', 'yellow');
      process.exit(0);
    }
  } else {
    // Validate specific files
    workflowFiles = args.filter(file => {
      if (!fs.existsSync(file)) {
        print(`Warning: File not found: ${file}`, 'yellow');
        return false;
      }
      return true;
    });
  }

  // Validate each workflow
  for (const file of workflowFiles) {
    total++;
    if (validateWorkflow(file)) {
      passed++;
    } else {
      failed++;
    }
  }

  // Final summary
  console.log('\n==========================================');
  console.log('Validation Summary');
  console.log('==========================================');
  console.log(`  Total:    ${total}`);
  print(`  Passed:   ${passed}`, 'green');
  print(`  Failed:   ${failed}`, failed > 0 ? 'red' : 'reset');
  print(`  Warnings: ${warnings}`, warnings > 0 ? 'yellow' : 'reset');
  console.log('==========================================');

  process.exit(failed > 0 ? 1 : 0);
}

main();
