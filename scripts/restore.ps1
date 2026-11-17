<#
.SYNOPSIS
    Plane Enterprise Restore Utility (PowerShell)
.DESCRIPTION
    Restores persistent volumes and databases from a previous backup archive.
.PARAMETER BackupDir
    Path to the backup directory containing .tar.gz archives.
#>

[CmdletBinding()]
param (
    [Parameter(Mandatory=$true)]
    [string]$BackupDir
)

$ErrorActionPreference = "Stop"
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$ProjectRoot = Split-Path -Parent $ScriptDir
Set-Location $ProjectRoot

if (-not (Test-Path $BackupDir)) {
    Write-Error "Backup directory does not exist: $BackupDir"
    exit 1
}

Write-Host "==================================================" -ForegroundColor Cyan
Write-Host "       Plane Self-Hosted Restore Utility          " -ForegroundColor Cyan
Write-Host "==================================================" -ForegroundColor Cyan
Write-Host "Source Backup: $BackupDir" -ForegroundColor Yellow

# 1. Safety Check: Verify plane stack is stopped
$RunningContainers = docker ps --filter "name=plane-" -q
if ($RunningContainers) {
    Write-Host "`n[!] Active Plane containers detected." -ForegroundColor Yellow
    Write-Host "Stopping Plane stack safely before restore..." -ForegroundColor Gray
    docker compose down
}

# 2. Volume Restores
$VolumesToRestore = @("plane_pgdata", "plane_uploads", "plane_redisdata", "plane_rabbitmq_data")

foreach ($Vol in $VolumesToRestore) {
    $ArchiveFile = Join-Path $BackupDir "$Vol.tar.gz"
    if (Test-Path $ArchiveFile) {
        Write-Host "`nRestoring volume: $Vol from $ArchiveFile..." -ForegroundColor Green
        
        # Ensure volume exists
        docker volume create $Vol | Out-Null

        # Clear existing volume and extract archive
        docker run --rm `
            -v "${Vol}:/target_vol" `
            -v "${BackupDir}:/backup_src:ro" `
            alpine sh -c "rm -rf /target_vol/* /target_vol/..?* /target_vol/.[!.]* && tar -xzf /backup_src/$Vol.tar.gz -C /target_vol"

        if ($LASTEXITCODE -eq 0) {
            Write-Host "  -> [OK] Volume $Vol restored successfully." -ForegroundColor DarkGreen
        } else {
            Write-Warning "  -> [FAIL] Failed to restore $Vol"
        }
    } else {
        Write-Host "  -> Archive $Vol.tar.gz not found in backup directory; skipping." -ForegroundColor Gray
    }
}

# 3. Environment File
$EnvBackup = Join-Path $BackupDir "plane.env.backup"
if (Test-Path $EnvBackup) {
    if (-not (Test-Path ".env")) {
        Copy-Item $EnvBackup ".env"
        Write-Host "`nRestored .env from backup." -ForegroundColor Green
    } else {
        Write-Host "`nExisting .env found. Keeping current .env (backup copy is available at $EnvBackup)." -ForegroundColor Yellow
    }
}

Write-Host "`n==================================================" -ForegroundColor Cyan
Write-Host "Restore operation complete!" -ForegroundColor Green
Write-Host "You can now start Plane with: docker compose up -d" -ForegroundColor White
Write-Host "==================================================" -ForegroundColor Cyan
