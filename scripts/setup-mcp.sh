#!/usr/bin/env bash
# ==============================================================================
# setup-mcp.sh - Cross-platform MCP Setup for Linux
# Configures GitHub MCP Server and Google Cloud MCP Server.
# ==============================================================================

set -euo pipefail

# Default values
CONFIG_PATH="${HOME}/.gemini/config/mcp_config.json"
BIN_DIR="${HOME}/.local/bin"
GITHUB_TOKEN="${GITHUB_PERSONAL_ACCESS_TOKEN:-${GITHUB_TOKEN:-}}"
SKIP_GCLOUD=false
SKIP_GITHUB=false
IS_TEST=false

print_usage() {
    cat << EOF
Usage: $(basename "$0") [OPTIONS]

Configures GitHub MCP Server and Google Cloud MCP Server.

Options:
  -t, --token <TOKEN>      GitHub Personal Access Token (or set GITHUB_TOKEN / GITHUB_PERSONAL_ACCESS_TOKEN)
  -c, --config <PATH>      Target mcp_config.json path (default: ~/.gemini/config/mcp_config.json)
  -b, --bin-dir <DIR>      Directory to install binaries (default: ~/.local/bin)
      --skip-gcloud        Skip Google Cloud MCP setup
      --skip-github        Skip GitHub MCP setup
      --test               Run in CI / Test mode (uses mock token if none provided)
  -h, --help               Show this help message
EOF
}

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case "$1" in
        -t|--token)
            GITHUB_TOKEN="$2"
            shift 2
            ;;
        -c|--config)
            CONFIG_PATH="$2"
            shift 2
            ;;
        -b|--bin-dir)
            BIN_DIR="$2"
            shift 2
            ;;
        --skip-gcloud)
            SKIP_GCLOUD=true
            shift
            ;;
        --skip-github)
            SKIP_GITHUB=true
            shift
            ;;
        --test)
            IS_TEST=true
            shift
            ;;
        -h|--help)
            print_usage
            exit 0
            ;;
        *)
            echo "Error: Unknown argument: $1" >&2
            print_usage
            exit 1
            ;;
    esac
done

echo "=========================================================="
echo " Starting MCP Configuration (Linux) "
echo "=========================================================="

mkdir -p "$BIN_DIR"
mkdir -p "$(dirname "$CONFIG_PATH")"

# ------------------------------------------------------------------------------
# 1. GitHub MCP Server Setup
# ------------------------------------------------------------------------------
if [ "$SKIP_GITHUB" = false ]; then
    echo "[-] Configuring GitHub MCP Server..."

    if [ -z "$GITHUB_TOKEN" ]; then
        if [ "$IS_TEST" = true ]; then
            echo "    [CI/Test] Using dummy token for testing purposes."
            GITHUB_TOKEN="ghp_mocktesttoken000000000000000000000000"
        elif [ -t 0 ]; then
            echo -n "    Please enter your GitHub Personal Access Token (hidden): "
            read -r -s GITHUB_TOKEN
            echo ""
        else
            echo "Error: GitHub token is required. Pass via --token or GITHUB_TOKEN env var." >&2
            exit 1
        fi
    fi

    if [ -z "$GITHUB_TOKEN" ]; then
        echo "Error: Empty GitHub token provided." >&2
        exit 1
    fi

    # Detect architecture
    ARCH="$(uname -m)"
    case "$ARCH" in
        x86_64|amd64)
            RELEASE_ARCH="x86_64"
            ;;
        aarch64|arm64)
            RELEASE_ARCH="arm64"
            ;;
        *)
            echo "Warning: Unsupported architecture '$ARCH', defaulting to x86_64"
            RELEASE_ARCH="x86_64"
            ;;
    esac

    GITHUB_BIN_PATH="${BIN_DIR}/github-mcp-server"
    if [ ! -f "$GITHUB_BIN_PATH" ] || [ "$IS_TEST" = true ]; then
        DOWNLOAD_URL="https://github.com/github/github-mcp-server/releases/latest/download/github-mcp-server_Linux_${RELEASE_ARCH}.tar.gz"
        echo "    Downloading github-mcp-server binary from official releases..."
        TMP_DIR="$(mktemp -d)"
        if curl -sSL -f "$DOWNLOAD_URL" -o "${TMP_DIR}/github-mcp.tar.gz"; then
            tar -xzf "${TMP_DIR}/github-mcp.tar.gz" -C "$TMP_DIR"
            if [ -f "${TMP_DIR}/github-mcp-server" ]; then
                mv "${TMP_DIR}/github-mcp-server" "$GITHUB_BIN_PATH"
                chmod +x "$GITHUB_BIN_PATH"
                echo "    ✓ Installed github-mcp-server to ${GITHUB_BIN_PATH}"
            fi
        else
            echo "    [Notice] Direct release download failed or was rate-limited."
            if ! command -v github-mcp-server >/dev/null 2>&1; then
                echo "    Warning: github-mcp-server executable not found in PATH."
            fi
        fi
        rm -rf "$TMP_DIR"
    else
        echo "    ✓ github-mcp-server binary already exists at ${GITHUB_BIN_PATH}"
    fi
