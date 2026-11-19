# Deploying Plane on Windows & Windows Server (Step-by-Step)

This guide provides end-to-end instructions for deploying **Plane** on a **Windows Server** (Windows Server 2022 / 2025) or **Windows 10 / 11** host without any pre-existing Docker installation.

---

## 1. System Requirements

* **Operating System**: Windows Server 2022, Windows Server 2025, or Windows 10/11 (Pro, Enterprise, or Datacenter editions).
* **Hardware**:
  * **Minimum**: 2 vCPUs, 4 GB RAM, 30 GB SSD.
  * **Recommended (Production)**: 4+ vCPUs, 8 GB RAM, 60+ GB NVMe storage.
* **Virtualization**: Nested virtualization enabled if running Windows inside a cloud VM (AWS EC2 `t3/c5`, Azure `Dv4`, GCP, or Hyper-V).

---

## 2. Automated One-Click Deployment (Recommended)

Log in to your Windows Server via RDP (Remote Desktop) or PowerShell SSH.

Open **PowerShell as Administrator**:

```powershell
# 1. Download and run the automated deployment launcher:
irm https://raw.githubusercontent.com/nizar-kode/plane-selfhost/main/deploy.ps1 | iex
```

Or if you have Git installed and cloned the repository:

```powershell
git clone https://github.com/nizar-kode/plane-selfhost.git C:\plane-selfhost
cd C:\plane-selfhost
powershell -ExecutionPolicy Bypass -File .\deploy.ps1
```

### What the Script Performs Automatically:
1. **Verifies Administrator privileges** & system memory.
2. **Installs Git for Windows and Python 3** silently if missing.
3. **Enables WSL 2 & Virtual Machine Platform** features.
4. **Installs Docker Desktop** silently with accepted licenses and starts the engine.
5. **Stages the repository** to `C:\plane-selfhost`.
6. **Prompts for your Server IP or Domain** (defaults to auto-detected local network IP).
7. **Generates cryptographic keys** (`SECRET_KEY`, database passwords, WebSocket secrets) and configures `.env`.
8. **Configures Windows Defender Firewall** to allow inbound TCP traffic on ports **80** and **443**.
9. **Executes schema migrations** (`migrator` service) and launches the complete Plane container stack (`docker compose up -d`).
10. **Runs healthcheck verification** and provides active URLs.

---

## 3. Manual Step-by-Step Walkthrough

If you prefer executing each step manually for full administrative control:

### Step 3.1: Enable Windows Subsystem for Linux (WSL 2)
Plane uses Linux containers (PostgreSQL, Valkey, RabbitMQ, Python/Django). On Windows, these run via the high-performance WSL 2 backend.

Open **PowerShell as Administrator**:
```powershell
# Enable WSL & Virtual Machine Platform
dism.exe /online /enable-feature /featurename:Microsoft-Windows-Subsystem-Linux /all /norestart
dism.exe /online /enable-feature /featurename:VirtualMachinePlatform /all /norestart

# Update WSL to the latest Linux kernel
wsl --update
```

*(If this is a brand new server that has never had WSL enabled, restart the server if prompted)*.

---

### Step 3.2: Install Git & Python
```powershell
# Using winget (if available):
winget install --id Git.Git -e --silent
winget install --id Python.Python.3.11 -e --silent

# Refresh environment variables:
$env:Path = [System.Environment]::GetEnvironmentVariable("Path","Machine") + ";" + [System.Environment]::GetEnvironmentVariable("Path","User")
```

---

### Step 3.3: Install Docker Desktop on Windows
1. Download the official Docker installer:
   ```powershell
   $dockerInstaller = "$env:TEMP\DockerDesktopInstaller.exe"
   Invoke-WebRequest -Uri "https://desktop.docker.com/win/main/amd64/Docker%20Desktop%20Installer.exe" -OutFile $dockerInstaller
   ```
2. Run the silent installer:
   ```powershell
   Start-Process -FilePath $dockerInstaller -ArgumentList "install --quiet --accept-licenses" -Wait
   Remove-Item -Force $dockerInstaller
   ```
3. Launch Docker Desktop:
   ```powershell
   Start-Process "C:\Program Files\Docker\Docker\Docker Desktop.exe"
   ```
4. Verify Docker is running:
   ```powershell
   docker --version
   docker compose version
   docker info
   ```

---

