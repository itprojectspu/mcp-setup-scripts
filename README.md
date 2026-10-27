# MCP Setup Scripts (Windows & Linux)

Cross-platform configuration scripts for Model Context Protocol (MCP) servers:
- **GitHub MCP Server** (`github-mcp-server` official Go binary)
- **Google Cloud MCP Server** (`@google-cloud/gcloud-mcp`)

Includes automated dependency installation, browser-based authentication with clickable/copyable URLs, and GitHub Actions CI.

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

## 📋 Prerequisites & Automatic Installation

The scripts can automatically detect and offer to install missing tools:
- **Node.js** (`>= 20.x`)
- **Google Cloud SDK** (`gcloud`)
- **GitHub MCP Server** (downloaded from official GitHub releases)

---

## 🚀 Quick Start

### Windows (PowerShell)

1. Open PowerShell and navigate to the project directory:
   ```powershell
   cd \ruta\a\mcp-setup-scripts
   ```

2. Run interactively:
   ```powershell
   .\scripts\setup-mcp.ps1
   ```

3. **Con instalación automática de dependencias y autenticación de Google Cloud:**
   ```powershell
   .\scripts\setup-mcp.ps1 `
       -InstallDependencies `
       -LoginGCloud `
       -GCloudAccount "tu-usuario@tudominio.com" `
       -GCloudProject "tu-proyecto-id"
   ```

#### Opciones de Autenticación de Google Cloud en Windows
El script te preguntará cómo deseas autenticarte:
- **Opción 1 (Recomendada):** Muestra un **enlace URL** para copiar y pegar en tu navegador. Ideal si trabajas por SSH, máquina virtual o terminal remota. Al iniciar sesión, copias el código de autorización generado y lo pegas en la consola.
- **Opción 2:** Abre el navegador automáticamente para completar el inicio de sesión.

---

### Linux & macOS (Bash)

1. Dar permisos de ejecución:
   ```bash
   chmod +x scripts/setup-mcp.sh
   ```

2. Ejecutar de forma interactiva:
   ```bash
   ./scripts/setup-mcp.sh
   ```

3. **Con instalación de dependencias y login:**
   ```bash
   ./scripts/setup-mcp.sh \
       --install-deps \
       --login-gcloud \
       --gcloud-account "tu-usuario@tudominio.com" \
       --gcloud-project "tu-proyecto-id"
   ```

---

## 📄 Formato del Archivo Generado

Los scripts generan o combinan de forma segura el archivo `mcp_config.json`:

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

El repositorio incluye un workflow de GitHub Actions (`.github/workflows/ci.yml`):
- **Windows:** Valida compatibilidad nativa con **Windows PowerShell 5.1** y **PowerShell Core 7**.
- **Linux:** Valida instalación, permisos `chmod 600` y esquemas JSON en Ubuntu.
- **Seguridad:** Analiza que no existan credenciales ni archivos `.env` en el repositorio.

---

## ⚖️ License

MIT License. See [LICENSE](LICENSE) for details.
