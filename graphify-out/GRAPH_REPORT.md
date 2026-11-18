# Graph Report - plane project managmenet  (2026-11-18)

## Corpus Check
- Corpus is ~12,302 words - fits in a single context window. You may not need a graph.

## Summary
- 60 nodes · 78 edges · 7 communities (6 shown, 1 thin omitted)
- Extraction: 97% EXTRACTED · 3% INFERRED · 0% AMBIGUOUS · INFERRED: 2 edges (avg confidence: 0.95)
- Token cost: 0 input · 0 output

## Community Hubs (Navigation)
- Gateway & Reverse Proxy
- Architecture Cluster 1
- Architecture Cluster 2
- Operations & Disaster Recovery
- Operations & Disaster Recovery
- Operations & Disaster Recovery
- Architecture Cluster 6

## God Nodes (most connected - your core abstractions)
1. `plane-api (Django REST Core)` - 10 edges
2. `plane-proxy (Caddy Gateway)` - 8 edges
3. `plane-mq (RabbitMQ 3.13)` - 5 edges
4. `README.md (Operations Manual)` - 5 edges
5. `main()` - 4 edges
6. `plane-db (PostgreSQL 15)` - 4 edges
7. `plane-redis (Valkey 7.2)` - 4 edges
8. `plane-migrator (Schema Migrations)` - 4 edges
9. `deploy-server.sh (Remote Server Automated Provisioner)` - 4 edges
10. `plane-live (Collaboration WebSockets)` - 3 edges

## Surprising Connections (you probably didn't know these)
- `proxy/nginx/plane.conf (Nginx Reverse Proxy)` --proxies_to--> `plane-proxy (Caddy Gateway)`  [INFERRED]
  proxy/nginx/plane.conf → docker-compose.yml
- `deploy-server.sh (Remote Server Automated Provisioner)` --launches--> `plane-proxy (Caddy Gateway)`  [EXTRACTED]
  scripts/deploy-server.sh → docker-compose.yml
- `backup.ps1 (Hot Dump & Volume Archiver)` --archives_volume--> `Volume: plane_pgdata`  [EXTRACTED]
  scripts/backup.ps1 → docker-compose.yml
- `restore.ps1 (Disaster Recovery Engine)` --restores_volume--> `Volume: plane_pgdata`  [EXTRACTED]
  scripts/restore.ps1 → docker-compose.yml
- `backup.ps1 (Hot Dump & Volume Archiver)` --archives_volume--> `Volume: plane_uploads`  [EXTRACTED]
  scripts/backup.ps1 → docker-compose.yml

## Import Cycles
- None detected.

## Hyperedges (group relationships)
- **Core State Persistence Stack** — docker_compose_plane_db, docker_compose_plane_redis, docker_compose_plane_minio, docker_compose_volume_pgdata, docker_compose_volume_uploads [EXTRACTED 1.00]
- **Operations & Disaster Recovery Suite** — scripts_manage_ps1, scripts_manage_sh, scripts_backup_ps1, scripts_restore_ps1, scripts_generate_secrets [EXTRACTED 1.00]
- **Remote Server Provisioning Pipeline** — deploy_sh, scripts_deploy_server_sh, scripts_generate_secrets, docker_compose_plane_proxy, docs_remote_deployment [EXTRACTED 1.00]

## Communities (7 total, 1 thin omitted)

### Community 0 - "Gateway & Reverse Proxy"
Cohesion: 0.24
Nodes (14): plane-admin (God-Mode Console), plane-api (Django REST Core), plane-beat-worker (Celery Beat), plane-db (PostgreSQL 15), plane-live (Collaboration WebSockets), plane-migrator (Schema Migrations), plane-mq (RabbitMQ 3.13), plane-proxy (Caddy Gateway) (+6 more)

### Community 1 - "Architecture Cluster 1"
Cohesion: 0.15
Nodes (11): graphify_analyze, graphify_build, graphify_cluster, graphify_detect, graphify_diagnostics, graphify_export, graphify_extract, graphify_report (+3 more)

### Community 2 - "Architecture Cluster 2"
Cohesion: 0.21
Nodes (11): os, pathlib, re, generate_alphanumeric(), generate_django_secret_key(), generate_hex(), main(), Plane Secret & Environment Generator Generates cryptographically secure secrets… (+3 more)

### Community 3 - "Operations & Disaster Recovery"
Cohesion: 0.18
Nodes (6): deploy.sh (Bootstrap Launcher), proxy/caddy/Caddyfile (Caddy Reverse Proxy), proxy/nginx/plane.conf (Nginx Reverse Proxy), proxy/traefik/dynamic_conf.yml (Traefik Ingress), README.md (Operations Manual), deploy-server.sh (Remote Server Automated Provisioner)

### Community 4 - "Operations & Disaster Recovery"
Cohesion: 0.47
Nodes (6): plane-minio (Silo / S3), Volume: plane_pgdata, Volume: plane_uploads, backup.ps1 (Hot Dump & Volume Archiver), manage.ps1 (Operations CLI), restore.ps1 (Disaster Recovery Engine)

### Community 5 - "Operations & Disaster Recovery"
Cohesion: 0.67
Nodes (3): backup.sh (Hot Dump & Volume Archiver), manage.sh (Operations CLI), restore.sh (Disaster Recovery Engine)

## Knowledge Gaps
- **8 isolated node(s):** `plane-beat-worker (Celery Beat)`, `Volume: plane_redisdata`, `Volume: plane_rabbitmq_data`, `Network: plane-network (Isolated Bridge)`, `backup.sh (Hot Dump & Volume Archiver)` (+3 more)
  These have ≤1 connection - possible missing edges or undocumented components. (Counts symbols only; 27 node(s) total have ≤1 connection when file, concept and rationale nodes are included.)
- **1 thin communities (<3 nodes) omitted from report** — run `graphify query` to explore isolated nodes.

## Suggested Questions
_Questions this graph is uniquely positioned to answer:_

- **Why does `deploy-server.sh (Remote Server Automated Provisioner)` connect `Operations & Disaster Recovery` to `Gateway & Reverse Proxy`, `Architecture Cluster 2`?**
  _High betweenness centrality (0.438) - this node is a cross-community bridge._
- **Why does `plane-proxy (Caddy Gateway)` connect `Gateway & Reverse Proxy` to `Operations & Disaster Recovery`?**
  _High betweenness centrality (0.368) - this node is a cross-community bridge._
- **Why does `plane-api (Django REST Core)` connect `Gateway & Reverse Proxy` to `Operations & Disaster Recovery`?**
  _High betweenness centrality (0.220) - this node is a cross-community bridge._
- **Are the 2 inferred relationships involving `plane-proxy (Caddy Gateway)` (e.g. with `proxy/caddy/Caddyfile (Caddy Reverse Proxy)` and `proxy/nginx/plane.conf (Nginx Reverse Proxy)`) actually correct?**
  _`plane-proxy (Caddy Gateway)` has 2 INFERRED edges - model-reasoned connections that need verification._
- **What connects `plane-beat-worker (Celery Beat)`, `Volume: plane_redisdata`, `Volume: plane_rabbitmq_data` to the rest of the system?**
  _8 weakly-connected nodes found - possible documentation gaps or missing edges._