<#
.SYNOPSIS
    Cross-platform MCP Setup for Windows.
    Configures GitHub MCP Server and Google Cloud MCP Server.

.DESCRIPTION
    Downloads official github-mcp-server binary for Windows, checks and optionally installs
    Google Cloud and Node.js prerequisites, assists with browser-based authentication,
    and securely configures mcp_config.json.

.PARAMETER GitHubToken
    GitHub Personal Access Token (classic or fine-grained with repo/read:org permissions).
    Can also be provided via $env:GITHUB_TOKEN or $env:GITHUB_PERSONAL_ACCESS_TOKEN.

.PARAMETER ConfigPath
    Target mcp_config.json path. Defaults to "$env:USERPROFILE\.gemini\config\mcp_config.json".

.PARAMETER InstallDir
    Directory to place server binaries. Defaults to "$env:LOCALAPPDATA\Programs\mcp-servers".

.PARAMETER GCloudAccount
    Google Cloud account email to log in (e.g., user@domain.com).

.PARAMETER GCloudProject
    Google Cloud project ID to set as default.

.PARAMETER InstallDependencies
    Automatically download and install missing prerequisites (Node.js / Google Cloud SDK).

.PARAMETER LoginGCloud
    Prompt or launch Google Cloud authentication with browser link.

.PARAMETER SkipGCloud
    Skip Google Cloud MCP setup.

.PARAMETER SkipGitHub
    Skip GitHub MCP setup.

.PARAMETER Test
    Run in CI / Test mode with mock credentials.

.EXAMPLE
    .\setup-mcp.ps1
.EXAMPLE
    .\setup-mcp.ps1 -GitHubToken "ghp_xxxxxxxxxxxx" -LoginGCloud -GCloudAccount "user@domain.com"
#>

