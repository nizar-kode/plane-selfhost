<#
.SYNOPSIS
    Plane Enterprise Backup Utility (PowerShell)
.DESCRIPTION
    Creates a full snapshot backup of PostgreSQL database and MinIO storage volumes.
.PARAMETER OutputDir
    Destination folder for the backup (defaults to ./backups/<timestamp>)
#>

[CmdletBinding()]
param (
    [string]$OutputDir = ""
)

$ErrorActionPreference = "Stop"
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$ProjectRoot = Split-Path -Parent $ScriptDir
Set-Location $ProjectRoot

$Timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
if ([string]::IsNullOrWhiteSpace($OutputDir)) {
    $OutputDir = Join-Path $ProjectRoot "backups\backup_$Timestamp"
}

if (-not (Test-Path $OutputDir)) {
    New-Item -ItemType Directory -Force -Path $OutputDir | Out-Null
}

Write-Host "==================================================" -ForegroundColor Cyan
Write-Host "       Plane Self-Hosted Backup Utility           " -ForegroundColor Cyan
Write-Host "==================================================" -ForegroundColor Cyan
Write-Host "Destination: $OutputDir" -ForegroundColor Yellow

# 1. Database Hot Logical Backup (pg_dump)
Write-Host "`n[1/3] Exporting PostgreSQL database (pg_dump)..." -ForegroundColor Green
$SqlFile = Join-Path $OutputDir "plane_database.sql"

$DbRunning = docker ps --filter "name=plane-db" --filter "status=running" -q
if ($DbRunning) {
    try {
        # Fetch postgres user and db from environment or default to plane
        $PostgresUser = if ($env:POSTGRES_USER) { $env:POSTGRES_USER } else { "plane" }
        $PostgresDb = if ($env:POSTGRES_DB) { $env:POSTGRES_DB } else { "plane" }

        docker exec -t plane-db pg_dump -U $PostgresUser -d $PostgresDb -F p > $SqlFile
        Write-Host "  -> PostgreSQL dump created: $SqlFile" -ForegroundColor DarkGreen
    }
    catch {
        Write-Warning "  -> Hot pg_dump failed. Proceeding with raw volume backup."
    }
} else {
    Write-Host "  -> plane-db container is not running; skipping live SQL dump." -ForegroundColor Yellow
}

# 2. Volume Archiving (Postgres, MinIO Uploads, Redis, RabbitMQ)
Write-Host "`n[2/3] Archiving Docker volumes..." -ForegroundColor Green
$VolumesToBackup = @("plane_pgdata", "plane_uploads", "plane_redisdata", "plane_rabbitmq_data")

foreach ($Vol in $VolumesToBackup) {
    $ArchiveFile = "$Vol.tar.gz"
    Write-Host "  -> Archiving volume: $Vol to $ArchiveFile..." -ForegroundColor Gray

    # Spin up temporary lightweight alpine container to stream volume contents
    docker run --rm -v "${Vol}:/volume_data:ro" -v "${OutputDir}:/backup_target" alpine sh -c "tar -czf /backup_target/$ArchiveFile -C /volume_data ."
    if ($LASTEXITCODE -eq 0) {
        Write-Host "     [OK] $Vol archived successfully." -ForegroundColor DarkGreen
    } else {
        Write-Warning "     [FAIL] Could not archive volume $Vol."
    }
}

# 3. Environment & Configuration Backup
Write-Host "`n[3/3] Backing up configuration (.env)..." -ForegroundColor Green
if (Test-Path ".env") {
    Copy-Item ".env" (Join-Path $OutputDir "plane.env.backup")
    Write-Host "  -> Configuration saved as plane.env.backup" -ForegroundColor DarkGreen
}

Write-Host "`n==================================================" -ForegroundColor Cyan
Write-Host "Backup completed successfully!" -ForegroundColor Green
Write-Host "Archive location: $OutputDir" -ForegroundColor White
Write-Host "==================================================" -ForegroundColor Cyan
