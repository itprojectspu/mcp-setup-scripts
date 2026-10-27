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
GCLOUD_ACCOUNT="${GCLOUD_ACCOUNT:-}"
GCLOUD_PROJECT="${GCLOUD_PROJECT:-}"
INSTALL_DEPS=false
LOGIN_GCLOUD=false
SKIP_GCLOUD=false
SKIP_GITHUB=false
IS_TEST=false

print_usage() {
    cat << EOF
Usage: $(basename "$0") [OPTIONS]

Configures GitHub MCP Server and Google Cloud MCP Server.

Options:
  -t, --token <TOKEN>          GitHub Personal Access Token (or GITHUB_TOKEN env var)
  -c, --config <PATH>          Target mcp_config.json path (default: ~/.gemini/config/mcp_config.json)
  -b, --bin-dir <DIR>          Directory to install binaries (default: ~/.local/bin)
      --install-deps           Automatically install missing dependencies (Node.js/gcloud)
      --login-gcloud           Prompt/run Google Cloud authentication
      --gcloud-account <EMAIL> Google Cloud account email to log in
      --gcloud-project <ID>    Google Cloud project ID to set as default
      --skip-gcloud            Skip Google Cloud MCP setup
      --skip-github            Skip GitHub MCP setup
      --test                   Run in CI / Test mode (uses mock credentials, non-interactive)
  -h, --help                   Show this help message
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
        --install-deps)
            INSTALL_DEPS=true
            shift
            ;;
        --login-gcloud)
            LOGIN_GCLOUD=true
            shift
            ;;
        --gcloud-account)
            GCLOUD_ACCOUNT="$2"
            shift 2
            ;;
        --gcloud-project)
            GCLOUD_PROJECT="$2"
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

    # Check Node.js
    if ! command -v node >/dev/null 2>&1; then
        echo "    Warning: Node.js is not installed. Node >= 20 is required for @google-cloud/gcloud-mcp."
        if [ "$INSTALL_DEPS" = true ] || { [ "$IS_TEST" = false ] && [ -t 0 ]; }; then
            DO_INSTALL_NODE="n"
            if [ "$INSTALL_DEPS" = true ]; then
                DO_INSTALL_NODE="y"
            else
                read -r -p "    Would you like to install Node.js via nvm / package manager? [y/N]: " DO_INSTALL_NODE
            fi
            if [[ "$DO_INSTALL_NODE" =~ ^[Yy]$ ]]; then
                echo "    Installing Node.js..."
                curl -fsSL https://deb.nodesource.com/setup_20.x 2>/dev/null | bash - 2>/dev/null || true
            fi
        fi
    else
        NODE_VER="$(node -v)"
        echo "    ✓ Node.js detected: ${NODE_VER}"
    fi

    # Install @google-cloud/gcloud-mcp package globally if npm is present
    if command -v npm >/dev/null 2>&1; then
        if [ "$INSTALL_DEPS" = true ] || { [ "$IS_TEST" = false ] && [ -t 0 ]; }; then
            echo "    Ensuring @google-cloud/gcloud-mcp is installed..."
            npm install -g --prefix "$HOME/.local" @google-cloud/gcloud-mcp >/dev/null 2>&1 || true
        fi
    fi

    # Check gcloud CLI
    if ! command -v gcloud >/dev/null 2>&1; then
        echo "    Warning: gcloud CLI is not detected in PATH."
        DO_INSTALL_GCLOUD="n"
        if [ "$INSTALL_DEPS" = true ]; then
            DO_INSTALL_GCLOUD="y"
        elif [ "$IS_TEST" = false ] && [ -t 0 ]; then
            read -r -p "    Would you like to download and install Google Cloud SDK now? [y/N]: " DO_INSTALL_GCLOUD
        fi

        if [[ "$DO_INSTALL_GCLOUD" =~ ^[Yy]$ ]]; then
            echo "    Downloading and installing Google Cloud SDK..."
            curl -sSL https://sdk.cloud.google.com | bash -s -- --disable-prompts --install-dir="$HOME"
            if [ -f "$HOME/google-cloud-sdk/bin/gcloud" ]; then
                ln -sf "$HOME/google-cloud-sdk/bin/gcloud" "${BIN_DIR}/gcloud"
                ln -sf "$HOME/google-cloud-sdk/bin/gsutil" "${BIN_DIR}/gsutil"
                ln -sf "$HOME/google-cloud-sdk/bin/bq" "${BIN_DIR}/bq"
                export PATH="${BIN_DIR}:$HOME/google-cloud-sdk/bin:$PATH"
                echo "    ✓ Google Cloud SDK installed and linked to ${BIN_DIR}/gcloud"
            fi
        else
            echo "    Install it manually via: curl -sSL https://sdk.cloud.google.com | bash"
        fi
    fi

    # Verify gcloud if available and handle authentication
    if command -v gcloud >/dev/null 2>&1; then
        GCLOUD_VER="$(gcloud --version 2>&1 | head -n 1)"
        echo "    ✓ Google Cloud SDK detected: ${GCLOUD_VER}"

        ACTIVE_ACCOUNT="$(gcloud config get-value account 2>/dev/null || true)"
        if [ -n "$ACTIVE_ACCOUNT" ] && [ "$ACTIVE_ACCOUNT" != "(unset)" ]; then
            echo "    ✓ Active gcloud account: ${ACTIVE_ACCOUNT}"
        else
            ACTIVE_ACCOUNT=""
            echo "    [Notice] No active account logged in."
        fi

        # Interactive authentication option with browser link
        if [ "$IS_TEST" = false ]; then
            DO_LOGIN=false
            if [ "$LOGIN_GCLOUD" = true ] || [ -z "$ACTIVE_ACCOUNT" ]; then
                if [ "$LOGIN_GCLOUD" = true ]; then
                    DO_LOGIN=true
                elif [ -t 0 ]; then
                    read -r -p "    Would you like to authenticate Google Cloud now? [y/N]: " USER_WANTS_LOGIN
                    if [[ "$USER_WANTS_LOGIN" =~ ^[Yy]$ ]]; then
                        DO_LOGIN=true
                    fi
                fi
            fi

            if [ "$DO_LOGIN" = true ]; then
                echo ""
                echo "----------------------------------------------------------"
                echo " Google Cloud Authentication "
                echo "----------------------------------------------------------"
                echo " Select login mode:"
                echo "   [1] Show URL link to copy-paste into your browser (Recommended for remote/headless)"
                echo "   [2] Launch web browser automatically"
                echo -n " Choice [1/2] (default: 1): "
                AUTH_CHOICE="1"
                if [ -t 0 ]; then
                    read -r AUTH_CHOICE_INPUT
                    if [ -n "$AUTH_CHOICE_INPUT" ]; then
                        AUTH_CHOICE="$AUTH_CHOICE_INPUT"
                    fi
                fi

                AUTH_CMD=(gcloud auth login)
                if [ -n "$GCLOUD_ACCOUNT" ]; then
                    AUTH_CMD+=("$GCLOUD_ACCOUNT")
                fi

                if [ "$AUTH_CHOICE" = "1" ]; then
                    echo "    Generating browser login link..."
                    AUTH_CMD+=(--no-launch-browser)
                else
                    echo "    Opening browser for authorization..."
                fi

                "${AUTH_CMD[@]}" || {
                    echo "    Warning: Authentication process was cancelled or failed."
                }

                # Refresh active account
                ACTIVE_ACCOUNT="$(gcloud config get-value account 2>/dev/null || true)"
                if [ -n "$ACTIVE_ACCOUNT" ] && [ "$ACTIVE_ACCOUNT" != "(unset)" ]; then
                    echo "    ✓ Successfully logged in as: ${ACTIVE_ACCOUNT}"
                fi
            fi

            # Configure default project if specified
            if [ -n "$GCLOUD_PROJECT" ]; then
                echo "    Setting default Google Cloud project to: ${GCLOUD_PROJECT}"
                gcloud config set project "$GCLOUD_PROJECT" 2>/dev/null || true
            fi
        fi
    fi
fi

# ------------------------------------------------------------------------------
# 3. Update mcp_config.json
# ------------------------------------------------------------------------------
echo "[-] Updating MCP configuration at: ${CONFIG_PATH}"

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

chmod 600 "$CONFIG_PATH"
echo "    ✓ Permissions secured (chmod 600)"
echo "    ✓ Configuration saved successfully."

echo "=========================================================="
echo " Setup complete! "
echo "=========================================================="
