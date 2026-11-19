# Plane Self-Hosted

<p align="center">
  <strong>Production-ready Docker Compose deployment and lifecycle operations for Plane — the open-source project management platform and ClickUp / Jira alternative.</strong>
</p>

<p align="center">
  <a href="https://github.com/makeplane/plane/releases/tag/v1.5.0"><img src="https://img.shields.io/badge/Release-v1.5.0%20Stable-blue?style=flat-square" alt="Plane Release" /></a>
  <img src="https://img.shields.io/badge/Engine-Docker%20Compose-2496ED?style=flat-square&logo=docker" alt="Docker Compose" />
  <img src="https://img.shields.io/badge/Database-PostgreSQL%2015.7-336791?style=flat-square&logo=postgresql" alt="PostgreSQL" />
  <img src="https://img.shields.io/badge/Cache-Valkey%20%2F%20Redis%207.2-DC382D?style=flat-square&logo=redis" alt="Redis" />
  <img src="https://img.shields.io/badge/Broker-RabbitMQ%203.13-FF6600?style=flat-square&logo=rabbitmq" alt="RabbitMQ" />
  <img src="https://img.shields.io/badge/Storage-MinIO%20%2F%20S3-C72C48?style=flat-square" alt="MinIO S3" />
  <img src="https://img.shields.io/badge/Platform-Linux%20%7C%20Windows%20%7C%20macOS-success?style=flat-square" alt="Platform" />
  <img src="https://img.shields.io/badge/License-AGPL--3.0-orange?style=flat-square" alt="License" />
</p>

---

## Overview

**Plane** is a modern, extensible open-source project management and issue-tracking platform built for high-velocity software engineering and product teams. It delivers cycles, modules, custom views, real-time multi-player collaboration, public publishing spaces, customer portals, and enterprise administration.

This repository provides an enterprise-grade, reproducible **self-hosted deployment package** for running Plane on your own infrastructure using Docker Compose.

### Key Highlights
* **Official Stable Pinning**: Pinned to Plane Community Edition `v1.5.0` with verified multi-tier container dependencies.
* **Turnkey Secret Generation**: Automated generation of cryptographically secure Django keys, WebSocket secret tokens, and database credentials via `generate_secrets.py`.
* **Cross-Platform Operations CLI**: Unified management tooling for Windows (`manage.ps1`) and Linux / macOS (`manage.sh`).
* **Zero Data Loss Guarantee**: Named volume architecture with dedicated automated backup and disaster-recovery runbooks for PostgreSQL and MinIO S3 assets.
* **Production Reverse-Proxy Templates**: Tested reference configurations for Nginx, Caddy, Traefik, and Cloudflare Tunnel.
* **Graphify Knowledge Graph**: Fully indexed system architecture, dependencies, and relationship mapping.

---

## Architecture Overview

```
                                [ Users / Browsers ]
                                          │
                                          ▼ (HTTP/HTTPS :80 / :443)
                            ┌───────────────────────────┐
                            │    plane-proxy (Caddy)    │
                            └─────────────┬─────────────┘
                                          │
         ┌────────────────┬───────────────┼───────────────┬────────────────┐
         │                │               │               │                │
         ▼                ▼               ▼               ▼                ▼
  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐
  │  plane-web  │  │ plane-space │  │ plane-admin │  │ plane-live  │  │  plane-api  │
  │  (Next.js)  │  │ (Publishing)│  │ (God Mode)  │  │(WebSockets) │  │(Django REST)│
  └─────────────┘  └─────────────┘  └─────────────┘  └──────┬──────┘  └──────┬──────┘
                                                            │                │
                                ┌───────────────────────────┴────────────────┴┐
                                │                                             │
                                ▼                                             ▼
                      ┌──────────────────┐                          ┌──────────────────┐
                      │   plane-redis    │                          │     plane-mq     │
                      │ (Valkey Cache &  │                          │(RabbitMQ Broker) │
                      │    Pub/Sub)      │                          └────────┬─────────┘
                      └────────┬─────────┘                                   │
                               │                                             │
                               │          ┌──────────────────────────────────┤
                               ▼          ▼                                  ▼
                        ┌──────────────────┐                       ┌──────────────────┐
                        │   plane-worker   │                       │ plane-beat-worker│
                        │  (Celery Async)  │                       │ (Celery Periodic)│
                        └────────┬─────────┘                       └────────┬─────────┘
                                 │                                          │
         ┌───────────────────────┴──────────────────────────────────────────┘
         │
         ▼
┌──────────────────┐                           ┌──────────────────┐
│     plane-db     │                           │   plane-minio    │
│ (PostgreSQL 15)  │                           │(S3 File Storage) │
└──────────────────┘                           └──────────────────┘
```

