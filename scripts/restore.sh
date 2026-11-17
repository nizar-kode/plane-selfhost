#!/usr/bin/env bash
# ==============================================================================
# Plane Enterprise Restore Utility (Bash)
# Restores persistent volumes and databases from a previous backup archive.
# ==============================================================================

set -euo pipefail

if [ "$#" -lt 1 ]; then
    echo "Usage: $0 <path-to-backup-dir>"
    exit 1
fi

BACKUP_DIR="$1"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$PROJECT_ROOT"

if [ ! -d "$BACKUP_DIR" ]; then
    echo "Error: Backup directory '$BACKUP_DIR' does not exist."
    exit 1
fi

echo "=================================================="
echo "       Plane Self-Hosted Restore Utility (Bash)   "
echo "=================================================="
echo "Source Backup: $BACKUP_DIR"

# 1. Stop Stack if running
if docker ps --filter "name=plane-" -q | grep -q .; then
    echo -e "\n[!] Active Plane containers detected. Stopping stack..."
    docker compose down
fi

# 2. Restore Volumes
VOLUMES=("plane_pgdata" "plane_uploads" "plane_redisdata" "plane_rabbitmq_data")

for VOL in "${VOLUMES[@]}"; do
    ARCHIVE_FILE="$BACKUP_DIR/$VOL.tar.gz"
    if [ -f "$ARCHIVE_FILE" ]; then
        echo -e "\nRestoring volume: $VOL..."
        docker volume create "$VOL" >/dev/null
        docker run --rm \
            -v "$VOL:/target_vol" \
            -v "$BACKUP_DIR:/backup_src:ro" \
            alpine sh -c "rm -rf /target_vol/* /target_vol/..?* /target_vol/.[!.]* && tar -xzf /backup_src/$VOL.tar.gz -C /target_vol"
        echo "  -> [OK] Volume $VOL restored."
    else
        echo "  -> Skipping $VOL (archive not found)."
    fi
done

# 3. Environment File
if [ -f "$BACKUP_DIR/plane.env.backup" ]; then
    if [ ! -f ".env" ]; then
        cp "$BACKUP_DIR/plane.env.backup" .env
        echo "  -> Restored .env from backup."
    fi
fi

echo "=================================================="
echo "Restore operation complete!"
echo "You can now start Plane with: docker compose up -d"
echo "=================================================="
