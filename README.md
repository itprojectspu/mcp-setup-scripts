# MCP Setup Scripts (Windows & Linux)

Cross-platform configuration scripts for Model Context Protocol (MCP) servers:
- **GitHub MCP Server** (`github-mcp-server` official Go binary)
- **Google Cloud MCP Server** (`@google-cloud/gcloud-mcp`)

Includes automated CI workflows to test configuration and ensure **zero secrets** are committed.

---

## 🔒 Security & Best Practices

- **Zero Secret Exposure**: Tokens and credentials are **never hardcoded**.
- The scripts accept tokens via:
  1. Environment variable (`GITHUB_PERSONAL_ACCESS_TOKEN` or `GITHUB_TOKEN`).
  2. Hidden interactive CLI prompt (`read -s` on Linux, `Read-Host -AsSecureString` on Windows).
- Configuration files on Linux are automatically protected with restrictive permissions (`chmod 600`).
- A comprehensive `.gitignore` prevents committing `.env`, keyfiles, and active credentials.
- CI includes automated scanning for secret leaks.

---

## 📋 Prerequisites

| Component | Linux | Windows |
| :--- | :--- | :--- |
| **Node.js** | `>= 20.x` | `>= 20.x` |
| **Python** | `>= 3.8` (for JSON merge) | Not required |
| **Shell** | `bash`, `curl`, `tar` | PowerShell 5.1+ / PowerShell 7+ |
| **Google Cloud CLI** | Recommended (`gcloud`) | Recommended (`gcloud`) |

---

## 🚀 Quick Start

### Linux & macOS

1. Make the script executable:
   ```bash
   chmod +x scripts/setup-mcp.sh
   ```

2. Run interactively (you will be prompted to enter your GitHub PAT securely):
   ```bash
   ./scripts/setup-mcp.sh
   ```

3. Or pass your token via environment variable:
   ```bash
   export GITHUB_PERSONAL_ACCESS_TOKEN="ghp_yourTokenHere"
   ./scripts/setup-mcp.sh
   ```

#### Options

```
Usage: setup-mcp.sh [OPTIONS]

Options:
  -t, --token <TOKEN>      GitHub Personal Access Token
  -c, --config <PATH>      Target mcp_config.json path (default: ~/.gemini/config/mcp_config.json)
  -b, --bin-dir <DIR>      Directory to install binaries (default: ~/.local/bin)
      --skip-gcloud        Skip Google Cloud MCP setup
      --skip-github        Skip GitHub MCP setup
      --test               Run in CI / Test mode with mock credentials
  -h, --help               Show help message
```

---

### Windows (PowerShell)

1. Open PowerShell and navigate to the repository directory.
2. Run interactively:
   ```powershell
   .\scripts\setup-mcp.ps1
   ```

3. Or pass your token as a parameter or via environment variable:
   ```powershell
   $env:GITHUB_PERSONAL_ACCESS_TOKEN = "ghp_yourTokenHere"
   .\scripts\setup-mcp.ps1
   ```

#### Parameters

```powershell
.\scripts\setup-mcp.ps1 `
    -GitHubToken "ghp_yourTokenHere" `
    -ConfigPath "$env:USERPROFILE\.gemini\config\mcp_config.json" `
    -InstallDir "$env:LOCALAPPDATA\Programs\mcp-servers" `
    -SkipGCloud `
    -SkipGitHub `
    -Test
```

---

## 📄 Generated Configuration Format

The scripts generate or safely merge into `mcp_config.json`:

```json
{
  "mcpServers": {
    "github": {
      "command": "github-mcp-server",
      "args": ["stdio"],
      "env": {
        "GITHUB_PERSONAL_ACCESS_TOKEN": "YOUR_TOKEN"
      }
    },
    "gcloud": {
      "command": "npx",
      "args": ["-y", "@google-cloud/gcloud-mcp"]
    }
  }
}
```

---

## 🧪 Continuous Integration (CI)

This repository includes a multi-platform GitHub Actions workflow (`.github/workflows/ci.yml`):

1. **Security & Lint**:
   - Secret scan to verify no private keys or tokens are in code or git history.
   - Verifies forbidden files are not tracked.
   - Shell syntax verification (`bash -n`).
2. **Linux Runner (`ubuntu-latest`)**:
   - Executes `tests/test-linux.sh`.
   - Tests binary downloads, config generation, and permission enforcement (`chmod 600`).
3. **Windows Runner (`windows-latest`)**:
   - Executes `tests/test-windows.ps1` via PowerShell (`pwsh`).
   - Tests Windows archive extraction and JSON validation.

---

## 🔑 Google Cloud Authentication

After configuring the MCP, authenticate your Google Cloud account:

```bash
# Login with your account
gcloud auth login your-email@your-domain.com

# Set default project
gcloud config set project your-gcp-project-id
```

---

## ⚖️ License

MIT License. See [LICENSE](LICENSE) for details.
