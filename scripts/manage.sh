#!/usr/bin/env bash
# ==============================================================================
# Plane Enterprise Deployment & Operations Management CLI (Bash)
# Comprehensive management tool for Plane Self-Hosted stack on Linux / macOS.
# ==============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$PROJECT_ROOT"

show_header() {
cat << "EOF"
==============================================================
   ____  _                  ____       _  __      _   _           _ 
  |  _ \| | __ _ _ __   ___/ ___|  ___| |/ _|    | | | | ___  ___| |_ 
  | |_) | |/ _` | '_ \ / _ \___ \ / _ \ | |_|____| |_| |/ _ \/ __| __|
  |  __/| | (_| | | | |  __/___) |  __/ |  _|____|  _  | (_) \__ \ |_ 
  |_|   |_|\__,_|_| |_|\___|____/ \___|_|_|      |_| |_|\___/|___/\__|
==============================================================
  Self-Hosted Project Management Platform | Plane v1.5.0
==============================================================
EOF
}

ensure_env() {
    if [ ! -f ".env" ]; then
        echo "[!] No .env file found. Generating secure environment..."
        python3 scripts/generate_secrets.py || python scripts/generate_secrets.py
    fi
}

start_plane() {
    ensure_env
    echo -e "\n[+] Starting Plane services..."
    docker compose up -d
    echo -e "\n[OK] Plane is launching in background."
    echo "Services take ~30-60 seconds for migrations and health checks."
    show_status
}

stop_plane() {
    echo -e "\n[-] Stopping Plane services..."
    docker compose down
    echo "[OK] All Plane services stopped."
}

restart_plane() {
    echo -e "\n[*] Restarting Plane services..."
    docker compose restart
    echo "[OK] Services restarted."
}

show_status() {
    echo -e "\n--------------------------------------------------------------"
    echo "                 Plane Stack Health & Status                  "
    echo "--------------------------------------------------------------"
    docker compose ps

    WEB_URL="http://localhost"
    if [ -f ".env" ]; then
        WEB_URL=$(grep "^WEB_URL=" .env | cut -d'=' -f2- || echo "http://localhost")
    fi

    echo -e "\n[Access Endpoints]"
    echo "  -> Main Web App:     $WEB_URL"
    echo "  -> Admin Console:    $WEB_URL/god-mode/"
    echo "  -> Documentation:    https://docs.plane.so"
    echo "--------------------------------------------------------------"
}

show_logs() {
    local SERVICE="${1:-}"
    if [ -z "$SERVICE" ]; then
        echo -e "\nStreaming logs for all Plane services (Ctrl+C to exit)..."
        docker compose logs -f --tail=100
    else
        echo -e "\nStreaming logs for $SERVICE (Ctrl+C to exit)..."
        docker compose logs -f --tail=100 "$SERVICE"
    fi
}

update_plane() {
    echo -e "\n[1/4] Creating safety backup before upgrade..."
    bash "$SCRIPT_DIR/backup.sh"

    echo -e "\n[2/4] Pulling updated container images..."
    docker compose pull

    echo -e "\n[3/4] Running schema migrations..."
    docker compose run --rm migrator

    echo -e "\n[4/4] Restarting updated Plane stack..."
    docker compose up -d

    echo -e "\n[OK] Upgrade process completed successfully!"
    show_status
}

show_menu() {
    show_header
    echo "Select an action:"
    echo "  1) Start Plane (docker compose up -d)"
    echo "  2) Stop Plane (docker compose down)"
    echo "  3) Restart Services"
    echo "  4) View Health & Status"
    echo "  5) View Real-Time Logs"
    echo "  6) Backup Database & Files"
    echo "  7) Restore From Backup"
    echo "  8) Upgrade Plane & Run Migrations"
    echo "  9) Re-generate Secrets (.env)"
    echo "  0) Exit"

    read -rp "Enter choice [1-0]: " CHOICE
    case "$CHOICE" in
        1) start_plane ;;
        2) stop_plane ;;
        3) restart_plane ;;
        4) show_status ;;
        5)
            read -rp "Enter service name (empty for all): " SVC
            show_logs "$SVC"
            ;;
        6) bash "$SCRIPT_DIR/backup.sh" ;;
        7)
            read -rp "Enter backup folder path: " BPATH
            bash "$SCRIPT_DIR/restore.sh" "$BPATH"
            ;;
        8) update_plane ;;
        9) python3 "$SCRIPT_DIR/generate_secrets.py" --force || python "$SCRIPT_DIR/generate_secrets.py" --force ;;
        0) exit 0 ;;
        *) echo "Invalid choice." ;;
    esac
}

CMD="${1:-menu}"
case "$CMD" in
    start)        show_header; start_plane ;;
    stop)         show_header; stop_plane ;;
    restart)      show_header; restart_plane ;;
    status)       show_header; show_status ;;
    logs)         show_header; show_logs "${2:-}" ;;
    backup)       show_header; bash "$SCRIPT_DIR/backup.sh" ;;
    restore)      show_header; bash "$SCRIPT_DIR/restore.sh" "${2:-}" ;;
    update)       show_header; update_plane ;;
    init-secrets) python3 "$SCRIPT_DIR/generate_secrets.py" || python "$SCRIPT_DIR/generate_secrets.py" ;;
    menu)         show_menu ;;
    *)            show_menu ;;
esac
