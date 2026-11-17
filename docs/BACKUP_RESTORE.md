# Plane Self-Hosted Backup & Disaster Recovery Guide

This runbook details backup strategies, scheduled automation, volume persistence, and full disaster restoration for self-hosted Plane deployments.

---

## 1. Backup Philosophy & Strategy

A complete, recoverable Plane backup requires two primary components:
1. **Relational Database (`plane_pgdata` / PostgreSQL)**: Contains all workspaces, projects, issues, comments, cycles, metadata, and user accounts.
2. **Binary Object Storage (`plane_uploads` / MinIO)**: Contains all uploaded attachments, images, documents, and profile pictures.

Secondary components:
* **RabbitMQ & Redis Volumes (`plane_rabbitmq_data`, `plane_redisdata`)**: Contain transient task queues and cache data.
* **Environment Configuration (`.env`)**: Contains cryptographic keys (`SECRET_KEY`, `LIVE_SERVER_SECRET_KEY`) without which existing encrypted data or live tokens cannot be decoded.

---

## 2. Automated Backups with the Included CLI

### On Windows (PowerShell)
Execute the PowerShell backup script:
```powershell
.\scripts\manage.ps1 backup
```
Or run the dedicated backup utility directly:
```powershell
.\scripts\backup.ps1
```

### On Linux / macOS (Bash)
Execute the Bash backup script:
```bash
./scripts/manage.sh backup
```
Or directly:
```bash
bash scripts/backup.sh
```

### Output Structure
Backups are placed in timestamped subfolders under `backups/backup_YYYYMMDD_HHMMSS/`:
```
backups/backup_20261117_101500/
├── plane_database.sql       # Plain SQL dump from pg_dump
├── plane_pgdata.tar.gz      # Raw PostgreSQL data directory
├── plane_uploads.tar.gz     # MinIO S3 uploaded files & attachments
├── plane_redisdata.tar.gz   # Redis persistent state
├── plane_rabbitmq_data.tar.gz # RabbitMQ queues
└── plane.env.backup         # Configuration snapshot with encryption keys
```

---

## 3. Scheduled Automated Backups (Cron / Windows Task Scheduler)

### Setting up Cron on Linux
Add a daily cron job at 02:00 AM:
```bash
crontab -e
```
Add the following line:
```cron
0 2 * * * /bin/bash /opt/plane-selfhost/scripts/backup.sh /var/backups/plane/$(date +\%Y\%m\%d) >> /var/log/plane-backup.log 2>&1
```

### Setting up Windows Task Scheduler
Open PowerShell as Administrator and create a daily scheduled task:
```powershell
$Action = New-ScheduledTaskAction -Execute "powershell.exe" -Argument "-ExecutionPolicy Bypass -File E:\code\antigravity\plane-selfhost\scripts\backup.ps1"
$Trigger = New-ScheduledTaskTrigger -Daily -At 2:00AM
Register-ScheduledTask -Action $Action -Trigger $Trigger -TaskName "Plane_Daily_Backup" -Description "Daily snapshot of Plane PostgreSQL and MinIO data."
```

---

## 4. Disaster Recovery & Restoration Procedures

> [!WARNING]
> **Always stop the Plane stack before restoring raw volumes** to prevent database corruption.

### 4.1 Automated Volume Restoration

#### On Windows:
```powershell
.\scripts\manage.ps1 restore "backups\backup_20261117_101500"
```
Or directly:
```powershell
.\scripts\restore.ps1 -BackupDir "backups\backup_20261117_101500"
```

#### On Linux:
```bash
./scripts/manage.sh restore /path/to/backups/backup_20261117_101500
```
Or directly:
```bash
bash scripts/restore.sh /path/to/backups/backup_20261117_101500
```

### 4.2 Manual SQL Restoration (Alternative)

If you only need to restore the PostgreSQL logical database from `plane_database.sql`:

1. Start only the PostgreSQL database container:
   ```bash
   docker compose up -d plane-db
   ```
2. Wait until PostgreSQL is healthy:
   ```bash
   docker compose ps plane-db
   ```
3. Drop and recreate the database, or pipe the SQL script into `psql`:
   ```bash
   docker exec -i plane-db psql -U plane -d plane < plane_database.sql
   ```
4. Start the rest of the Plane stack:
   ```bash
   docker compose up -d
   ```

---

## 5. Restoration Verification Checklist

After restoring:
1. Verify all containers are running and healthy:
   ```bash
   docker compose ps
   ```
2. Verify web application login: Navigate to your configured `WEB_URL` and log in with your administrative account.
3. Verify uploaded assets: Open an existing issue and confirm image attachments, avatars, and file links render correctly.
4. Verify background worker processing: Create a test issue or invite a member and check `docker compose logs worker`.
