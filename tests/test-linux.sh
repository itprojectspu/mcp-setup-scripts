#!/usr/bin/env bash
set -euo pipefail

echo ">>> Running Linux MCP setup test suite..."

TEST_DIR="$(mktemp -d)"
TEST_CONFIG="${TEST_DIR}/mcp_config.json"
TEST_BIN="${TEST_DIR}/bin"
trap 'rm -rf "$TEST_DIR"' EXIT

# Execute script with test mode and custom config path
./scripts/setup-mcp.sh \
    --test \
    --config "$TEST_CONFIG" \
    --bin-dir "$TEST_BIN"

# Check config file existence
if [ ! -f "$TEST_CONFIG" ]; then
    echo "FAIL: Test config was not created at $TEST_CONFIG"
    exit 1
fi

# Check file permissions (should be 600)
PERMS="$(stat -c "%a" "$TEST_CONFIG" 2>/dev/null || stat -f "%OLp" "$TEST_CONFIG" 2>/dev/null || true)"
if [ -n "$PERMS" ] && [ "$PERMS" != "600" ]; then
    echo "FAIL: Config file permissions are $PERMS, expected 600"
    exit 1
fi

# Verify JSON schema and contents
python3 - << EOF
import json, sys

with open('$TEST_CONFIG') as f:
    data = json.load(f)

assert "mcpServers" in data, "Missing mcpServers"
assert "github" in data["mcpServers"], "Missing github server"
assert "gcloud" in data["mcpServers"], "Missing gcloud server"

github = data["mcpServers"]["github"]
assert github["command"] == "github-mcp-server"
assert "GITHUB_PERSONAL_ACCESS_TOKEN" in github.get("env", {})

gcloud = data["mcpServers"]["gcloud"]
assert gcloud["command"] == "npx"

print(">>> Linux test passed: JSON schema and values are valid!")
EOF

echo ">>> All Linux tests completed successfully!"
