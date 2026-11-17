# Plane Self-Hosted Architecture

## 1. System Overview

**Plane** is an enterprise-grade, open-source project management platform structured as a distributed microservices application. This deployment package orchestrates all required application tiers, backing databases, asynchronous task pipelines, and gateway proxies using Docker Compose.

```
                           [ Users / Browsers ]
                                    │
                                    ▼ (HTTP/HTTPS :80/:443)
                      ┌───────────────────────────┐
                      │    plane-proxy (Caddy)    │
                      └─────────────┬─────────────┘
                                    │
         ┌───────────────┬──────────┼───────────────┬───────────────┐
         │               │          │               │               │
         ▼               ▼          ▼               ▼               ▼
  ┌─────────────┐ ┌─────────────┐ ┌───┴─────────┐ ┌───┴─────────┐ ┌─────────────┐
  │  plane-web  │ │ plane-space │ │ plane-admin │ │ plane-live  │ │  plane-api  │
  │  (Next.js)  │ │ (Portals)   │ │  (Console)  │ │(WebSockets) │ │(Django REST)│
  └─────────────┘ └─────────────┘ └─────────────┘ └──────┬──────┘ └──────┬──────┘
                                                         │               │
                              ┌──────────────────────────┴───────────────┴┐
                              │                                           │
                              ▼                                           ▼
                    ┌──────────────────┐                        ┌──────────────────┐
                    │   plane-redis    │                        │     plane-mq     │
                    │ (Valkey Cache &  │                        │(RabbitMQ Broker) │
                    │    Pub/Sub)      │                        └────────┬─────────┘
                    └────────┬─────────┘                                 │
                             │                                           │
                             │          ┌────────────────────────────────┤
                             ▼          ▼                                ▼
                      ┌──────────────────┐                     ┌──────────────────┐
                      │   plane-worker   │                     │ plane-beat-worker│
                      │  (Celery Async)  │                     │ (Celery Periodic)│
                      └────────┬─────────┘                     └────────┬─────────┘
                               │                                        │
         ┌─────────────────────┴────────────────────────────────────────┘
         │
         ▼
┌──────────────────┐                         ┌──────────────────┐
│     plane-db     │                         │   plane-minio    │
│ (PostgreSQL 15)  │                         │(S3 File Storage) │
└──────────────────┘                         └──────────────────┘
```

---

## 2. Component Details

### 2.1 Gateway & Routing Tier
* **`proxy` (`makeplane/plane-proxy:v1.5.0`)**:
  - Acts as the primary ingress point on ports `80` (HTTP) and `443` (HTTPS).
  - Built on Caddy, handling domain routing, reverse proxying, client header rewriting (`X-Forwarded-For`, `X-Forwarded-Proto`), and automatic TLS generation.
  - Dynamically dispatches requests:
    - `/` and UI routes -> `web`
    - `/api/*` -> `api`
    - `/spaces/*` -> `space`
    - `/god-mode/*` -> `admin`
    - `/live/*` (WebSockets) -> `live`

### 2.2 Presentation & Frontend Tier
* **`web` (`makeplane/plane-frontend:v1.5.0`)**:
  - The core Next.js web application for workspaces, issues, cycles, modules, views, analytics, and project settings.
* **`space` (`makeplane/plane-space:v1.5.0`)**:
  - Public project portals, customer feedback boards, and public roadmap sharing.
* **`admin` (`makeplane/plane-admin:v1.5.0`)**:
  - God-mode management interface (`/god-mode`) for instance-wide administrators, workspace quotas, telemetry, and authentication providers.

### 2.3 Backend & Application Logic
* **`api` (`makeplane/plane-backend:v1.5.0`)**:
  - Django REST framework application serving the main REST APIs, authentication, workspace management, issue tracking, and integrations.
  - Runs with Gunicorn multi-worker ASGI/WSGI servers.
* **`live` (`makeplane/plane-live:v1.5.0`)**:
  - High-performance real-time collaboration server providing WebSockets for multi-user issue editing, presence awareness, and cursor synchronization.
  - Interacts with `plane-redis` for ephemeral socket states and message fan-out.
* **`migrator` (`makeplane/plane-backend:v1.5.0`)**:
  - Runs database migrations at startup (`docker-entrypoint-migrator.sh`) and gracefully exits once the schema is up to date.

### 2.4 Asynchronous Processing Tier
* **`worker` (`makeplane/plane-backend:v1.5.0`)**:
  - Celery asynchronous task executor (`docker-entrypoint-worker.sh`) processing background jobs: email sending, image thumbnailing, webhook dispatching, activity feed updates, and issue exports.
* **`beat-worker` (`makeplane/plane-backend:v1.5.0`)**:
  - Celery Beat scheduler (`docker-entrypoint-beat.sh`) triggering scheduled routines, notification summaries, and maintenance cleanups.

### 2.5 Storage & Persistence Tier
* **`plane-db` (`postgres:15.7-alpine`)**:
  - Relational database storing users, projects, issues, cycles, comments, permissions, and audit logs.
  - Volume: `plane_pgdata` mounted to `/var/lib/postgresql/data`.
* **`plane-redis` (`valkey/valkey:7.2.11-alpine`)**:
  - Valkey (high-performance open-source Redis replacement) powering application caching, user sessions, and Pub/Sub communication for live collaboration.
  - Volume: `plane_redisdata` mounted to `/data`.
* **`plane-mq` (`rabbitmq:3.13.6-management-alpine`)**:
  - Message broker managing Celery task queues.
  - Volume: `plane_rabbitmq_data` mounted to `/var/lib/rabbitmq`.
* **`plane-minio` (`pgsty/silo:RELEASE.2026-09-16T00-00-00Z`)**:
  - S3-compatible object storage service storing project attachments, uploaded issue images, documents, and user avatars.
  - Volume: `plane_uploads` mounted to `/export`.

---

## 3. Data Persistence & Named Volumes

All stateful data is segregated into isolated Docker named volumes:

| Volume Name | Target Container Path | Contents |
| :--- | :--- | :--- |
| `plane_pgdata` | `/var/lib/postgresql/data` | PostgreSQL tables, indexes, and write-ahead logs |
| `plane_uploads` | `/export` | MinIO binary object storage (uploaded images & attachments) |
| `plane_redisdata` | `/data` | Valkey / Redis AOF & RDB persistent snapshots |
| `plane_rabbitmq_data` | `/var/lib/rabbitmq` | RabbitMQ durable queue state |
| `plane_logs_api` | `/code/plane/logs` | API service application logs |
| `plane_logs_worker` | `/code/plane/logs` | Celery asynchronous worker logs |
| `plane_proxy_data` | `/data` | Caddy TLS certificates and cryptographic keys |

---

## 4. Network Isolation & Security

* All services operate inside an isolated bridge network (`plane-network`).
* Only the `proxy` service binds ports to the host machine (`80` and `443`).
* Internal services (Postgres on `5432`, Redis on `6379`, RabbitMQ on `5672`, MinIO on `9000`) are not exposed to the public network or host ports, preventing unauthorized access.
* Container restart policy is set to `unless-stopped` to survive system reboots.
