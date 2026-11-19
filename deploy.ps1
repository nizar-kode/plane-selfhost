<#
.SYNOPSIS
    Plane Self-Hosted - Root Quick Launcher for Windows & Windows Server
.DESCRIPTION
    Bootstraps and launches the automated Windows deployment pipeline.
    Compatible with direct local execution and remote one-liner execution:
        irm https://raw.githubusercontent.com/nizar-kode/plane-selfhost/main/deploy.ps1 | iex
#>

[CmdletBinding()]
param (
    [string]$ServerIPOrDomain = "",
    [string]$InstallDir = "C:\plane-selfhost",
    [string]$RepoUrl = "https://github.com/nizar-kode/plane-selfhost.git",
    [int]$HttpPort = 80
)

# Allow environment variable override for port (useful when piping to iex)
if ($env:HTTP_PORT -and $HttpPort -eq 80) {
    $HttpPort = [int]$env:HTTP_PORT
}
if ($env:PORT -and $HttpPort -eq 80) {
    $HttpPort = [int]$env:PORT
}

# Bypass execution policy for the current process
try { Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass -Force -ErrorAction SilentlyContinue } catch {}

# Safely resolve script directory when run from file vs piped to Invoke-Expression (iex)
$ScriptPath = $null
try {
    if ($MyInvocation -and $MyInvocation.MyCommand -and $MyInvocation.MyCommand.Path) {
        $ScriptPath = $MyInvocation.MyCommand.Path
    }
} catch {}

$ScriptDir = if (![string]::IsNullOrWhiteSpace($ScriptPath)) { Split-Path -Parent $ScriptPath } else { $null }

# Scenario 1: Running locally from within the cloned repository
if ($ScriptDir -and (Test-Path (Join-Path $ScriptDir "scripts\deploy-server.ps1"))) {
    $localEngine = Join-Path $ScriptDir "scripts\deploy-server.ps1"
    powershell.exe -ExecutionPolicy Bypass -File $localEngine -ServerIPOrDomain $ServerIPOrDomain -InstallDir $InstallDir -RepoUrl $RepoUrl -HttpPort $HttpPort
    return
}

# Scenario 2: Remote execution via `irm ... | iex`
Write-Host "================================================================================" -ForegroundColor Cyan
Write-Host "       Bootstrapping Plane Self-Hosted Deployment on Windows Server            " -ForegroundColor Cyan
Write-Host "================================================================================" -ForegroundColor Cyan
Write-Host "[INFO] Staging target directory: $InstallDir" -ForegroundColor Gray

if (-not (Test-Path $InstallDir)) {
    New-Item -ItemType Directory -Force -Path $InstallDir | Out-Null
}

$deployScript = Join-Path $InstallDir "scripts\deploy-server.ps1"

# Ensure repository files in target directory are present and up-to-date
if (Test-Path "$InstallDir\.git") {
    if (Get-Command git -ErrorAction SilentlyContinue) {
        Write-Host "[INFO] Updating repository files via Git..." -ForegroundColor Green
        try {
            Set-Location $InstallDir
            git pull origin main --quiet
        } catch {}
    }
} elseif (-not (Test-Path $deployScript)) {
    if (Get-Command git -ErrorAction SilentlyContinue) {
        Write-Host "[INFO] Git detected. Cloning repository..." -ForegroundColor Green
        git clone $RepoUrl $InstallDir
    } else {
        Write-Host "[INFO] Git is not yet installed. Downloading repository archive from GitHub..." -ForegroundColor Yellow
        $zipUrl = "https://github.com/nizar-kode/plane-selfhost/archive/refs/heads/main.zip"
        $zipFile = "$env:TEMP\plane-selfhost-main.zip"
        $extractDir = "$env:TEMP\plane-selfhost-extract"

        # Download ZIP
        [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
        Invoke-WebRequest -Uri $zipUrl -OutFile $zipFile -UseBasicParsing
        
        # Extract archive
        if (Test-Path $extractDir) { Remove-Item -Recurse -Force $extractDir }
        Expand-Archive -Path $zipFile -DestinationPath $extractDir -Force

        # Move contents to $InstallDir
        $sourceDir = Join-Path $extractDir "plane-selfhost-main"
        Copy-Item -Path "$sourceDir\*" -Destination $InstallDir -Recurse -Force

        # Clean temporary archive files
        Remove-Item -Force $zipFile -ErrorAction SilentlyContinue
        Remove-Item -Recurse -Force $extractDir -ErrorAction SilentlyContinue
        Write-Host "[OK] Repository files successfully staged to $InstallDir" -ForegroundColor Green
    }
}

# Launch the full automated Windows deployment engine
if (Test-Path $deployScript) {
    Set-Location $InstallDir
    powershell.exe -ExecutionPolicy Bypass -File $deployScript -ServerIPOrDomain $ServerIPOrDomain -InstallDir $InstallDir -RepoUrl $RepoUrl -HttpPort $HttpPort
} else {
    Write-Error "Deployment engine not found at $deployScript. Please verify repository files."
}
