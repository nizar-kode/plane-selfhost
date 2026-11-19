<#
.SYNOPSIS
    Plane Self-Hosted - Root Quick Launcher for Windows / Windows Server
.DESCRIPTION
    Launches the automated Windows deployment pipeline.
    Usage:
        powershell -ExecutionPolicy Bypass -File .\deploy.ps1
        powershell -ExecutionPolicy Bypass -File .\deploy.ps1 -ServerIPOrDomain "192.168.1.100"
#>

[CmdletBinding()]
param (
    [string]$ServerIPOrDomain = "",
    [string]$InstallDir = "C:\plane-selfhost",
    [string]$RepoUrl = "https://github.com/nizar-kode/plane-selfhost.git"
)

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path

if (Test-Path (Join-Path $ScriptDir "scripts\deploy-server.ps1")) {
    & (Join-Path $ScriptDir "scripts\deploy-server.ps1") -ServerIPOrDomain $ServerIPOrDomain -InstallDir $InstallDir -RepoUrl $RepoUrl
} else {
    Write-Host "Bootstrapping Plane deployment..." -ForegroundColor Cyan
    if (-not (Test-Path $InstallDir)) {
        New-Item -ItemType Directory -Force -Path $InstallDir | Out-Null
    }
    Set-Location $InstallDir
    if (-not (Test-Path "$InstallDir\.git")) {
        git clone $RepoUrl $InstallDir
    }
    & "$InstallDir\scripts\deploy-server.ps1" -ServerIPOrDomain $ServerIPOrDomain -InstallDir $InstallDir -RepoUrl $RepoUrl
}
