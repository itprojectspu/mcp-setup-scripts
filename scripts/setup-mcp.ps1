<#
.SYNOPSIS
    Cross-platform MCP Setup for Windows.
    Configures GitHub MCP Server and Google Cloud MCP Server.

.DESCRIPTION
    Downloads official github-mcp-server binary for Windows, checks Google Cloud
    and Node.js prerequisites, and securely configures mcp_config.json.

.PARAMETER GitHubToken
    GitHub Personal Access Token (classic or fine-grained with repo/read:org permissions).
    Can also be provided via $env:GITHUB_TOKEN or $env:GITHUB_PERSONAL_ACCESS_TOKEN.

.PARAMETER ConfigPath
    Target mcp_config.json path. Defaults to "$env:USERPROFILE\.gemini\config\mcp_config.json".

.PARAMETER InstallDir
    Directory to place server binaries. Defaults to "$env:LOCALAPPDATA\Programs\mcp-servers".

.PARAMETER SkipGCloud
    Skip Google Cloud MCP setup.

.PARAMETER SkipGitHub
    Skip GitHub MCP setup.

.PARAMETER Test
    Run in CI / Test mode with mock credentials.

.EXAMPLE
    .\setup-mcp.ps1
.EXAMPLE
    .\setup-mcp.ps1 -GitHubToken "ghp_xxxxxxxxxxxx"
#>

[CmdletBinding()]
param(
    [string]$GitHubToken = $env:GITHUB_PERSONAL_ACCESS_TOKEN,
    [string]$ConfigPath = "$env:USERPROFILE\.gemini\config\mcp_config.json",
    [string]$InstallDir = "$env:LOCALAPPDATA\Programs\mcp-servers",
    [switch]$SkipGCloud,
    [switch]$SkipGitHub,
    [switch]$Test
)

$ErrorActionPreference = "Stop"

if (-not $GitHubToken -and $env:GITHUB_TOKEN) {
    $GitHubToken = $env:GITHUB_TOKEN
}

Write-Host "==========================================================" -ForegroundColor Cyan
Write-Host " Starting MCP Configuration (Windows) " -ForegroundColor Cyan
Write-Host "==========================================================" -ForegroundColor Cyan

# Create install & config directories
if (-not (Test-Path -Path $InstallDir)) {
    New-Item -ItemType Directory -Path $InstallDir -Force | Out-Null
}

$configDir = Split-Path -Parent $ConfigPath
if (-not (Test-Path -Path $configDir)) {
    New-Item -ItemType Directory -Path $configDir -Force | Out-Null
}

