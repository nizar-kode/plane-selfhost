# Remote Server Deployment Guide (Step-by-Step)

This guide provides complete, production-grade instructions for deploying **Plane** onto a fresh Linux remote server (VPS, dedicated server, or cloud instance on AWS, DigitalOcean, Hetzner, GCP, Linode, or Azure).

---

## 1. Server Prerequisites

### Hardware Recommendations
| Workload | vCPU | RAM | Storage | Suitable For |
| :--- | :--- | :--- | :--- | :--- |
| **Minimum / Testing** | 2 Cores | 4 GB | 25 GB SSD | Small team (up to 10 users), basic issue tracking |
| **Production Recommended** | 4 Cores | 8 GB | 50+ GB NVMe | Medium/Large team (10–100 users), active collaboration |
| **Enterprise / Heavy** | 8+ Cores | 16 GB | 100+ GB NVMe | 100+ active users, extensive file attachments, rich cycles |

> [!IMPORTANT]
> If your VPS has 4 GB RAM, ensure you configure a **4 GB Swap file** (explained in Step 2 below) to guarantee that initial database migrations do not trigger Linux OOM (Out Of Memory) killer.

### Supported Operating Systems
* **Ubuntu** 22.04 LTS / 24.04 LTS *(Recommended)*
* **Debian** 11 / 12
* **Rocky Linux / AlmaLinux** 9
* **CentOS Stream** 9 / RHEL 9

### Network & Firewall Ports
Ensure your cloud provider's firewall (AWS Security Group, Hetzner Firewall, GCP Firewall, etc.) allows inbound traffic on:
* **Port `22/tcp`**: SSH management access
* **Port `80/tcp`**: HTTP web traffic (and ACME HTTP-01 challenge for SSL)
* **Port `443/tcp`**: HTTPS encrypted web traffic

---

## 2. Automated One-Command Remote Deployment (Recommended)

SSH into your remote server:
```bash
ssh root@your-server-ip
```

Then run the automated deployment script directly:

```bash
curl -fsSL https://raw.githubusercontent.com/nizar-kode/plane-selfhost/main/deploy.sh | bash
```

### What the script performs automatically:
1. **Pre-flight verification**: Checks OS distribution, CPU architecture (amd64/arm64), and RAM.
2. **Prerequisites installation**: Installs `curl`, `git`, `python3`, `tar`, `gzip`, `openssl`, and `ca-certificates`.
3. **Docker Engine & Compose**: Detects existing Docker or automatically installs Docker CE and Docker Compose via official Docker repositories, enabling systemd service.
4. **Git Repository Retrieval**: Clones the deployment repository to `/opt/plane-selfhost`.
5. **Entropy & Secrets Generation**: Automatically generates 50-char Django secret keys, 64-char WebSocket tokens, and isolated database/MinIO credentials into `.env`.
6. **Domain & Ingress Setup**: Prompts for your domain or public IP, and configures automatic Let's Encrypt HTTPS.
7. **Firewall Rules**: Automatically configures local UFW or firewalld rules for ports 80 and 443 while preserving SSH.
8. **Container Orchestration**: Pulls official images, executes Django schema migrations via `plane-migrator`, and brings up the full stack.
9. **Health Verification**: Verifies container health checks and displays live endpoint URLs.

---

## 3. Step-by-Step Manual Deployment (Alternative)

If you prefer to execute each step manually for full visibility and control, follow this walkthrough:

### Step 3.1: Connect and Prepare the Server
```bash
ssh root@your-server-ip

# Update OS packages
apt-get update && apt-get upgrade -y   # On Ubuntu/Debian
# or: dnf upgrade -y                   # On Rocky/AlmaLinux
```

### Step 3.2: Configure 4 GB Swap (Recommended for 4 GB RAM servers)
```bash
# Check existing swap
free -h

# Create a 4GB swap file if none exists
fallocate -l 4G /swapfile
chmod 600 /swapfile
mkswap /swapfile
swapon /swapfile

# Make permanent across reboots
echo '/swapfile none swap sw 0 0' | tee -a /etc/fstab
```

### Step 3.3: Install Docker Engine and Docker Compose
```bash
# Download and run official Docker convenience script
curl -fsSL https://get.docker.com -o get-docker.sh
sh get-docker.sh
rm -f get-docker.sh

# Start and enable Docker
systemctl enable --now docker

# Verify installation
docker --version
docker compose version
```

