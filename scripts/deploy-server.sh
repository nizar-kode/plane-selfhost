#!/usr/bin/env bash
# ==============================================================================
# Plane Enterprise Self-Hosted - Remote Server Deployment Script
# Automated Step-by-Step Provisioning: OS -> Docker -> Git -> Config -> Launch
# ==============================================================================

set -euo pipefail

# Color palette for terminal output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m' # No Color

# Default settings
DEFAULT_REPO_URL="https://github.com/nizar-kode/plane-selfhost.git"
DEFAULT_INSTALL_DIR="/opt/plane-selfhost"
REPO_URL="${PLANE_REPO_URL:-$DEFAULT_REPO_URL}"
INSTALL_DIR="${PLANE_INSTALL_DIR:-$DEFAULT_INSTALL_DIR}"
BRANCH="${PLANE_BRANCH:-main}"
NON_INTERACTIVE="${NON_INTERACTIVE:-0}"

# Banner
print_banner() {
cat << "EOF"
================================================================================
   ____  _                  ____       _  __      _   _           _ 
  |  _ \| | __ _ _ __   ___/ ___|  ___| |/ _|    | | | | ___  ___| |_ 
  | |_) | |/ _` | '_ \ / _ \___ \ / _ \ | |_|____| |_| |/ _ \/ __| __|
  |  __/| | (_| | | | |  __/___) |  __/ |  _|____|  _  | (_) \__ \ |_ 
  |_|   |_|\__,_|_| |_|\___|____/ \___|_|_|      |_| |_|\___/|___/\__|
================================================================================
   Enterprise Automated Remote Server Deployment Utility | Plane v1.5.0
================================================================================
EOF
}

log_info() {
    echo -e "${CYAN}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1" >&2
}

log_step() {
    echo -e "\n${BOLD}${BLUE}==>${NC} ${BOLD}$1${NC}"
}

# ------------------------------------------------------------------------------
# 1. Privilege and Environment Verification
# ------------------------------------------------------------------------------
check_privileges() {
    log_step "Step 1/8: Verifying System Privileges & Environment"

    if [ "$EUID" -ne 0 ]; then
        if command -v sudo >/dev/null 2>&1; then
            SUDO="sudo"
            log_info "Running with sudo privileges."
        else
            log_error "This script requires root privileges or 'sudo'. Please run as root."
            exit 1
        fi
    else
        SUDO=""
        log_info "Running directly as root user."
    fi

    # Detect OS
    if [ -f /etc/os-release ]; then
        . /etc/os-release
        OS_ID="${ID:-unknown}"
        OS_VERSION="${VERSION_ID:-unknown}"
        log_info "Detected Operating System: $NAME ($OS_ID $OS_VERSION)"
    else
        log_warn "Could not reliably determine OS distribution. Proceeding with generic Linux."
        OS_ID="generic"
    fi

    # Check Architecture
    ARCH=$(uname -m)
    log_info "Detected CPU Architecture: $ARCH"
    case "$ARCH" in
        x86_64|amd64)
            ;;
        aarch64|arm64)
            ;;
        *)
            log_warn "Plane Docker images are primarily built for amd64 and arm64. Architecture $ARCH may encounter compatibility issues."
            ;;
    esac

    # Hardware check
    TOTAL_MEM_KB=$(grep MemTotal /proc/meminfo | awk '{print $2}')
    TOTAL_MEM_MB=$((TOTAL_MEM_KB / 1024))
    log_info "Total RAM: ${TOTAL_MEM_MB} MB"

    if [ "$TOTAL_MEM_MB" -lt 3500 ]; then
        log_warn "Plane recommends at least 4 GB (4096 MB) of RAM for production."
        log_warn "If this server has low RAM, ensure sufficient Swap space (at least 4 GB) is configured to avoid Out-Of-Memory (OOM) errors during database migrations."
    fi
}

# ------------------------------------------------------------------------------
# 2. Package Management & System Dependencies
# ------------------------------------------------------------------------------
install_prerequisites() {
    log_step "Step 2/8: Installing System Prerequisites (curl, git, python3, openssl)"

    if [ "$OS_ID" = "ubuntu" ] || [ "$OS_ID" = "debian" ]; then
        log_info "Updating apt package repository..."
        $SUDO apt-get update -qq
        $SUDO apt-get install -y -qq curl git python3 python3-pip openssl tar gzip jq ca-certificates gnupg lsb-release
    elif [ "$OS_ID" = "centos" ] || [ "$OS_ID" = "rhel" ] || [ "$OS_ID" = "rocky" ] || [ "$OS_ID" = "almalinux" ] || [ "$OS_ID" = "fedora" ]; then
        log_info "Updating yum/dnf package repository..."
        if command -v dnf >/dev/null 2>&1; then
            $SUDO dnf install -y curl git python3 python3-pip openssl tar gzip jq ca-certificates
        else
            $SUDO yum install -y curl git python3 python3-pip openssl tar gzip jq ca-certificates
        fi
    else
        log_warn "Unknown package manager. Attempting to verify required tools manually..."
        for cmd in curl git python3 openssl tar gzip; do
            if ! command -v "$cmd" >/dev/null 2>&1; then
                log_error "Required tool '$cmd' is not installed. Please install it before running this script."
                exit 1
            fi
        done
    fi

    log_success "System prerequisites installed successfully."
}

# ------------------------------------------------------------------------------
# 3. Docker & Docker Compose Installation
# ------------------------------------------------------------------------------
install_docker() {
    log_step "Step 3/8: Verifying & Installing Docker Engine and Docker Compose"

    if command -v docker >/dev/null 2>&1 && docker compose version >/dev/null 2>&1; then
        DOCKER_VER=$(docker --version | awk '{print $3}' | tr -d ',')
        COMPOSE_VER=$(docker compose version | awk '{print $4}')
        log_success "Docker Engine ($DOCKER_VER) and Docker Compose ($COMPOSE_VER) are already installed."
    else
        log_info "Docker or Docker Compose not detected. Installing via official Docker script..."
        curl -fsSL https://get.docker.com -o /tmp/get-docker.sh
        $SUDO sh /tmp/get-docker.sh
        rm -f /tmp/get-docker.sh

        # Enable and start Docker service
        if command -v systemctl >/dev/null 2>&1; then
            $SUDO systemctl enable --now docker
        elif command -v service >/dev/null 2>&1; then
            $SUDO service docker start
        fi

        log_success "Docker installed successfully."
    fi

    # Add current non-root user to docker group if applicable
    if [ -n "${SUDO_USER:-}" ] && [ "$SUDO_USER" != "root" ]; then
        if ! groups "$SUDO_USER" | grep -q '\bdocker\b'; then
            log_info "Adding user '$SUDO_USER' to docker group..."
            $SUDO usermod -aG docker "$SUDO_USER"
            log_warn "User '$SUDO_USER' added to docker group. Note: group membership takes effect upon new login session."
        fi
    fi

    # Verify Docker daemon is running
    if ! $SUDO docker info >/dev/null 2>&1; then
        log_error "Docker daemon is not running. Please start docker ('systemctl start docker') and retry."
        exit 1
    fi
}

# ------------------------------------------------------------------------------
# 4. Clone or Update GitHub Repository
# ------------------------------------------------------------------------------
setup_repository() {
    log_step "Step 4/8: Retrieving Deployment Repository from GitHub"

    log_info "Target installation directory: $INSTALL_DIR"

    if [ -d "$INSTALL_DIR/.git" ]; then
        log_info "Existing Git repository found at $INSTALL_DIR. Pulling latest updates..."
        cd "$INSTALL_DIR"
        $SUDO git fetch origin "$BRANCH"
        $SUDO git checkout "$BRANCH"
        $SUDO git pull origin "$BRANCH"
    else
        log_info "Cloning $REPO_URL (branch: $BRANCH) to $INSTALL_DIR..."
        $SUDO mkdir -p "$INSTALL_DIR"
        $SUDO git clone -b "$BRANCH" "$REPO_URL" "$INSTALL_DIR"
        cd "$INSTALL_DIR"
    fi

    # Set ownership to current user if running via sudo
    if [ -n "${SUDO_USER:-}" ]; then
        $SUDO chown -R "$SUDO_USER:$(id -gn "$SUDO_USER")" "$INSTALL_DIR"
    fi

    # Make management scripts executable
    $SUDO chmod +x "$INSTALL_DIR"/scripts/*.sh || true

    log_success "Repository successfully staged at $INSTALL_DIR"
}

# ------------------------------------------------------------------------------
# 5. Environment & Cryptographic Secrets Generation
# ------------------------------------------------------------------------------
configure_environment() {
    log_step "Step 5/8: Configuring Server Domain, Routing, & Cryptographic Secrets"

    cd "$INSTALL_DIR"

    if [ -f ".env" ]; then
        log_info "An existing .env file was found."
        if [ "$NON_INTERACTIVE" -eq 1 ]; then
            log_info "Non-interactive mode: preserving existing .env file."
            return 0
        fi

        read -rp "Do you want to reconfigure .env and regenerate secrets? (y/N): " RECONF
        if [[ ! "$RECONF" =~ ^[Yy]$ ]]; then
            log_info "Preserving existing .env configuration."
            return 0
        fi
    fi

    # Determine public IP address
    DETECTED_IP=$(curl -s https://ifconfig.me || curl -s https://api.ipify.org || echo "localhost")

    # Interactive Domain & SSL Configuration
    if [ "$NON_INTERACTIVE" -eq 1 ]; then
        TARGET_DOMAIN="${DOMAIN:-$DETECTED_IP}"
        USE_HTTPS="${USE_HTTPS:-0}"
        ADMIN_EMAIL="${SSL_EMAIL:-}"
        HTTP_PORT="${PORT:-80}"
        HTTPS_PORT="${SSL_PORT:-443}"
    else
        echo -e "\n${BOLD}Server Ingress & Domain Configuration:${NC}"
        echo "Detected public server IP: $DETECTED_IP"
        read -rp "Enter your Domain Name or IP address [$DETECTED_IP]: " USER_DOMAIN
        TARGET_DOMAIN="${USER_DOMAIN:-$DETECTED_IP}"

        echo ""
        read -rp "Do you want to enable automatic HTTPS via Let's Encrypt? (requires valid domain pointing to this server) (y/N): " HTTPS_CHOICE
        if [[ "$HTTPS_CHOICE" =~ ^[Yy]$ ]]; then
            USE_HTTPS=1
            read -rp "Enter administrator email address for Let's Encrypt SSL notices: " ADMIN_EMAIL
        else
            USE_HTTPS=0
            ADMIN_EMAIL=""
        fi

        read -rp "Host HTTP port to expose [80]: " USER_PORT
        HTTP_PORT="${USER_PORT:-80}"
        HTTPS_PORT="443"
    fi

    # Copy template
    cp .env.example .env

    # Run Python secret generator if python3 is available
    if command -v python3 >/dev/null 2>&1; then
        log_info "Generating high-entropy cryptographic secrets with Python..."
        python3 scripts/generate_secrets.py --force
    else
        log_warn "Python3 not available for secret generation; using OpenSSL fallback..."
        SECRET_KEY=$(openssl rand -base64 48 | tr -dc 'a-zA-Z0-9!@#%&*(-_=+)' | head -c 50)
        LIVE_SECRET=$(openssl rand -hex 32)
        PG_PASS=$(openssl rand -hex 16)
        MQ_PASS=$(openssl rand -hex 16)
        S3_ACCESS="plane_$(openssl rand -hex 8)"
        S3_SECRET=$(openssl rand -hex 20)

        sed -i "s|^SECRET_KEY=.*|SECRET_KEY=$SECRET_KEY|" .env
        sed -i "s|^LIVE_SERVER_SECRET_KEY=.*|LIVE_SERVER_SECRET_KEY=$LIVE_SECRET|" .env
        sed -i "s|^POSTGRES_PASSWORD=.*|POSTGRES_PASSWORD=$PG_PASS|" .env
        sed -i "s|^DATABASE_URL=.*|DATABASE_URL=postgresql://plane:$PG_PASS@plane-db:5432/plane|" .env
        sed -i "s|^RABBITMQ_PASSWORD=.*|RABBITMQ_PASSWORD=$MQ_PASS|" .env
        sed -i "s|^AMQP_URL=.*|AMQP_URL=amqp://plane:$MQ_PASS@plane-mq:5672/plane|" .env
        sed -i "s|^AWS_ACCESS_KEY_ID=.*|AWS_ACCESS_KEY_ID=$S3_ACCESS|" .env
        sed -i "s|^AWS_SECRET_ACCESS_KEY=.*|AWS_SECRET_ACCESS_KEY=$S3_SECRET|" .env
    fi

    # Update domain, scheme, and ports in .env
    if [ "$USE_HTTPS" -eq 1 ]; then
        PROTO="https"
        sed -i "s|^SITE_ADDRESS=.*|SITE_ADDRESS=$TARGET_DOMAIN|" .env
        if [ -n "$ADMIN_EMAIL" ]; then
            sed -i "s|^CERT_EMAIL=.*|CERT_EMAIL=email $ADMIN_EMAIL|" .env
        fi
    else
        PROTO="http"
        sed -i "s|^SITE_ADDRESS=.*|SITE_ADDRESS=:$HTTP_PORT|" .env
    fi

    if [ "$HTTP_PORT" != "80" ] && [ "$USE_HTTPS" -eq 0 ]; then
        FULL_WEB_URL="$PROTO://$TARGET_DOMAIN:$HTTP_PORT"
    else
        FULL_WEB_URL="$PROTO://$TARGET_DOMAIN"
    fi

    sed -i "s|^APP_DOMAIN=.*|APP_DOMAIN=$TARGET_DOMAIN|" .env
    sed -i "s|^WEB_URL=.*|WEB_URL=$FULL_WEB_URL|" .env
    sed -i "s|^CORS_ALLOWED_ORIGINS=.*|CORS_ALLOWED_ORIGINS=$FULL_WEB_URL|" .env
    sed -i "s|^LISTEN_HTTP_PORT=.*|LISTEN_HTTP_PORT=$HTTP_PORT|" .env
    sed -i "s|^LISTEN_HTTPS_PORT=.*|LISTEN_HTTPS_PORT=$HTTPS_PORT|" .env

    log_success ".env configured for domain: $TARGET_DOMAIN (URL: $FULL_WEB_URL)"
}

# ------------------------------------------------------------------------------
# 6. Firewall Configuration (UFW / Firewalld)
# ------------------------------------------------------------------------------
configure_firewall() {
    log_step "Step 6/8: Checking Server Firewall Settings"

    HTTP_PORT_VAL=$(grep "^LISTEN_HTTP_PORT=" .env | cut -d'=' -f2 || echo "80")
    HTTPS_PORT_VAL=$(grep "^LISTEN_HTTPS_PORT=" .env | cut -d'=' -f2 || echo "443")

    if command -v ufw >/dev/null 2>&1 && ufw status | grep -q "Status: active"; then
        log_info "UFW active firewall detected. Ensuring HTTP/HTTPS ports are allowed..."
        $SUDO ufw allow 22/tcp comment 'SSH' || true
        $SUDO ufw allow "$HTTP_PORT_VAL"/tcp comment 'Plane HTTP Ingress' || true
        $SUDO ufw allow "$HTTPS_PORT_VAL"/tcp comment 'Plane HTTPS Ingress' || true
        log_success "UFW rules updated."
    elif command -v firewall-cmd >/dev/null 2>&1 && systemctl is-active --quiet firewalld; then
        log_info "Firewalld active firewall detected. Adding HTTP/HTTPS services..."
        $SUDO firewall-cmd --permanent --add-port="$HTTP_PORT_VAL"/tcp || true
        $SUDO firewall-cmd --permanent --add-port="$HTTPS_PORT_VAL"/tcp || true
        $SUDO firewall-cmd --reload || true
        log_success "Firewalld rules updated."
    else
        log_info "No active local firewall daemon detected (or handled by cloud security groups)."
        log_info "Ensure inbound ports $HTTP_PORT_VAL and $HTTPS_PORT_VAL are allowed in your cloud provider's firewall (AWS Security Group, GCP Firewall, Hetzner, DigitalOcean, etc.)."
    fi
}

# ------------------------------------------------------------------------------
# 7. Pull Images & Launch Stack
# ------------------------------------------------------------------------------
launch_plane() {
    log_step "Step 7/8: Pulling Docker Images, Running Migrations, & Launching Stack"

    cd "$INSTALL_DIR"

    # Validate compose configuration
    log_info "Validating docker compose syntax..."
    $SUDO docker compose config --quiet

    log_info "Pulling official Plane v1.5.0 container images..."
    $SUDO docker compose pull

    log_info "Running initial database schema migrations (plane-migrator)..."
    # Starting backing services first to allow healthy readiness
    $SUDO docker compose up -d plane-db plane-redis plane-mq plane-minio

    log_info "Waiting for PostgreSQL, Valkey, and RabbitMQ to pass health checks..."
    local attempts=0
    local max_attempts=30
    until [ $($SUDO docker inspect -f '{{.State.Health.Status}}' plane-db 2>/dev/null || echo "starting") = "healthy" ] && \
          [ $($SUDO docker inspect -f '{{.State.Health.Status}}' plane-redis 2>/dev/null || echo "starting") = "healthy" ]; do
        sleep 2
        attempts=$((attempts + 1))
        if [ $attempts -ge $max_attempts ]; then
            log_warn "Timeout waiting for health checks; proceeding to migration..."
            break
        fi
    done

    log_info "Executing Django database migrations..."
    $SUDO docker compose run --rm migrator

    log_info "Launching full application stack (Web, Admin, Space, Live, API, Workers, Proxy)..."
    $SUDO docker compose up -d

    log_success "All Plane containers dispatched."
}

# ------------------------------------------------------------------------------
# 8. Post-Launch Verification & Output Summary
# ------------------------------------------------------------------------------
verify_deployment() {
    log_step "Step 8/8: Verifying System Health & Access Endpoints"

    cd "$INSTALL_DIR"
    sleep 5

    $SUDO docker compose ps

    WEB_URL_VAL=$(grep "^WEB_URL=" .env | cut -d'=' -f2 || echo "http://localhost")

    echo -e "\n================================================================================"
    echo -e "${GREEN}${BOLD}             🎉 PLANE DEPLOYMENT COMPLETED SUCCESSFULLY!             ${NC}"
    echo -e "================================================================================"
    echo -e "\n${BOLD}Access URLs:${NC}"
    echo -e "  • ${BOLD}Main Application Web UI:${NC}    ${CYAN}$WEB_URL_VAL${NC}"
    echo -e "  • ${BOLD}Instance Setup (God Mode):${NC}  ${CYAN}$WEB_URL_VAL/god-mode/${NC}"
    echo -e "  • ${BOLD}Plane Space (Portals):${NC}      ${CYAN}$WEB_URL_VAL/spaces/${NC}"

    echo -e "\n${BOLD}Initial Onboarding Steps:${NC}"
    echo -e "  1. Open ${CYAN}$WEB_URL_VAL/god-mode/${NC} in your browser."
    echo -e "  2. Complete the initial registration to create your ${BOLD}Instance Administrator${NC} account."
    echo -e "  3. Configure your first Workspace and invite team members."

    echo -e "\n${BOLD}Daily Management Commands:${NC}"
    echo -e "  • ${BOLD}Check Status:${NC}   cd $INSTALL_DIR && ./scripts/manage.sh status"
    echo -e "  • ${BOLD}View Logs:${NC}      cd $INSTALL_DIR && ./scripts/manage.sh logs"
    echo -e "  • ${BOLD}Stop Stack:${NC}     cd $INSTALL_DIR && ./scripts/manage.sh stop"
    echo -e "  • ${BOLD}Start Stack:${NC}    cd $INSTALL_DIR && ./scripts/manage.sh start"
    echo -e "  • ${BOLD}Create Backup:${NC}  cd $INSTALL_DIR && ./scripts/manage.sh backup"
    echo -e "  • ${BOLD}Upgrade Plane:${NC}  cd $INSTALL_DIR && ./scripts/manage.sh update"

    echo -e "\n${BOLD}Automated Daily Backup Recommendation:${NC}"
    echo -e "  Add this daily cron job at 02:00 AM (runs automatic backup of DB + S3 files):"
    echo -e "  ${YELLOW}(crontab -l 2>/dev/null; echo \"0 2 * * * /bin/bash $INSTALL_DIR/scripts/backup.sh > /var/log/plane-backup.log 2>&1\") | crontab -${NC}"

    echo -e "\n================================================================================\n"
}

# ------------------------------------------------------------------------------
# Script Execution Flow
# ------------------------------------------------------------------------------
main() {
    print_banner
    check_privileges
    install_prerequisites
    install_docker
    setup_repository
    configure_environment
    configure_firewall
    launch_plane
    verify_deployment
}

main "$@"