[CmdletBinding()]
param(
    [string]$GitHubToken = $env:GITHUB_PERSONAL_ACCESS_TOKEN,
    [string]$ConfigPath = "$env:USERPROFILE\.gemini\config\mcp_config.json",
    [string]$InstallDir = "$env:LOCALAPPDATA\Programs\mcp-servers",
    [string]$GCloudAccount,
    [string]$GCloudProject,
    [switch]$InstallDependencies,
    [switch]$LoginGCloud,
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

    # Check Node.js
    $nodeCmd = Get-Command node -ErrorAction SilentlyContinue
    if (-not $nodeCmd) {
        Write-Warning "    Node.js is not detected in PATH. Node >= 20 is required for @google-cloud/gcloud-mcp."
        $doInstallNode = $false
        if ($InstallDependencies) {
            $doInstallNode = $true
        } elseif (-not $Test -and [System.Environment]::UserInteractive) {
            $nodeAnswer = Read-Host "    Would you like to install Node.js via winget now? (Y/N)"
            if ($nodeAnswer -match "^[Yy]") {
                $doInstallNode = $true
            }
        }

        if ($doInstallNode) {
            $wingetCmd = Get-Command winget -ErrorAction SilentlyContinue
            if ($wingetCmd) {
                Write-Host "    Installing Node.js via winget..." -ForegroundColor Gray
                winget install --id OpenJS.NodeJS.LTS --accept-package-agreements --accept-source-agreements
            } else {
                Write-Warning "    winget is not available. Please install Node.js manually: https://nodejs.org/"
            }
        }
    } else {
        $nodeVer = & node -v
        Write-Host "    [OK] Node.js detected: $nodeVer" -ForegroundColor Green
    }

    # Check gcloud CLI
    $gcloudCmd = Get-Command gcloud -ErrorAction SilentlyContinue
    if (-not $gcloudCmd) {
        Write-Warning "    gcloud CLI is not detected in PATH."
        $doInstallGcloud = $false
        if ($InstallDependencies) {
            $doInstallGcloud = $true
        } elseif (-not $Test -and [System.Environment]::UserInteractive) {
            $gcloudAnswer = Read-Host "    Would you like to download and install Google Cloud SDK now? (Y/N)"
            if ($gcloudAnswer -match "^[Yy]") {
                $doInstallGcloud = $true
            }
        }

        if ($doInstallGcloud) {
            $wingetCmd = Get-Command winget -ErrorAction SilentlyContinue
            $installedViaWinget = $false
            if ($wingetCmd) {
                try {
                    Write-Host "    Installing Google Cloud SDK via winget..." -ForegroundColor Gray
                    winget install --id Google.CloudSDK --accept-package-agreements --accept-source-agreements
                    $installedViaWinget = $true
                } catch {
                    Write-Warning "    winget install failed, trying direct installer..."
                }
            }

            if (-not $installedViaWinget) {
                $gcloudInstallerUrl = "https://dl.google.com/dl/cloudsdk/channels/rapid/GoogleCloudSDKInstaller.exe"
                $gcloudInstallerPath = Join-Path ([System.IO.Path]::GetTempPath()) "GoogleCloudSDKInstaller.exe"
                Write-Host "    Downloading Google Cloud SDK installer..." -ForegroundColor Gray
                Invoke-WebRequest -Uri $gcloudInstallerUrl -OutFile $gcloudInstallerPath -UseBasicParsing
                Write-Host "    Launching installer. Complete the setup wizard..." -ForegroundColor Cyan
                Start-Process -FilePath $gcloudInstallerPath -Wait
            }

            # Refresh PATH from registry
            $regUserPath = [Environment]::GetEnvironmentVariable("Path", "User")
            $regMachinePath = [Environment]::GetEnvironmentVariable("Path", "Machine")
            $env:PATH = "$regUserPath;$regMachinePath;$env:PATH"
            $gcloudCmd = Get-Command gcloud -ErrorAction SilentlyContinue
        } else {
            Write-Host "    You can install it manually from: https://cloud.google.com/sdk/docs/install" -ForegroundColor Gray
        }
    }

    # If gcloud is available, check status and handle browser authentication
    if ($gcloudCmd) {
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
            $activeAccount = $null
            Write-Host "    [Notice] No active account logged in." -ForegroundColor Cyan
        }

        # Interactive authentication with browser link option
        if (-not $Test) {
            $doLogin = $false
            if ($LoginGCloud -or -not $activeAccount) {
                if ($LoginGCloud) {
                    $doLogin = $true
                } elseif ([System.Environment]::UserInteractive) {
                    $loginAnswer = Read-Host "    Would you like to authenticate Google Cloud now? (Y/N)"
                    if ($loginAnswer -match "^[Yy]") {
                        $doLogin = $true
                    }
                }
            }

            if ($doLogin) {
                Write-Host ""
                Write-Host "----------------------------------------------------------" -ForegroundColor Cyan
                Write-Host " Google Cloud Authentication " -ForegroundColor Cyan
                Write-Host "----------------------------------------------------------" -ForegroundColor Cyan
                Write-Host " Select login mode:"
                Write-Host "   [1] Show URL link to copy-paste into your browser (Recommended for remote/headless)"
                Write-Host "   [2] Launch web browser automatically"
                $authChoice = Read-Host " Choice [1/2] (default: 1)"
                if ([string]::IsNullOrWhiteSpace($authChoice)) {
                    $authChoice = "1"
                }

                $authArgs = @("auth", "login")
                if ($GCloudAccount) {
                    $authArgs += $GCloudAccount
                }

                if ($authChoice -eq "1") {
                    Write-Host "    Generating browser login link..." -ForegroundColor Cyan
                    $authArgs += "--no-launch-browser"
                } else {
                    Write-Host "    Opening browser for authorization..." -ForegroundColor Cyan
                }

                try {
                    & gcloud @authArgs
                } catch {
                    Write-Warning "    Authentication process encountered an issue: $($_.Exception.Message)"
                }

                # Verify new active account
                try {
                    $activeAccount = (& gcloud config get-value account 2>$null)
                    if ($activeAccount -and $activeAccount -ne "(unset)") {
                        Write-Host "    [OK] Successfully logged in as: $activeAccount" -ForegroundColor Green
                    }
                } catch {
                    # Ignore
                }
            }

            # Configure default project if supplied
            if ($GCloudProject) {
                Write-Host "    Setting default Google Cloud project to: $GCloudProject" -ForegroundColor Gray
                try {
                    & gcloud config set project $GCloudProject
                } catch {
                    Write-Warning "    Failed to set project $GCloudProject"
                }
            }
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