fi

# ------------------------------------------------------------------------------
# 2. Google Cloud MCP Server Setup
# ------------------------------------------------------------------------------
if [ "$SKIP_GCLOUD" = false ]; then
    echo "[-] Checking Google Cloud MCP prerequisites..."

    if ! command -v node >/dev/null 2>&1; then
        echo "    Warning: Node.js is not installed. Node >= 20 is required for @google-cloud/gcloud-mcp."
    else
        NODE_VER="$(node -v)"
        echo "    ✓ Node.js detected: ${NODE_VER}"
    fi

    if ! command -v gcloud >/dev/null 2>&1; then
        echo "    Warning: gcloud CLI is not detected in PATH."
        echo "    Install it via: curl -sSL https://sdk.cloud.google.com | bash"
    else
        GCLOUD_VER="$(gcloud --version 2>&1 | head -n 1)"
        echo "    ✓ Google Cloud SDK detected: ${GCLOUD_VER}"
        
        # Check active account
        ACTIVE_ACCOUNT="$(gcloud config get-value account 2>/dev/null || true)"
        if [ -n "$ACTIVE_ACCOUNT" ] && [ "$ACTIVE_ACCOUNT" != "(unset)" ]; then
            echo "    ✓ Active gcloud account: ${ACTIVE_ACCOUNT}"
        else
            echo "    [Notice] No active account logged in. Run 'gcloud auth login' to authenticate."
        fi
    fi
fi

# ------------------------------------------------------------------------------
# 3. Update mcp_config.json
# ------------------------------------------------------------------------------
echo "[-] Updating MCP configuration at: ${CONFIG_PATH}"

# Python or Node-based safe JSON merger to prevent corrupting existing configs
export PY_CONFIG_PATH="$CONFIG_PATH"
export PY_GITHUB_TOKEN="$GITHUB_TOKEN"
export PY_SKIP_GITHUB="$SKIP_GITHUB"
export PY_SKIP_GCLOUD="$SKIP_GCLOUD"

if command -v python3 >/dev/null 2>&1; then
    python3 - << 'EOF'
import os
import json

config_path = os.environ['PY_CONFIG_PATH']
github_token = os.environ.get('PY_GITHUB_TOKEN', '')
skip_github = os.environ.get('PY_SKIP_GITHUB') == 'true'
skip_gcloud = os.environ.get('PY_SKIP_GCLOUD') == 'true'

data = {"mcpServers": {}}
if os.path.exists(config_path):
    try:
        with open(config_path, 'r', encoding='utf-8') as f:
            data = json.load(f)
            if "mcpServers" not in data or not isinstance(data["mcpServers"], dict):
                data["mcpServers"] = {}
    except Exception as e:
        print(f"    Warning: Existing config could not be parsed ({e}), initializing fresh config.")
        data = {"mcpServers": {}}

if not skip_github and github_token:
    data["mcpServers"]["github"] = {
        "command": "github-mcp-server",
        "args": ["stdio"],
        "env": {
            "GITHUB_PERSONAL_ACCESS_TOKEN": github_token
        }
    }

if not skip_gcloud:
    data["mcpServers"]["gcloud"] = {
        "command": "npx",
        "args": ["-y", "@google-cloud/gcloud-mcp"]
    }

with open(config_path, 'w', encoding='utf-8') as f:
    json.dump(data, f, indent=2)
    f.write("\n")
EOF
elif command -v node >/dev/null 2>&1; then
    node - << 'EOF'
const fs = require('fs');
const configPath = process.env.PY_CONFIG_PATH;
const githubToken = process.env.PY_GITHUB_TOKEN || '';
const skipGithub = process.env.PY_SKIP_GITHUB === 'true';
const skipGcloud = process.env.PY_SKIP_GCLOUD === 'true';

let data = { mcpServers: {} };
if (fs.existsSync(configPath)) {
    try {
        data = JSON.parse(fs.readFileSync(configPath, 'utf8'));
        if (!data.mcpServers || typeof data.mcpServers !== 'object') {
            data.mcpServers = {};
        }
    } catch (e) {
        data = { mcpServers: {} };
    }
}

if (!skipGithub && githubToken) {
    data.mcpServers.github = {
        command: "github-mcp-server",
        args: ["stdio"],
        env: {
            GITHUB_PERSONAL_ACCESS_TOKEN: githubToken
        }
    };
}

if (!skipGcloud) {
    data.mcpServers.gcloud = {
        command: "npx",
        args: ["-y", "@google-cloud/gcloud-mcp"]
    };
}

fs.writeFileSync(configPath, JSON.stringify(data, null, 2) + "\n", 'utf8');
EOF
else
    echo "Error: Either python3 or node is required to safely merge JSON configuration." >&2
    exit 1
fi

# Set restrictive permissions on config file to protect credentials
chmod 600 "$CONFIG_PATH"
echo "    ✓ Permissions secured (chmod 600)"
echo "    ✓ Configuration saved successfully."

echo "=========================================================="
echo " Setup complete! "
echo "=========================================================="
