#!/usr/bin/env bash
# ==============================================================================
# Plane Enterprise Backup Utility (Bash)
# Creates a snapshot backup of PostgreSQL database and MinIO storage volumes.
# ==============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$PROJECT_ROOT"

TIMESTAMP=$(date +"%Y%m%d_%H%M%S")
OUTPUT_DIR="${1:-$PROJECT_ROOT/backups/backup_$TIMESTAMP}"

mkdir -p "$OUTPUT_DIR"

echo "=================================================="
echo "       Plane Self-Hosted Backup Utility (Bash)    "
echo "=================================================="
echo "Destination: $OUTPUT_DIR"

# 1. Database Hot Dump
echo -e "\n[1/3] Exporting PostgreSQL database (pg_dump)..."
SQL_FILE="$OUTPUT_DIR/plane_database.sql"

if docker ps --filter "name=plane-db" --filter "status=running" -q | grep -q .; then
    POSTGRES_USER="${POSTGRES_USER:-plane}"
    POSTGRES_DB="${POSTGRES_DB:-plane}"
    docker exec -t plane-db pg_dump -U "$POSTGRES_USER" -d "$POSTGRES_DB" -F p > "$SQL_FILE" || true
    echo "  -> PostgreSQL dump created: $SQL_FILE"
else
    echo "  -> plane-db container is not running; skipping live SQL dump."
fi

# 2. Volume Archives
echo -e "\n[2/3] Archiving Docker volumes..."
VOLUMES=("plane_pgdata" "plane_uploads" "plane_redisdata" "plane_rabbitmq_data")

for VOL in "${VOLUMES[@]}"; do
    ARCHIVE_FILE="$VOL.tar.gz"
    echo "  -> Archiving volume: $VOL to $ARCHIVE_FILE..."
    docker run --rm \
        -v "$VOL:/volume_data:ro" \
        -v "$OUTPUT_DIR:/backup_target" \
        alpine sh -c "tar -czf /backup_target/$ARCHIVE_FILE -C /volume_data ."
    echo "     [OK] $VOL archived successfully."
done

# 3. Environment Backup
echo -e "\n[3/3] Backing up configuration (.env)..."
if [ -f ".env" ]; then
    cp .env "$OUTPUT_DIR/plane.env.backup"
    echo "  -> Configuration saved as plane.env.backup"
fi

echo "=================================================="
echo "Backup completed successfully!"
echo "Archive location: $OUTPUT_DIR"
echo "=================================================="