# ------------------------------------------------------------------------------
# 1. GitHub MCP Server Setup
# ------------------------------------------------------------------------------
if (-not $SkipGitHub) {
    Write-Host "[-] Configuring GitHub MCP Server..." -ForegroundColor Yellow

    if ([string]::IsNullOrWhiteSpace($GitHubToken)) {
        if ($Test) {
            Write-Host "    [CI/Test] Using dummy token for testing purposes." -ForegroundColor Magenta
            $GitHubToken = "ghp_mocktesttoken000000000000000000000000"
        } else {
            $securePrompt = Read-Host "    Please enter your GitHub Personal Access Token" -AsSecureString
            $BSTR = [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($securePrompt)
            $GitHubToken = [System.Runtime.InteropServices.Marshal]::PtrToStringAuto($BSTR)
            [System.Runtime.InteropServices.Marshal]::ZeroFreeBSTR($BSTR)
        }
    }

    if ([string]::IsNullOrWhiteSpace($GitHubToken)) {
        Write-Error "Error: A valid GitHub token is required."
        exit 1
    }

    # Detect architecture
    $arch = "x86_64"
    if ($env:PROCESSOR_ARCHITECTURE -eq "ARM64") {
        $arch = "arm64"
    }

    $binPath = Join-Path $InstallDir "github-mcp-server.exe"
    if (-not (Test-Path $binPath) -or $Test) {
        $downloadUrl = "https://github.com/github/github-mcp-server/releases/latest/download/github-mcp-server_Windows_${arch}.zip"
        Write-Host "    Downloading github-mcp-server binary from official releases..." -ForegroundColor Gray
        $guidStr = [System.Guid]::NewGuid().ToString("N")
        $zipTemp = Join-Path ([System.IO.Path]::GetTempPath()) "github-mcp-$guidStr.zip"
        $extractTemp = Join-Path ([System.IO.Path]::GetTempPath()) "github-mcp-extract-$guidStr"

        try {
            [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
            Invoke-WebRequest -Uri $downloadUrl -OutFile $zipTemp -UseBasicParsing
            Expand-Archive -Path $zipTemp -DestinationPath $extractTemp -Force

            $extractedExe = Get-ChildItem -Path $extractTemp -Filter "github-mcp-server.exe" -Recurse | Select-Object -First 1
            if ($extractedExe) {
                Move-Item -Path $extractedExe.FullName -Destination $binPath -Force
                Write-Host "    [OK] Installed github-mcp-server to $binPath" -ForegroundColor Green
            } else {
                Write-Warning "    Could not find github-mcp-server.exe in extracted archive."
            }
        }
        catch {
            Write-Warning "    [Notice] Failed to download or extract binary: $($_.Exception.Message)"
        }
        finally {
            if (Test-Path $zipTemp) { Remove-Item -Path $zipTemp -Force -ErrorAction SilentlyContinue }
            if (Test-Path $extractTemp) { Remove-Item -Path $extractTemp -Recurse -Force -ErrorAction SilentlyContinue }
        }
    } else {
        Write-Host "    [OK] github-mcp-server binary already exists at $binPath" -ForegroundColor Green
    }

    # Ensure $InstallDir is in PATH for current process
    if ($env:PATH -notlike "*$InstallDir*") {
        $env:PATH = "$InstallDir;$env:PATH"
    }
}

# ------------------------------------------------------------------------------
# 2. Google Cloud MCP Server Setup
# ------------------------------------------------------------------------------
if (-not $SkipGCloud) {
    Write-Host "[-] Checking Google Cloud MCP prerequisites..." -ForegroundColor Yellow

    $nodeCmd = Get-Command node -ErrorAction SilentlyContinue
    if (-not $nodeCmd) {
        Write-Warning "    Node.js is not detected in PATH. Node >= 20 is required for @google-cloud/gcloud-mcp."
    } else {
        $nodeVer = & node -v
        Write-Host "    [OK] Node.js detected: $nodeVer" -ForegroundColor Green
    }

    $gcloudCmd = Get-Command gcloud -ErrorAction SilentlyContinue
    if (-not $gcloudCmd) {
        Write-Warning "    gcloud CLI is not detected in PATH. Install Google Cloud SDK for Windows: https://cloud.google.com/sdk/docs/install"
    } else {
        $gcloudVer = (& gcloud --version 2>&1 | Select-Object -First 1)
        Write-Host "    [OK] Google Cloud SDK detected: $gcloudVer" -ForegroundColor Green

        $activeAccount = $null
        try {
            $activeAccount = (& gcloud config get-value account 2>$null)
        } catch {
            $activeAccount = $null
        }

        if ($activeAccount -and $activeAccount -ne "(unset)") {
            Write-Host "    [OK] Active gcloud account: $activeAccount" -ForegroundColor Green
        } else {
            Write-Host "    [Notice] No active account logged in. Run 'gcloud auth login' to authenticate." -ForegroundColor Cyan
        }
    }
}

# ------------------------------------------------------------------------------
# 3. Update mcp_config.json
# ------------------------------------------------------------------------------
Write-Host "[-] Updating MCP configuration at: $ConfigPath" -ForegroundColor Yellow

$configData = @{
    mcpServers = @{}
}

if (Test-Path -Path $ConfigPath) {
    try {
        $raw = Get-Content -Path $ConfigPath -Raw -Encoding UTF8
        $parsed = ConvertFrom-Json $raw
        if ($parsed.mcpServers) {
            foreach ($prop in $parsed.mcpServers.PSObject.Properties) {
                $configData.mcpServers[$prop.Name] = $prop.Value
            }
        }
    }
    catch {
        Write-Warning "    Existing configuration could not be parsed; creating fresh configuration."
    }
}

if (-not $SkipGitHub -and $GitHubToken) {
    $configData.mcpServers["github"] = @{
        command = "github-mcp-server"
        args    = @("stdio")
        env     = @{
            GITHUB_PERSONAL_ACCESS_TOKEN = $GitHubToken
        }
    }
}

if (-not $SkipGCloud) {
    $configData.mcpServers["gcloud"] = @{
        command = "npx.cmd"
        args    = @("-y", "@google-cloud/gcloud-mcp")
    }
}

$jsonOutput = $configData | ConvertTo-Json -Depth 10
[System.IO.File]::WriteAllText($ConfigPath, $jsonOutput + [System.Environment]::NewLine, [System.Text.Encoding]::UTF8)

Write-Host "    [OK] Configuration saved successfully." -ForegroundColor Green
Write-Host "==========================================================" -ForegroundColor Cyan
Write-Host " Setup complete! " -ForegroundColor Cyan
Write-Host "==========================================================" -ForegroundColor Cyan
