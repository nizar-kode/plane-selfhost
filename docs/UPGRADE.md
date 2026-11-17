# Plane Self-Hosted Upgrade & Migration Runbook

This guide describes how to update Plane safely to newer stable releases without data loss or downtime corruption.

---

## 1. Upgrade Principles

1. **Always Backup First**: Upgrades modify the relational database schema. A pre-upgrade backup is mandatory.
2. **Read Release Notes**: Check [Plane GitHub Releases](https://github.com/makeplane/plane/releases) for breaking changes or new required environment variables.
3. **Execute Migrations via `migrator`**: Schema migrations must finish successfully before bringing up the new API and worker containers.

---

## 2. One-Command Upgrade Workflow

The included management script automatically creates a backup, pulls new images, runs schema migrations, and restarts the stack.

### On Windows (PowerShell):
```powershell
.\scripts\manage.ps1 update
```

### On Linux / macOS (Bash):
```bash
./scripts/manage.sh update
```

---

## 3. Step-by-Step Manual Upgrade Procedure

If you prefer to perform each step manually:

### Step 1: Create a Snapshot Backup
```bash
# Windows
.\scripts\backup.ps1

# Linux
bash scripts/backup.sh
```

### Step 2: Update Application Version in `.env`
Open `.env` and update the release tag:
```env
APP_RELEASE=v1.5.0
```

### Step 3: Pull New Container Images
Pull the updated official Docker images:
```bash
docker compose pull
```

### Step 4: Stop Frontend and API Services
Stop traffic to prevent active writes during database migration:
```bash
docker compose stop api worker beat-worker web space admin live proxy
```

### Step 5: Run Database Migrations
Start the migrator container to apply pending schema changes:
```bash
docker compose run --rm migrator
```
Verify the output finishes with:
```
Operations to perform:
  Apply all migrations: ...
Running migrations:
  Applying ... OK
```

### Step 6: Start the Full Stack
Bring up all services with the new version:
```bash
docker compose up -d
```

### Step 7: Verify Service Health
Check that all containers are healthy:
```bash
docker compose ps
```

---

## 4. Rollback Procedure (If Upgrade Fails)

If a migration fails or an incompatible version breaks features:

1. Stop all services:
   ```bash
   docker compose down
   ```
2. Restore previous `.env` (reverting `APP_RELEASE` to the previous version).
3. Restore the pre-upgrade volume backup:
   ```bash
   # Windows
   .\scripts\restore.ps1 -BackupDir "backups\backup_<timestamp>"

   # Linux
   bash scripts/restore.sh "backups/backup_<timestamp>"
   ```
4. Restart the previous stack:
   ```bash
   docker compose up -d
   ```