For complete technical specifications, see **[docs/ARCHITECTURE.md](file:///docs/ARCHITECTURE.md)**.

---

## Prerequisites

Before starting, ensure your host server meets the following requirements:

* **Operating System**: Linux (Ubuntu 22.04+, Debian 12+, RHEL 9+), Windows Server / Windows 11 with Docker Desktop (WSL 2 backend), or macOS.
* **Hardware**:
  * **Minimum**: 2 vCPUs, 4 GB RAM, 20 GB SSD storage.
  * **Recommended (Production)**: 4+ vCPUs, 8 GB RAM, 50+ GB high-speed NVMe storage.
* **Software**:
  * **Docker Engine**: Version `24.0.0` or higher (`docker --version`).
  * **Docker Compose**: Version `v2.20.0` or higher (`docker compose version`).
  * **Python**: Version `3.9+` (used for automated secret generation).

---

## Remote Server Deployment (New Server / VPS)

### Option A: Windows Server (2022 / 2025 / Windows 10/11)
To deploy on a fresh Windows Server without Docker pre-installed:

1. Connect to the Windows Server via RDP or PowerShell SSH.
2. Open **PowerShell as Administrator** and run:

```powershell
# Automated one-command deployment
irm https://raw.githubusercontent.com/nizar-kode/plane-selfhost/main/deploy.ps1 | iex
```

Or if cloned locally:
```powershell
powershell -ExecutionPolicy Bypass -File .\deploy.ps1
```

> [!TIP]
> For the complete step-by-step Windows Server guide, WSL 2 setup, IIS port-80 resolution, and Task Scheduler automation, see **[docs/WINDOWS_SERVER_DEPLOYMENT.md](file:///docs/WINDOWS_SERVER_DEPLOYMENT.md)**.

### Option B: Linux Server (Ubuntu, Debian, CentOS, Rocky Linux)
To deploy on a fresh Linux remote server from scratch:

```bash
# 1. SSH into your remote server
ssh root@your-server-ip

# 2. Run the automated deployment bootstrap script
curl -fsSL https://raw.githubusercontent.com/nizar-kode/plane-selfhost/main/deploy.sh | bash
```

Or if the repository is already cloned on the server:
```bash
./scripts/deploy-server.sh
```

> [!TIP]
> For the complete Linux step-by-step manual, swap sizing, and cloud firewall recommendations, see **[docs/REMOTE_DEPLOYMENT.md](file:///docs/REMOTE_DEPLOYMENT.md)**.

---

## Quick Start Guide

### 1. Clone the Repository

```bash
git clone https://github.com/nizar-kode/plane-selfhost.git
cd plane-selfhost
```

### 2. Generate Secrets & Environment

Run the automated secret generator to create a secured `.env` from `.env.example`:

```bash
# Windows / Linux / macOS
python scripts/generate_secrets.py
```

This automatically generates:
* 50-character cryptographic Django `SECRET_KEY`.
* 64-character hex `LIVE_SERVER_SECRET_KEY` for WebSocket authentication.
* Random 32-character database password (`POSTGRES_PASSWORD`) and synchronized `DATABASE_URL`.
* Random 32-character message broker password (`RABBITMQ_PASSWORD`) and synchronized `AMQP_URL`.
* High-entropy MinIO storage keys (`AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY`).

> [!TIP]
> If deploying with a custom domain or behind an existing reverse proxy, edit `.env` and set:
> ```env
> APP_DOMAIN=plane.yourdomain.com
> WEB_URL=https://plane.yourdomain.com
> CORS_ALLOWED_ORIGINS=https://plane.yourdomain.com
> ```

### 3. Launch Plane

Start the stack with Docker Compose:

```bash
docker compose up -d
```

Or using the unified operations management tool:

```powershell
# Windows PowerShell
.\scripts\manage.ps1 start

# Linux / macOS Bash
./scripts/manage.sh start
```

> [!NOTE]
> On the first startup, the `migrator` service applies all database migrations. Services will take between 30 to 60 seconds to pass all health checks.

### 4. Verify Stack Health

```bash
docker compose ps
```

All services (`plane-db`, `plane-redis`, `plane-mq`, `plane-minio`, `api`, `web`, `space`, `admin`, `live`, `proxy`) should report state `healthy` or `running`.

---

## Accessing Plane & Initial Configuration

Once the stack is running, access Plane via your browser:

| Interface | URL | Purpose |
| :--- | :--- | :--- |
| **Main Web Application** | `http://localhost` (or your domain) | User workspaces, projects, cycles, and issues |
| **God Mode Admin Console**| `http://localhost/god-mode/` | System-wide admin dashboard, telemetry, quotas, and integrations |
| **Plane Space** | `http://localhost/spaces/` | Public roadmap, documentation, and external portals |

### First-Time Administrator Setup
1. Navigate to `http://localhost/god-mode/` (or `https://plane.yourdomain.com/god-mode/`).
2. Follow the on-screen prompts to register your initial **Instance Administrator** account.
3. Configure your general organization profile and default workspace.
4. Optional: Configure SMTP settings under `/god-mode/email/` to enable member invitation emails.

---

## Management & Daily Operations

The repository includes cross-platform management scripts for all routine tasks:

```
Windows:  .\scripts\manage.ps1 <command>
Linux:    ./scripts/manage.sh <command>
```

| Command | Action | Equivalent Docker Command |
| :--- | :--- | :--- |
| `start` | Start all services in background | `docker compose up -d` |
| `stop` | Stop all running containers | `docker compose down` |
| `restart` | Restart all containers | `docker compose restart` |
| `status` | View container health & endpoint URLs | `docker compose ps` |
| `logs [svc]` | Stream real-time container logs | `docker compose logs -f [service]` |
| `backup` | Create snapshot backup of DB & files | Runs automated backup utility |
| `restore [dir]`| Restore database & uploads from backup | Runs automated recovery utility |
| `update` | Backup, pull images, migrate & restart | Full automated update cycle |
| `init-secrets`| Regenerate secure credentials | Runs `scripts/generate_secrets.py` |

---

## Backup & Disaster Recovery

Plane stores data in two critical locations: PostgreSQL (database state) and MinIO (uploaded binary files).

### Creating a Snapshot Backup

Execute the backup script:

```powershell
# Windows PowerShell
.\scripts\manage.ps1 backup

# Linux / macOS Bash
./scripts/manage.sh backup
```

The utility automatically creates:
1. `plane_database.sql`: Clean logical dump via `pg_dump`.
2. `plane_pgdata.tar.gz`: PostgreSQL volume archive.
3. `plane_uploads.tar.gz`: MinIO file uploads archive.
4. `plane_redisdata.tar.gz`: Valkey cache archive.
5. `plane_rabbitmq_data.tar.gz`: Task queue state archive.
6. `plane.env.backup`: Configuration and cryptographic keys.

### Restoring from Backup

```powershell
# Windows PowerShell
.\scripts\manage.ps1 restore "backups\backup_YYYYMMDD_HHMMSS"

# Linux / macOS Bash
./scripts/manage.sh restore /path/to/backups/backup_YYYYMMDD_HHMMSS
```

For full disaster recovery runbooks, see **[docs/BACKUP_RESTORE.md](file:///docs/BACKUP_RESTORE.md)**.

---

## Upgrading Plane

To update Plane to future versions:

```powershell
# Windows PowerShell
.\scripts\manage.ps1 update

# Linux / macOS Bash
./scripts/manage.sh update
```

The upgrade workflow:
1. Performs an automatic safety backup of current data.
2. Pulls updated container images from Docker Hub.
3. Executes pending schema migrations via the `migrator` service.
4. Restarts all application services cleanly.

For manual upgrade instructions and rollback procedures, see **[docs/UPGRADE.md](file:///docs/UPGRADE.md)**.

---

## Reverse Proxy & SSL Setup

If you run existing reverse proxies (Nginx, Caddy, Traefik, or Cloudflare Tunnel) on the host machine:

1. In `.env`, change `LISTEN_HTTP_PORT=8080` (or another unused port) and set `NUM_PROXIES=1`.
2. Apply the relevant reverse-proxy configuration from `proxy/`:
   * **Nginx**: See `proxy/nginx/plane.conf`
   * **Caddy**: See `proxy/caddy/Caddyfile`
   * **Traefik**: See `proxy/traefik/dynamic_conf.yml`

For detailed setup instructions, see **[docs/REVERSE_PROXY.md](file:///docs/REVERSE_PROXY.md)**.

---

## Troubleshooting

### 1. Migrator Container Exits with Error
* **Symptom**: `plane-migrator` fails and API container refuses to start.
* **Resolution**: Verify PostgreSQL is healthy with `docker compose ps plane-db`. Inspect database logs:
  ```bash
  docker compose logs plane-db
  docker compose logs migrator
  ```
  Ensure database credentials in `DATABASE_URL` match `POSTGRES_USER` and `POSTGRES_PASSWORD` in `.env`.

### 2. Live Collaboration / Real-Time Sync Not Working
* **Symptom**: Collaborative text editing or presence indicators do not sync between tabs.
* **Resolution**: Plane Live uses WebSockets. Verify that:
  - `LIVE_SERVER_SECRET_KEY` is identical across all services in `.env`.
  - Your upstream reverse proxy passes `Upgrade $http_upgrade` and `Connection "upgrade"` headers.

### 3. File Uploads Failing
* **Symptom**: Image uploads or file attachments report `413 Request Entity Too Large` or network error.
* **Resolution**:
  - In `.env`, adjust `FILE_SIZE_LIMIT=52428800` (50 MB) or higher.
  - In your reverse proxy (e.g. Nginx), ensure `client_max_body_size 100M;` is configured.

### 4. Port 80 or 443 Already in Use
* **Symptom**: `bind: address already in use` error when starting docker compose.
* **Resolution**: Set `LISTEN_HTTP_PORT=8080` and `LISTEN_HTTPS_PORT=8443` in `.env`, then run `docker compose up -d`.

---

## Graphify Architecture & Knowledge Graph

This repository integrates **Graphify** to provide continuous dependency mapping, architectural cohesion scoring, and automated codebase intelligence.

```
graphify-out/
├── graph.json        # GraphRAG knowledge graph schema
├── graph.html        # Interactive 3D visual graph explorer
├── GRAPH_REPORT.md   # Structural audit & community cohesion report
```

To re-analyze or query the architecture graph:
```bash
# Query the architecture
python -m graphify query "How do services communicate with Redis and PostgreSQL?"

# Check shortest path between components
python -m graphify path "plane-api" "plane-db"
```

---

## Official Plane Resources

* **Official Website**: [https://plane.so/](https://plane.so/)
* **Plane Documentation**: [https://docs.plane.so/](https://docs.plane.so/)
* **GitHub Repository**: [https://github.com/makeplane/plane](https://github.com/makeplane/plane)
* **Docker Hub Images**: [https://hub.docker.com/u/makeplane](https://hub.docker.com/u/makeplane)
* **Community Discord**: [https://discord.com/invite/A2hkBrGEuv](https://discord.com/invite/A2hkBrGEuv)

---

## License

This deployment repository is provided under the **MIT License**.  
Plane Community Edition is licensed by MakePlane under the **Business Source License (BSL 1.1)** and **AGPL-3.0**.