### Step 3.4: Clone the Deployment Repository from GitHub
```powershell
New-Item -ItemType Directory -Force -Path C:\plane-selfhost | Out-Null
cd C:\plane-selfhost

git clone https://github.com/nizar-kode/plane-selfhost.git .
```

---

### Step 3.5: Configure Environment & Generate High-Entropy Secrets
1. Copy `.env.example` to `.env`:
   ```powershell
   Copy-Item .env.example .env
   ```
2. Run the automated secret generator:
   ```powershell
   python scripts\generate_secrets.py
   ```
3. Edit `.env` to bind your Windows server IP address:
   ```powershell
   notepad .env
   ```
   Update the following lines (replace `192.168.1.100` with your Windows server IP):
   ```env
   APP_DOMAIN=192.168.1.100
   WEB_URL=http://192.168.1.100
   CORS_ALLOWED_ORIGINS=http://192.168.1.100
   SITE_ADDRESS=:80
   LISTEN_HTTP_PORT=80
   LISTEN_HTTPS_PORT=443
   ```

---

### Step 3.6: Open Inbound Firewall Ports (80 & 443)
Allow inbound web traffic through Windows Defender Firewall:
```powershell
New-NetFirewallRule -DisplayName "Plane Web HTTP" -Direction Inbound -Protocol TCP -LocalPort 80 -Action Allow
New-NetFirewallRule -DisplayName "Plane Web HTTPS" -Direction Inbound -Protocol TCP -LocalPort 443 -Action Allow
```

> [!TIP]
> **Check for Port 80 Conflicts (IIS / World Wide Web Publishing Service):**  
> If Windows Server has IIS installed, it may already be listening on port 80.  
> To test: `Test-NetConnection -ComputerName 127.0.0.1 -Port 80`  
> If occupied by IIS and you don't need IIS, stop it:
> ```powershell
> Stop-Service W3SVC -Force
> Set-Service W3SVC -StartupType Disabled
> ```
> Or, change Plane's host port in `.env` to `LISTEN_HTTP_PORT=8080`, and access Plane at `http://<SERVER_IP>:8080`.

---

### Step 3.7: Launch Plane with Docker Compose
```powershell
cd C:\plane-selfhost

# Validate compose configuration:
docker compose config --quiet

# Pull images:
docker compose pull

# Start database services and wait for healthiness:
docker compose up -d plane-db plane-redis plane-mq plane-minio

# Run database schema migrations:
docker compose run --rm migrator

# Launch the entire Plane application stack:
docker compose up -d
```

---

### Step 3.8: Verify Running Stack
```powershell
docker compose ps
```
All containers (`plane-proxy`, `plane-web`, `plane-api`, `plane-admin`, `plane-db`, etc.) should display status `healthy` or `running`.

---

## 4. Initial Administrator Setup

From any computer on your network, open your browser and navigate to:

```
http://<YOUR_WINDOWS_SERVER_IP>/god-mode/
```

1. Enter your instance name and administrator account credentials.
2. Complete workspace setup.
3. Access the main board and issue tracker at `http://<YOUR_WINDOWS_SERVER_IP>/`.

---

## 5. Daily Operations & Maintenance on Windows Server

From `C:\plane-selfhost` in PowerShell:

| Task | PowerShell Command |
| :--- | :--- |
| **Check Status & Health** | `.\scripts\manage.ps1 status` |
| **View Live Container Logs** | `.\scripts\manage.ps1 logs` |
| **Create Snapshot Backup** | `.\scripts\manage.ps1 backup` |
| **Restore from Backup** | `.\scripts\manage.ps1 restore "C:\plane-selfhost\backups\backup_xxxx"` |
| **Upgrade Plane** | `.\scripts\manage.ps1 update` |
| **Restart Stack** | `.\scripts\manage.ps1 restart` |
| **Stop Stack** | `.\scripts\manage.ps1 stop` |
| **Start Stack** | `.\scripts\manage.ps1 start` |

---

## 6. Configuring Automated Daily Backup on Windows Server

To schedule an automatic daily backup using **Windows Task Scheduler**:

Open PowerShell as Administrator:

```powershell
$action = New-ScheduledTaskAction -Execute "powershell.exe" -Argument "-ExecutionPolicy Bypass -File C:\plane-selfhost\scripts\backup.ps1"
$trigger = New-ScheduledTaskTrigger -Daily -At 2:00AM
Register-ScheduledTask -Action $action -Trigger $trigger -TaskName "Plane_Daily_Backup" -Description "Daily snapshot of Plane PostgreSQL and MinIO uploads." -User "SYSTEM"
```
