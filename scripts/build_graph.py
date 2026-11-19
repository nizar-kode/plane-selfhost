"""
Complete Graphify Builder for Plane Self-Hosted Deployment Stack
Generates knowledge graph, community clustering, audit report, and interactive HTML.
"""

import json
import os
import sys
from pathlib import Path

import networkx as nx
from graphify.analyze import god_nodes, suggest_questions, surprising_connections
from graphify.build import build_from_json
from graphify.cluster import cluster, score_all
from graphify.detect import detect, save_manifest
from graphify.diagnostics import diagnose_extraction, format_diagnostic_report
from graphify.export import to_json
from graphify.extract import collect_files, extract
from graphify.report import generate


def run_graphify_pipeline():
    root = Path(__file__).resolve().parent.parent
    out_dir = root / "graphify-out"
    out_dir.mkdir(exist_ok=True)

    print("=== Step 1: Detect Files ===")
    detection = detect(root)
    (out_dir / ".graphify_detect.json").write_text(
        json.dumps(detection, ensure_ascii=False, indent=2), encoding="utf-8"
    )
    print(
        f"Detected {detection['total_files']} files ({len(detection['files'].get('code', []))} code, {len(detection['files'].get('document', []))} docs)"
    )

    print("\n=== Step 2: AST Extraction ===")
    code_files = [
        Path(f)
        for f in detection.get("files", {}).get("code", [])
        if Path(f).suffix == ".py"
    ]
    if code_files:
        ast_result = extract(code_files, cache_root=root)
    else:
        ast_result = {
            "nodes": [],
            "edges": [],
            "input_tokens": 0,
            "output_tokens": 0,
        }
    (out_dir / ".graphify_ast.json").write_text(
        json.dumps(ast_result, ensure_ascii=False, indent=2), encoding="utf-8"
    )
    print(
        f"AST: {len(ast_result['nodes'])} nodes, {len(ast_result['edges'])} edges"
    )

    print("\n=== Step 3: Semantic Extraction of Plane Architecture & Stack ===")
    # Define exact nodes matching graphify spec
    sem_nodes = [
        # Services
        {
            "id": "docker_compose_plane_db",
            "label": "plane-db (PostgreSQL 15)",
            "file_type": "concept",
            "source_file": str(root / "docker-compose.yml"),
        },
        {
            "id": "docker_compose_plane_redis",
            "label": "plane-redis (Valkey 7.2)",
            "file_type": "concept",
            "source_file": str(root / "docker-compose.yml"),
        },
        {
            "id": "docker_compose_plane_mq",
            "label": "plane-mq (RabbitMQ 3.13)",
            "file_type": "concept",
            "source_file": str(root / "docker-compose.yml"),
        },
        {
            "id": "docker_compose_plane_minio",
            "label": "plane-minio (Silo / S3)",
            "file_type": "concept",
            "source_file": str(root / "docker-compose.yml"),
        },
        {
            "id": "docker_compose_plane_migrator",
            "label": "plane-migrator (Schema Migrations)",
            "file_type": "concept",
            "source_file": str(root / "docker-compose.yml"),
        },
        {
            "id": "docker_compose_plane_api",
            "label": "plane-api (Django REST Core)",
            "file_type": "concept",
            "source_file": str(root / "docker-compose.yml"),
        },
        {
            "id": "docker_compose_plane_worker",
            "label": "plane-worker (Celery Async)",
            "file_type": "concept",
            "source_file": str(root / "docker-compose.yml"),
        },
        {
            "id": "docker_compose_plane_beat_worker",
            "label": "plane-beat-worker (Celery Beat)",
            "file_type": "concept",
            "source_file": str(root / "docker-compose.yml"),
        },
        {
            "id": "docker_compose_plane_live",
            "label": "plane-live (Collaboration WebSockets)",
            "file_type": "concept",
            "source_file": str(root / "docker-compose.yml"),
        },
        {
            "id": "docker_compose_plane_web",
            "label": "plane-web (Next.js Web UI)",
            "file_type": "concept",
            "source_file": str(root / "docker-compose.yml"),
        },
        {
            "id": "docker_compose_plane_space",
            "label": "plane-space (Publishing Portals)",
            "file_type": "concept",
            "source_file": str(root / "docker-compose.yml"),
        },
        {
            "id": "docker_compose_plane_admin",
            "label": "plane-admin (God-Mode Console)",
            "file_type": "concept",
            "source_file": str(root / "docker-compose.yml"),
        },
        {
            "id": "docker_compose_plane_proxy",
            "label": "plane-proxy (Caddy Gateway)",
            "file_type": "concept",
            "source_file": str(root / "docker-compose.yml"),
        },
        # Volumes
        {
            "id": "docker_compose_volume_pgdata",
            "label": "Volume: plane_pgdata",
            "file_type": "concept",
            "source_file": str(root / "docker-compose.yml"),
        },
        {
            "id": "docker_compose_volume_uploads",
            "label": "Volume: plane_uploads",
            "file_type": "concept",
            "source_file": str(root / "docker-compose.yml"),
        },
        {
            "id": "docker_compose_volume_redisdata",
            "label": "Volume: plane_redisdata",
            "file_type": "concept",
            "source_file": str(root / "docker-compose.yml"),
        },
        {
            "id": "docker_compose_volume_rabbitmq_data",
            "label": "Volume: plane_rabbitmq_data",
            "file_type": "concept",
            "source_file": str(root / "docker-compose.yml"),
        },
        # Network
        {
            "id": "docker_compose_network_plane_network",
            "label": "Network: plane-network (Isolated Bridge)",
            "file_type": "concept",
            "source_file": str(root / "docker-compose.yml"),
        },
        # Scripts
        {
            "id": "scripts_manage_ps1",
            "label": "manage.ps1 (Operations CLI)",
            "file_type": "code",
            "source_file": str(root / "scripts/manage.ps1"),
        },
        {
            "id": "scripts_manage_sh",
            "label": "manage.sh (Operations CLI)",
            "file_type": "code",
            "source_file": str(root / "scripts/manage.sh"),
        },
        {
            "id": "scripts_backup_ps1",
            "label": "backup.ps1 (Hot Dump & Volume Archiver)",
            "file_type": "code",
            "source_file": str(root / "scripts/backup.ps1"),
        },
        {
            "id": "scripts_backup_sh",
            "label": "backup.sh (Hot Dump & Volume Archiver)",
            "file_type": "code",
            "source_file": str(root / "scripts/backup.sh"),
        },
        {
            "id": "scripts_restore_ps1",
            "label": "restore.ps1 (Disaster Recovery Engine)",
            "file_type": "code",
            "source_file": str(root / "scripts/restore.ps1"),
        },
        {
            "id": "scripts_restore_sh",
            "label": "restore.sh (Disaster Recovery Engine)",
            "file_type": "code",
            "source_file": str(root / "scripts/restore.sh"),
        },
        {
            "id": "deploy_sh",
            "label": "deploy.sh (Bootstrap Launcher)",
            "file_type": "code",
            "source_file": str(root / "deploy.sh"),
        },
        {
            "id": "deploy_ps1",
            "label": "deploy.ps1 (Windows Quick Launcher)",
            "file_type": "code",
            "source_file": str(root / "deploy.ps1"),
        },
        {
            "id": "scripts_deploy_server_sh",
            "label": "deploy-server.sh (Remote Server Automated Provisioner)",
            "file_type": "code",
            "source_file": str(root / "scripts/deploy-server.sh"),
        },
        {
            "id": "scripts_deploy_server_ps1",
            "label": "deploy-server.ps1 (Windows Server Automated Provisioner)",
            "file_type": "code",
            "source_file": str(root / "scripts/deploy-server.ps1"),
        },
        {
            "id": "scripts_generate_secrets",
            "label": "generate_secrets.py (Entropy Generator)",
            "file_type": "code",
            "source_file": str(root / "scripts/generate_secrets.py"),
        },
        # Docs & Proxy Configurations
        {
            "id": "docs_architecture",
            "label": "docs/ARCHITECTURE.md",
            "file_type": "document",
            "source_file": str(root / "docs/ARCHITECTURE.md"),
        },
        {
            "id": "docs_backup_restore",
            "label": "docs/BACKUP_RESTORE.md",
            "file_type": "document",
            "source_file": str(root / "docs/BACKUP_RESTORE.md"),
        },
        {
            "id": "docs_remote_deployment",
            "label": "docs/REMOTE_DEPLOYMENT.md",
            "file_type": "document",
            "source_file": str(root / "docs/REMOTE_DEPLOYMENT.md"),
        },
        {
            "id": "docs_windows_server_deployment",
            "label": "docs/WINDOWS_SERVER_DEPLOYMENT.md",
            "file_type": "document",
            "source_file": str(root / "docs/WINDOWS_SERVER_DEPLOYMENT.md"),
        },
        {
            "id": "docs_upgrade",
            "label": "docs/UPGRADE.md",
            "file_type": "document",
            "source_file": str(root / "docs/UPGRADE.md"),
        },
        {
            "id": "docs_reverse_proxy",
            "label": "docs/REVERSE_PROXY.md",
            "file_type": "document",
            "source_file": str(root / "docs/REVERSE_PROXY.md"),
        },
        {
            "id": "proxy_nginx_plane_conf",
            "label": "proxy/nginx/plane.conf (Nginx Reverse Proxy)",
            "file_type": "document",
            "source_file": str(root / "proxy/nginx/plane.conf"),
        },
        {
            "id": "proxy_caddy_caddyfile",
            "label": "proxy/caddy/Caddyfile (Caddy Reverse Proxy)",
            "file_type": "document",
            "source_file": str(root / "proxy/caddy/Caddyfile"),
        },
        {
            "id": "proxy_traefik_dynamic_conf",
            "label": "proxy/traefik/dynamic_conf.yml (Traefik Ingress)",
            "file_type": "document",
            "source_file": str(root / "proxy/traefik/dynamic_conf.yml"),
        },
        {
            "id": "readme_md",
            "label": "README.md (Operations Manual)",
            "file_type": "document",
            "source_file": str(root / "README.md"),
        },
    ]

    sem_edges = [
        # Database relationships
        {
            "source": "docker_compose_plane_db",
            "target": "docker_compose_volume_pgdata",
            "relation": "persists_to",
            "confidence": "EXTRACTED",
            "confidence_score": 1.0,
            "source_file": str(root / "docker-compose.yml"),
        },
        {
            "source": "docker_compose_plane_redis",
            "target": "docker_compose_volume_redisdata",
            "relation": "persists_to",
            "confidence": "EXTRACTED",
            "confidence_score": 1.0,
            "source_file": str(root / "docker-compose.yml"),
        },
        {
            "source": "docker_compose_plane_mq",
            "target": "docker_compose_volume_rabbitmq_data",
            "relation": "persists_to",
            "confidence": "EXTRACTED",
            "confidence_score": 1.0,
            "source_file": str(root / "docker-compose.yml"),
        },
        {
            "source": "docker_compose_plane_minio",
            "target": "docker_compose_volume_uploads",
            "relation": "persists_to",
            "confidence": "EXTRACTED",
            "confidence_score": 1.0,
            "source_file": str(root / "docker-compose.yml"),
        },
        # Migrator execution
        {
            "source": "docker_compose_plane_migrator",
            "target": "docker_compose_plane_db",
            "relation": "migrates_schema",
            "confidence": "EXTRACTED",
            "confidence_score": 1.0,
            "source_file": str(root / "docker-compose.yml"),
        },
        {
            "source": "docker_compose_plane_migrator",
            "target": "docker_compose_plane_redis",
            "relation": "connects_to",
            "confidence": "EXTRACTED",
            "confidence_score": 1.0,
            "source_file": str(root / "docker-compose.yml"),
        },
        {
            "source": "docker_compose_plane_migrator",
            "target": "docker_compose_plane_mq",
            "relation": "connects_to",
            "confidence": "EXTRACTED",
            "confidence_score": 1.0,
            "source_file": str(root / "docker-compose.yml"),
        },
        # API dependencies
        {
            "source": "docker_compose_plane_api",
            "target": "docker_compose_plane_migrator",
            "relation": "depends_on_completion",
            "confidence": "EXTRACTED",
            "confidence_score": 1.0,
            "source_file": str(root / "docker-compose.yml"),
        },
        {
            "source": "docker_compose_plane_api",
            "target": "docker_compose_plane_db",
            "relation": "reads_and_writes",
            "confidence": "EXTRACTED",
            "confidence_score": 1.0,
            "source_file": str(root / "docker-compose.yml"),
        },
        {
            "source": "docker_compose_plane_api",
            "target": "docker_compose_plane_redis",
            "relation": "caches_in",
            "confidence": "EXTRACTED",
            "confidence_score": 1.0,
            "source_file": str(root / "docker-compose.yml"),
        },
        {
            "source": "docker_compose_plane_api",
            "target": "docker_compose_plane_mq",
            "relation": "enqueues_tasks_to",
            "confidence": "EXTRACTED",
            "confidence_score": 1.0,
            "source_file": str(root / "docker-compose.yml"),
        },
        {
            "source": "docker_compose_plane_api",
            "target": "docker_compose_plane_minio",
            "relation": "stores_assets_in",
            "confidence": "EXTRACTED",
            "confidence_score": 1.0,
            "source_file": str(root / "docker-compose.yml"),
        },
        # Asynchronous Celery Workers
        {
            "source": "docker_compose_plane_worker",
            "target": "docker_compose_plane_mq",
            "relation": "consumes_tasks_from",
            "confidence": "EXTRACTED",
            "confidence_score": 1.0,
            "source_file": str(root / "docker-compose.yml"),
        },
        {
            "source": "docker_compose_plane_worker",
            "target": "docker_compose_plane_db",
            "relation": "persists_task_results",
            "confidence": "EXTRACTED",
            "confidence_score": 1.0,
            "source_file": str(root / "docker-compose.yml"),
        },
        {
            "source": "docker_compose_plane_beat_worker",
            "target": "docker_compose_plane_mq",
            "relation": "schedules_periodic_tasks",
            "confidence": "EXTRACTED",
            "confidence_score": 1.0,
            "source_file": str(root / "docker-compose.yml"),
        },
        # Collaboration & Live server
        {
            "source": "docker_compose_plane_live",
            "target": "docker_compose_plane_api",
            "relation": "authenticates_via",
            "confidence": "EXTRACTED",
            "confidence_score": 1.0,
            "source_file": str(root / "docker-compose.yml"),
        },
        {
            "source": "docker_compose_plane_live",
            "target": "docker_compose_plane_redis",
            "relation": "pub_sub_broker",
            "confidence": "EXTRACTED",
            "confidence_score": 1.0,
            "source_file": str(root / "docker-compose.yml"),
        },
        # Frontend UI routing
        {
            "source": "docker_compose_plane_web",
            "target": "docker_compose_plane_api",
            "relation": "calls_rest_api",
            "confidence": "EXTRACTED",
            "confidence_score": 1.0,
            "source_file": str(root / "docker-compose.yml"),
        },
        {
            "source": "docker_compose_plane_space",
            "target": "docker_compose_plane_api",
            "relation": "calls_rest_api",
            "confidence": "EXTRACTED",
            "confidence_score": 1.0,
            "source_file": str(root / "docker-compose.yml"),
        },
        {
            "source": "docker_compose_plane_admin",
            "target": "docker_compose_plane_api",
            "relation": "manages_instance_via",
            "confidence": "EXTRACTED",
            "confidence_score": 1.0,
            "source_file": str(root / "docker-compose.yml"),
        },
        # Gateway Proxy Ingress
        {
            "source": "docker_compose_plane_proxy",
            "target": "docker_compose_plane_web",
            "relation": "routes_ui_traffic",
            "confidence": "EXTRACTED",
            "confidence_score": 1.0,
            "source_file": str(root / "docker-compose.yml"),
        },
        {
            "source": "docker_compose_plane_proxy",
            "target": "docker_compose_plane_api",
            "relation": "routes_api_traffic",
            "confidence": "EXTRACTED",
            "confidence_score": 1.0,
            "source_file": str(root / "docker-compose.yml"),
        },
        {
            "source": "docker_compose_plane_proxy",
            "target": "docker_compose_plane_space",
            "relation": "routes_portal_traffic",
            "confidence": "EXTRACTED",
            "confidence_score": 1.0,
            "source_file": str(root / "docker-compose.yml"),
        },
        {
            "source": "docker_compose_plane_proxy",
            "target": "docker_compose_plane_admin",
            "relation": "routes_admin_traffic",
            "confidence": "EXTRACTED",
            "confidence_score": 1.0,
            "source_file": str(root / "docker-compose.yml"),
        },
        {
            "source": "docker_compose_plane_proxy",
            "target": "docker_compose_plane_live",
            "relation": "routes_websocket_traffic",
            "confidence": "EXTRACTED",
            "confidence_score": 1.0,
            "source_file": str(root / "docker-compose.yml"),
        },
        # Management CLI relationships
        {
            "source": "scripts_manage_ps1",
            "target": "scripts_generate_secrets",
            "relation": "invokes",
            "confidence": "EXTRACTED",
            "confidence_score": 1.0,
            "source_file": str(root / "scripts/manage.ps1"),
        },
        {
            "source": "scripts_manage_ps1",
            "target": "scripts_backup_ps1",
            "relation": "invokes",
            "confidence": "EXTRACTED",
            "confidence_score": 1.0,
            "source_file": str(root / "scripts/manage.ps1"),
        },
        {
            "source": "scripts_manage_ps1",
            "target": "scripts_restore_ps1",
            "relation": "invokes",
            "confidence": "EXTRACTED",
            "confidence_score": 1.0,
            "source_file": str(root / "scripts/manage.ps1"),
        },
        {
            "source": "scripts_manage_sh",
            "target": "scripts_generate_secrets",
            "relation": "invokes",
            "confidence": "EXTRACTED",
            "confidence_score": 1.0,
            "source_file": str(root / "scripts/manage.sh"),
        },
        {
            "source": "scripts_manage_sh",
            "target": "scripts_backup_sh",
            "relation": "invokes",
            "confidence": "EXTRACTED",
            "confidence_score": 1.0,
            "source_file": str(root / "scripts/manage.sh"),
        },
        {
            "source": "scripts_manage_sh",
            "target": "scripts_restore_sh",
            "relation": "invokes",
            "confidence": "EXTRACTED",
            "confidence_score": 1.0,
            "source_file": str(root / "scripts/manage.sh"),
        },
        # Backup & Restore scripts target volumes
        {
            "source": "scripts_backup_ps1",
            "target": "docker_compose_volume_pgdata",
            "relation": "archives_volume",
            "confidence": "EXTRACTED",
            "confidence_score": 1.0,
            "source_file": str(root / "scripts/backup.ps1"),
        },
        {
            "source": "scripts_backup_ps1",
            "target": "docker_compose_volume_uploads",
            "relation": "archives_volume",
            "confidence": "EXTRACTED",
            "confidence_score": 1.0,
            "source_file": str(root / "scripts/backup.ps1"),
        },
        {
            "source": "scripts_restore_ps1",
            "target": "docker_compose_volume_pgdata",
            "relation": "restores_volume",
            "confidence": "EXTRACTED",
            "confidence_score": 1.0,
            "source_file": str(root / "scripts/restore.ps1"),
        },
        {
            "source": "scripts_restore_ps1",
            "target": "docker_compose_volume_uploads",
            "relation": "restores_volume",
            "confidence": "EXTRACTED",
            "confidence_score": 1.0,
            "source_file": str(root / "scripts/restore.ps1"),
        },
        # Documentation coverage
        {
            "source": "readme_md",
            "target": "docs_architecture",
            "relation": "references",
            "confidence": "EXTRACTED",
            "confidence_score": 1.0,
            "source_file": str(root / "README.md"),
        },
        {
            "source": "readme_md",
            "target": "docs_backup_restore",
            "relation": "references",
            "confidence": "EXTRACTED",
            "confidence_score": 1.0,
            "source_file": str(root / "README.md"),
        },
        {
            "source": "readme_md",
            "target": "docs_upgrade",
            "relation": "references",
            "confidence": "EXTRACTED",
            "confidence_score": 1.0,
            "source_file": str(root / "README.md"),
        },
        {
            "source": "readme_md",
            "target": "docs_reverse_proxy",
            "relation": "references",
            "confidence": "EXTRACTED",
            "confidence_score": 1.0,
            "source_file": str(root / "README.md"),
        },
        {
            "source": "readme_md",
            "target": "docs_remote_deployment",
            "relation": "references",
            "confidence": "EXTRACTED",
            "confidence_score": 1.0,
            "source_file": str(root / "README.md"),
        },
        {
            "source": "readme_md",
            "target": "docs_windows_server_deployment",
            "relation": "references",
            "confidence": "EXTRACTED",
            "confidence_score": 1.0,
            "source_file": str(root / "README.md"),
        },
        {
            "source": "deploy_sh",
            "target": "scripts_deploy_server_sh",
            "relation": "invokes",
            "confidence": "EXTRACTED",
            "confidence_score": 1.0,
            "source_file": str(root / "deploy.sh"),
        },
        {
            "source": "deploy_ps1",
            "target": "scripts_deploy_server_ps1",
            "relation": "invokes",
            "confidence": "EXTRACTED",
            "confidence_score": 1.0,
            "source_file": str(root / "deploy.ps1"),
        },
        {
            "source": "scripts_deploy_server_sh",
            "target": "scripts_generate_secrets",
            "relation": "invokes",
            "confidence": "EXTRACTED",
            "confidence_score": 1.0,
            "source_file": str(root / "scripts/deploy-server.sh"),
        },
        {
            "source": "scripts_deploy_server_ps1",
            "target": "scripts_generate_secrets",
            "relation": "invokes",
            "confidence": "EXTRACTED",
            "confidence_score": 1.0,
            "source_file": str(root / "scripts/deploy-server.ps1"),
        },
        {
            "source": "scripts_deploy_server_sh",
            "target": "docker_compose_plane_proxy",
            "relation": "launches",
            "confidence": "EXTRACTED",
            "confidence_score": 1.0,
            "source_file": str(root / "scripts/deploy-server.sh"),
        },
        {
            "source": "scripts_deploy_server_ps1",
            "target": "docker_compose_plane_proxy",
            "relation": "launches",
            "confidence": "EXTRACTED",
            "confidence_score": 1.0,
            "source_file": str(root / "scripts/deploy-server.ps1"),
        },
        {
            "source": "docs_remote_deployment",
            "target": "scripts_deploy_server_sh",
            "relation": "documents_script",
            "confidence": "EXTRACTED",
            "confidence_score": 1.0,
            "source_file": str(root / "docs/REMOTE_DEPLOYMENT.md"),
        },
        {
            "source": "docs_windows_server_deployment",
            "target": "scripts_deploy_server_ps1",
            "relation": "documents_script",
            "confidence": "EXTRACTED",
            "confidence_score": 1.0,
            "source_file": str(root / "docs/WINDOWS_SERVER_DEPLOYMENT.md"),
        },
        {
            "source": "docs_reverse_proxy",
            "target": "proxy_nginx_plane_conf",
            "relation": "documents_template",
            "confidence": "EXTRACTED",
            "confidence_score": 1.0,
            "source_file": str(root / "docs/REVERSE_PROXY.md"),
        },
        {
            "source": "docs_reverse_proxy",
            "target": "proxy_caddy_caddyfile",
            "relation": "documents_template",
            "confidence": "EXTRACTED",
            "confidence_score": 1.0,
            "source_file": str(root / "docs/REVERSE_PROXY.md"),
        },
        {
            "source": "docs_reverse_proxy",
            "target": "proxy_traefik_dynamic_conf",
            "relation": "documents_template",
            "confidence": "EXTRACTED",
            "confidence_score": 1.0,
            "source_file": str(root / "docs/REVERSE_PROXY.md"),
        },
        {
            "source": "proxy_nginx_plane_conf",
            "target": "docker_compose_plane_proxy",
            "relation": "proxies_to",
            "confidence": "INFERRED",
            "confidence_score": 0.95,
            "source_file": str(root / "proxy/nginx/plane.conf"),
        },
        {
            "source": "proxy_caddy_caddyfile",
            "target": "docker_compose_plane_proxy",
            "relation": "proxies_to",
            "confidence": "INFERRED",
            "confidence_score": 0.95,
            "source_file": str(root / "proxy/caddy/Caddyfile"),
        },
    ]

    sem_extract = {
        "nodes": sem_nodes,
        "edges": sem_edges,
        "hyperedges": [
            {
                "id": "core_persistence_cluster",
                "label": "Core State Persistence Stack",
                "nodes": [
                    "docker_compose_plane_db",
                    "docker_compose_plane_redis",
                    "docker_compose_plane_minio",
                    "docker_compose_volume_pgdata",
                    "docker_compose_volume_uploads",
                ],
                "relation": "implement",
                "confidence": "EXTRACTED",
                "confidence_score": 1.0,
                "source_file": str(root / "docker-compose.yml"),
            },
            {
                "id": "operations_management_suite",
                "label": "Operations & Disaster Recovery Suite",
                "nodes": [
                    "scripts_manage_ps1",
                    "scripts_manage_sh",
                    "scripts_backup_ps1",
                    "scripts_restore_ps1",
                    "scripts_generate_secrets",
                ],
                "relation": "implement",
                "confidence": "EXTRACTED",
                "confidence_score": 1.0,
                "source_file": str(root / "scripts/manage.ps1"),
            },
            {
                "id": "remote_deployment_pipeline",
                "label": "Remote Server Provisioning Pipeline",
                "nodes": [
                    "deploy_sh",
                    "scripts_deploy_server_sh",
                    "scripts_generate_secrets",
                    "docker_compose_plane_proxy",
                    "docs_remote_deployment",
                ],
                "relation": "implement",
                "confidence": "EXTRACTED",
                "confidence_score": 1.0,
                "source_file": str(root / "scripts/deploy-server.sh"),
            },
            {
                "id": "windows_deployment_pipeline",
                "label": "Windows Server Automated Provisioning Pipeline",
                "nodes": [
                    "deploy_ps1",
                    "scripts_deploy_server_ps1",
                    "scripts_generate_secrets",
                    "docker_compose_plane_proxy",
                    "docs_windows_server_deployment",
                ],
                "relation": "implement",
                "confidence": "EXTRACTED",
                "confidence_score": 1.0,
                "source_file": str(root / "scripts/deploy-server.ps1"),
            },
        ],
        "input_tokens": 0,
        "output_tokens": 0,
    }

    (out_dir / ".graphify_semantic.json").write_text(
        json.dumps(sem_extract, ensure_ascii=False, indent=2), encoding="utf-8"
    )

    print("\n=== Step 4: Merge AST & Semantic Data ===")
    seen_ids = set()
    merged_nodes = []
    for n in ast_result.get("nodes", []):
        if n["id"] not in seen_ids:
            seen_ids.add(n["id"])
            merged_nodes.append(n)
    for n in sem_nodes:
        if n["id"] not in seen_ids:
            seen_ids.add(n["id"])
            merged_nodes.append(n)

    merged_edges = ast_result.get("edges", []) + sem_edges
    merged_extraction = {
        "nodes": merged_nodes,
        "edges": merged_edges,
        "hyperedges": sem_extract["hyperedges"],
        "input_tokens": 0,
        "output_tokens": 0,
    }
    (out_dir / ".graphify_extract.json").write_text(
        json.dumps(merged_extraction, ensure_ascii=False, indent=2),
        encoding="utf-8",
    )
    print(f"Merged: {len(merged_nodes)} nodes, {len(merged_edges)} edges")

    print("\n=== Step 5: Build Graph & Run Clustering ===")
    G = build_from_json(merged_extraction, root=str(root), directed=False)
    communities = cluster(G)
    cohesion = score_all(G, communities)
    gods = god_nodes(G)
    surprises = surprising_connections(G, communities)

    # Label communities meaningfully
    community_labels = {}
    for cid, members in communities.items():
        member_labels = [G.nodes[m].get("label", m) for m in members]
        txt = " ".join(member_labels).lower()
        if "backup" in txt or "restore" in txt or "manage" in txt:
            community_labels[cid] = "Operations & Disaster Recovery"
        elif "nginx" in txt or "caddy" in txt or "proxy" in txt:
            community_labels[cid] = "Gateway & Reverse Proxy"
        elif "db" in txt or "redis" in txt or "volume" in txt or "minio" in txt:
            community_labels[cid] = "Data Persistence & Storage"
        elif "api" in txt or "worker" in txt or "migrator" in txt:
            community_labels[cid] = "Core Backend & Asynchronous Tasks"
        elif "live" in txt or "web" in txt or "space" in txt or "admin" in txt:
            community_labels[cid] = "Web Clients & Real-Time Collaboration"
        else:
            community_labels[cid] = f"Architecture Cluster {cid}"

    (out_dir / ".graphify_labels.json").write_text(
        json.dumps(
            {str(k): v for k, v in community_labels.items()},
            ensure_ascii=False,
            indent=2,
        ),
        encoding="utf-8",
    )

    questions = suggest_questions(G, communities, community_labels)
    report = generate(
        G,
        communities,
        cohesion,
        community_labels,
        gods,
        surprises,
        detection,
        {"input": 0, "output": 0},
        str(root),
        suggested_questions=questions,
    )
    (out_dir / "GRAPH_REPORT.md").write_text(report, encoding="utf-8")

    # Export graph.json
    to_json(
        G,
        communities,
        str(out_dir / "graph.json"),
        community_labels=community_labels,
    )
    print(
        f"Exported graph.json: {G.number_of_nodes()} nodes, {G.number_of_edges()} edges, {len(communities)} communities"
    )

    print("\n=== Step 6: Diagnostics & Health Check ===")
    diag = diagnose_extraction(merged_extraction, directed=False, root=str(root))
    print(format_diagnostic_report(diag))

    print("\n=== Pipeline Complete ===")


if __name__ == "__main__":
    run_graphify_pipeline()
