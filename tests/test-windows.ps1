# ==============================================================================
# test-windows.ps1 - Automated test suite for Windows MCP setup script
# ==============================================================================

$ErrorActionPreference = "Stop"

Write-Host ">>> Running Windows MCP setup test suite..." -ForegroundColor Cyan

$tempBase = Join-Path ([System.IO.Path]::GetTempPath()) "mcp-test-$([System.Guid]::NewGuid().ToString('N'))"
$testConfig = Join-Path $tempBase "mcp_config.json"
$testBin = Join-Path $tempBase "bin"

try {
    # Execute setup script with -Test flag
    & "$PSScriptRoot\..\scripts\setup-mcp.ps1" `
        -Test `
        -ConfigPath $testConfig `
        -InstallDir $testBin

    # 1. Verify config file was created
    if (-not (Test-Path $testConfig)) {
        throw "FAIL: Expected configuration file was not created at $testConfig"
    }

    # 2. Parse and validate JSON content
    $content = Get-Content -Path $testConfig -Raw -Encoding UTF8
    $json = ConvertFrom-Json $content

    if (-not $json.mcpServers) {
        throw "FAIL: Missing 'mcpServers' object in generated JSON"
    }

    if (-not $json.mcpServers.github) {
        throw "FAIL: Missing 'github' server in generated configuration"
    }

    if (-not $json.mcpServers.gcloud) {
        throw "FAIL: Missing 'gcloud' server in generated configuration"
    }

    if ($json.mcpServers.github.command -ne "github-mcp-server") {
        throw "FAIL: Unexpected command for github: $($json.mcpServers.github.command)"
    }

    if (-not $json.mcpServers.github.env.GITHUB_PERSONAL_ACCESS_TOKEN) {
        throw "FAIL: GITHUB_PERSONAL_ACCESS_TOKEN not found in github server environment"
    }

    if ($json.mcpServers.gcloud.command -notlike "*npx*") {
        throw "FAIL: Unexpected command for gcloud: $($json.mcpServers.gcloud.command)"
    }

    Write-Host ">>> Windows test passed: JSON schema and values are valid!" -ForegroundColor Green
    Write-Host ">>> All Windows tests completed successfully!" -ForegroundColor Green
}
finally {
    if (Test-Path $tempBase) {
        Remove-Item -Path $tempBase -Recurse -Force -ErrorAction SilentlyContinue
    }
}
