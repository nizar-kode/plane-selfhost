<#
.SYNOPSIS
    Plane Enterprise Deployment & Operations Management CLI (PowerShell)
.DESCRIPTION
    Comprehensive management tool for Plane Self-Hosted stack on Windows.
.EXAMPLE
    .\scripts\manage.ps1 start
    .\scripts\manage.ps1 status
    .\scripts\manage.ps1 backup
#>

[CmdletBinding()]
param (
    [Parameter(Position=0)]
    [ValidateSet("start", "stop", "restart", "status", "logs", "backup", "restore", "update", "init-secrets", "menu", "")]
    [string]$Command = "menu",

    [Parameter(Position=1)]
    [string]$Arg1 = ""
)

$ErrorActionPreference = "Stop"
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$ProjectRoot = Split-Path -Parent $ScriptDir
Set-Location $ProjectRoot

function Show-Header {
    Write-Host @"
==============================================================
   ____  _                  ____       _  __      _   _           _ 
  |  _ \| | __ _ _ __   ___/ ___|  ___| |/ _|    | | | | ___  ___| |_ 
  | |_) | |/ _` | '_ \ / _ \___ \ / _ \ | |_|____| |_| |/ _ \/ __| __|
  |  __/| | (_| | | | |  __/___) |  __/ |  _|____|  _  | (_) \__ \ |_ 
  |_|   |_|\__,_|_| |_|\___|____/ \___|_|_|      |_| |_|\___/|___/\__|
==============================================================
  Self-Hosted Project Management Platform | Plane v1.5.0
==============================================================
"@ -ForegroundColor Cyan
}

function Ensure-Env {
    if (-not (Test-Path ".env")) {
        Write-Host "[!] No .env file found. Generating secure environment..." -ForegroundColor Yellow
        python scripts/generate_secrets.py
    }
}

function Start-Plane {
    Ensure-Env
    Write-Host "`n[+] Starting Plane services..." -ForegroundColor Green
    docker compose up -d
    Write-Host "`n[OK] Plane is launching in background." -ForegroundColor Green
    Write-Host "Services will take ~30-60 seconds to finish migrations and pass health checks." -ForegroundColor Gray
    Show-Status
}

function Stop-Plane {
    Write-Host "`n[-] Stopping Plane services..." -ForegroundColor Yellow
    docker compose down
    Write-Host "[OK] All Plane services stopped." -ForegroundColor Green
}

function Restart-Plane {
    Write-Host "`n[*] Restarting Plane services..." -ForegroundColor Yellow
    docker compose restart
    Write-Host "[OK] Services restarted." -ForegroundColor Green
}

function Show-Status {
    Write-Host "`n--------------------------------------------------------------" -ForegroundColor Cyan
    Write-Host "                 Plane Stack Health & Status                  " -ForegroundColor Cyan
    Write-Host "--------------------------------------------------------------" -ForegroundColor Cyan
    docker compose ps

    # Determine configured URL
    $WebUrl = "http://localhost"
    if (Test-Path ".env") {
        $Match = Select-String -Path ".env" -Pattern "^WEB_URL=(.*)$"
        if ($Match) {
            $WebUrl = $Match.Matches[0].Groups[1].Value.Trim()
        }
    }

    Write-Host "`n[Access Endpoints]" -ForegroundColor White
    Write-Host "  -> Main Web App:     $WebUrl" -ForegroundColor Green
    Write-Host "  -> Admin Console:    $WebUrl/god-mode/" -ForegroundColor Green
    Write-Host "  -> Documentation:    https://docs.plane.so" -ForegroundColor DarkGray
    Write-Host "--------------------------------------------------------------" -ForegroundColor Cyan
}

function Show-Logs {
    param([string]$Service)
    if ([string]::IsNullOrWhiteSpace($Service)) {
        Write-Host "`nStreaming logs for all Plane services (Ctrl+C to exit)..." -ForegroundColor Green
        docker compose logs -f --tail=100
    } else {
        Write-Host "`nStreaming logs for $Service (Ctrl+C to exit)..." -ForegroundColor Green
        docker compose logs -f --tail=100 $Service
    }
}

function Invoke-Backup {
    & "$ScriptDir\backup.ps1"
}

function Invoke-Restore {
    param([string]$Path)
    if ([string]::IsNullOrWhiteSpace($Path)) {
        $Backups = Get-ChildItem -Path "backups" -Directory -ErrorAction SilentlyContinue | Sort-Object CreationTime -Descending
        if ($Backups.Count -eq 0) {
            Write-Error "No backups found in backups/ directory."
            return
        }
        Write-Host "`nAvailable backups:" -ForegroundColor Yellow
        for ($i = 0; $i -lt $Backups.Count; $i++) {
            Write-Host "  [$i] $($Backups[$i].Name)" -ForegroundColor White
        }
        $Selection = Read-Host "`nEnter backup number to restore (or type path)"
        if ($Selection -match "^\d+$" -and [int]$Selection -lt $Backups.Count) {
            $Path = $Backups[[int]$Selection].FullName
        } else {
            $Path = $Selection
        }
    }
    & "$ScriptDir\restore.ps1" -BackupDir $Path
}

function Update-Plane {
    Write-Host "`n[1/4] Creating safety backup before upgrade..." -ForegroundColor Yellow
    Invoke-Backup
    
    Write-Host "`n[2/4] Pulling updated container images..." -ForegroundColor Green
    docker compose pull

    Write-Host "`n[3/4] Running schema migrations..." -ForegroundColor Green
    docker compose run --rm migrator

    Write-Host "`n[4/4] Restarting updated Plane stack..." -ForegroundColor Green
    docker compose up -d

    Write-Host "`n[OK] Upgrade process completed successfully!" -ForegroundColor Green
    Show-Status
}

function Show-Menu {
    Show-Header
    Write-Host @"
Select an action:
  1) Start Plane (docker compose up -d)
  2) Stop Plane (docker compose down)
  3) Restart Services
  4) View Health & Status
  5) View Real-Time Logs
  6) Backup Database & Files
  7) Restore From Backup
  8) Upgrade Plane & Run Migrations
  9) Re-generate Secrets (.env)
  0) Exit
"@ -ForegroundColor White

    $Choice = Read-Host "`nEnter choice [1-0]"
    switch ($Choice) {
        "1" { Start-Plane }
        "2" { Stop-Plane }
        "3" { Restart-Plane }
        "4" { Show-Status }
        "5" { 
            $Svc = Read-Host "Enter service name (leave blank for all services)"
            Show-Logs -Service $Svc
        }
        "6" { Invoke-Backup }
        "7" { Invoke-Restore }
        "8" { Update-Plane }
        "9" { python "$ScriptDir\generate_secrets.py" --force }
        "0" { exit 0 }
        default { Write-Warning "Invalid choice." }
    }
}

# Main Dispatcher
switch ($Command.ToLower()) {
    "start"        { Show-Header; Start-Plane }
    "stop"         { Show-Header; Stop-Plane }
    "restart"      { Show-Header; Restart-Plane }
    "status"       { Show-Header; Show-Status }
    "logs"         { Show-Header; Show-Logs -Service $Arg1 }
    "backup"       { Show-Header; Invoke-Backup }
    "restore"      { Show-Header; Invoke-Restore -Path $Arg1 }
    "update"       { Show-Header; Update-Plane }
    "init-secrets" { python "$ScriptDir\generate_secrets.py" }
    "menu"         { Show-Menu }
    default        { Show-Menu }
}