### Step 3.4: Clone the Deployment Repository from GitHub
```bash
mkdir -p /opt
cd /opt

git clone https://github.com/nizar-kode/plane-selfhost.git
cd /opt/plane-selfhost

# Make scripts executable
chmod +x scripts/*.sh deploy.sh
```

### Step 3.5: Configure Environment & Generate Secrets
```bash
# Copy the template
cp .env.example .env

# Generate cryptographically secure secrets
python3 scripts/generate_secrets.py
```

### Step 3.6: Configure Domain and SSL in `.env`
Edit `.env` with your preferred editor:
```bash
nano .env
```

#### For HTTP with Server Public IP (Testing / Internal Network):
```env
APP_DOMAIN=203.0.113.10
WEB_URL=http://203.0.113.10
CORS_ALLOWED_ORIGINS=http://203.0.113.10
SITE_ADDRESS=:80
LISTEN_HTTP_PORT=80
```

#### For Production with Domain & Automatic HTTPS (Let's Encrypt):
```env
APP_DOMAIN=plane.yourcompany.com
WEB_URL=https://plane.yourcompany.com
CORS_ALLOWED_ORIGINS=https://plane.yourcompany.com
SITE_ADDRESS=plane.yourcompany.com
CERT_EMAIL=email admin@yourcompany.com
LISTEN_HTTP_PORT=80
LISTEN_HTTPS_PORT=443
```

> [!NOTE]
> Ensure your domain's DNS `A` record points to your server's public IP address before starting Plane with automatic HTTPS.

### Step 3.7: Open Firewall Ports
```bash
# For Ubuntu / Debian (UFW):
ufw allow 22/tcp
ufw allow 80/tcp
ufw allow 443/tcp
ufw enable

# For Rocky / CentOS / RHEL (Firewalld):
firewall-cmd --permanent --add-service=ssh
firewall-cmd --permanent --add-service=http
firewall-cmd --permanent --add-service=https
firewall-cmd --reload
```

### Step 3.8: Launch the Plane Stack
```bash
# Pull images
docker compose pull

# Run database migrations
docker compose run --rm migrator

# Start all services in the background
docker compose up -d
```

### Step 3.9: Verify Container Health
```bash
docker compose ps
```
All containers should display status `healthy` or `running`.

---

## 4. Post-Deployment: Initial Administrator Setup

1. Open your browser and navigate to:
   ```
   https://plane.yourcompany.com/god-mode/
   ```
   *(or `http://your-server-ip/god-mode/`)*

2. Complete the initial onboarding form:
   * **Instance Name**: e.g., "Acme Engineering Workspace"
   * **Admin Email**: Your administrative email address
   * **Password**: A strong administrative password

3. Once logged in to God Mode:
   * Navigate to **Settings -> Email (SMTP)** to configure outbound mail for invitations.
   * Configure Authentication providers (Google OAuth, GitHub, or Email/Password).

4. Access the primary application at `https://plane.yourcompany.com` to create your initial workspace and project boards.

---

## 5. Automated Daily Backups

To ensure your database and files are protected against hardware or server failures, set up an automated daily backup:

1. Open root crontab:
   ```bash
   crontab -e
   ```
2. Add a daily job at 02:00 AM:
   ```cron
   0 2 * * * /bin/bash /opt/plane-selfhost/scripts/backup.sh >> /var/log/plane-backup.log 2>&1
   ```
3. Backup archives will be created in `/opt/plane-selfhost/backups/backup_YYYYMMDD_HHMMSS/`.

---

## 6. Remote Server Maintenance Cheat Sheet

From `/opt/plane-selfhost`:

| Task | Command |
| :--- | :--- |
| **Check Health & Status** | `./scripts/manage.sh status` |
| **Stream Live Logs** | `./scripts/manage.sh logs` |
| **Restart Services** | `./scripts/manage.sh restart` |
| **Stop Stack** | `./scripts/manage.sh stop` |
| **Start Stack** | `./scripts/manage.sh start` |
| **Create Manual Backup** | `./scripts/manage.sh backup` |
| **Restore from Backup** | `./scripts/manage.sh restore /opt/plane-selfhost/backups/backup_xxxx` |
| **Upgrade to New Release** | `./scripts/manage.sh update` |
