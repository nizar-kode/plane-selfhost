#!/usr/bin/env bash
# ==============================================================================
# Plane Self-Hosted - Root Quick Launcher / Bootstrap Script
# Usage:
#   Direct execution: ./deploy.sh
#   Remote curl execution: curl -fsSL https://raw.githubusercontent.com/nizar-kode/plane-selfhost/main/deploy.sh | bash
# ==============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" 2>/dev/null && pwd || echo "")"

if [ -n "$SCRIPT_DIR" ] && [ -f "$SCRIPT_DIR/scripts/deploy-server.sh" ]; then
    # Running from within cloned repository
    exec bash "$SCRIPT_DIR/scripts/deploy-server.sh" "$@"
else
    # Running standalone / piped via curl
    TARGET_DIR="${PLANE_INSTALL_DIR:-/opt/plane-selfhost}"
    REPO_URL="${PLANE_REPO_URL:-https://github.com/nizar-kode/plane-selfhost.git}"

    echo "=== Bootstrapping Plane Self-Hosted Deployment ==="
    echo "Installing Git and staging repository..."

    if [ "$EUID" -ne 0 ] && command -v sudo >/dev/null 2>&1; then
        SUDO="sudo"
    else
        SUDO=""
    fi

    # Ensure git and curl are available
    if ! command -v git >/dev/null 2>&1 || ! command -v curl >/dev/null 2>&1; then
        if command -v apt-get >/dev/null 2>&1; then
            $SUDO apt-get update -qq && $SUDO apt-get install -y -qq git curl
        elif command -v dnf >/dev/null 2>&1; then
            $SUDO dnf install -y git curl
        elif command -v yum >/dev/null 2>&1; then
            $SUDO yum install -y git curl
        fi
    fi

    # Clone or update
    if [ ! -d "$TARGET_DIR/.git" ]; then
        $SUDO mkdir -p "$TARGET_DIR"
        $SUDO git clone "$REPO_URL" "$TARGET_DIR"
    else
        cd "$TARGET_DIR" && $SUDO git pull origin main
    fi

    cd "$TARGET_DIR"
    $SUDO chmod +x scripts/*.sh deploy.sh || true
    exec bash "$TARGET_DIR/scripts/deploy-server.sh" "$@"
fi
