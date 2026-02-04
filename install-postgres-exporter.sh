#!/bin/bash

# Automatic Postgres Exporter Installation Script
# Based on: https://github.com/prometheus-community/postgres_exporter
#
# Usage:
#   curl -fsSL https://github.com/kekedaine/ops-scripts/blob/main/install-postgres-exporter.sh | sudo bash -s uninstall_old_service
#   curl -fsSL https://github.com/kekedaine/ops-scripts/blob/main/install-postgres-exporter.sh | sudo POSTGRES_EXPORTER_PORT=9999 bash
#
# Parameters:
#   uninstall_old_service - Remove existing postgres_exporter service before installation

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Logging functions
log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Check root privileges
if [[ $EUID -ne 0 ]]; then
   log_error "This script must be run as root"
   exit 1
fi

# Default configuration
POSTGRES_EXPORTER_VERSION=$(curl -s https://api.github.com/repos/prometheus-community/postgres_exporter/releases/latest | grep '"tag_name":' | sed -E 's/.*"v([^"]+)".*/\1/')
POSTGRES_EXPORTER_PORT=${POSTGRES_EXPORTER_PORT:-9187}
POSTGRES_USER=${POSTGRES_USER:-postgres}
POSTGRES_PASSWORD=${POSTGRES_PASSWORD:-$(openssl rand -base64 32)}
POSTGRES_HOST=${POSTGRES_HOST:-localhost}
POSTGRES_PORT=${POSTGRES_PORT:-5432}
POSTGRES_DB=${POSTGRES_DB:-postgres}
UNINSTALL_OLD_SERVICE=${1:-false}

log_info "Postgres Exporter version: $POSTGRES_EXPORTER_VERSION"
log_info "Exporter port: $POSTGRES_EXPORTER_PORT"
log_info "Generated password: $POSTGRES_PASSWORD"

# Handle uninstall parameter
if [[ "$1" == "uninstall_old_service" ]]; then
    UNINSTALL_OLD_SERVICE=true
    log_info "Mode: Uninstall old service enabled"
fi

# Check if port is already in use
if lsof -i:$POSTGRES_EXPORTER_PORT > /dev/null 2>&1; then
    log_error "Port $POSTGRES_EXPORTER_PORT is already in use. Please choose another port."
    exit 1
fi

# Check if PostgreSQL is running
if ! systemctl is-active --quiet postgresql; then
    log_error "PostgreSQL service is not running. Please start PostgreSQL first."
    exit 1
fi

# Function to check and remove old service
check_and_remove_old_service() {
    log_info "Checking for existing postgres_exporter service..."

    # Check if service exists
    if systemctl list-units --full -all | grep -Fq "postgres_exporter.service"; then
        log_warn "Found existing postgres_exporter service"

        if [[ "$UNINSTALL_OLD_SERVICE" == "true" ]]; then
            log_info "Removing old service..."

            # Stop service
            if systemctl is-active --quiet postgres_exporter; then
                log_info "Stopping postgres_exporter service..."
                sudo systemctl stop postgres_exporter
            fi

            # Disable service
            if systemctl is-enabled --quiet postgres_exporter; then
                log_info "Disabling postgres_exporter service..."
                sudo systemctl disable postgres_exporter
            fi

            # Remove service file
            if [[ -f "/etc/systemd/system/postgres_exporter.service" ]]; then
                log_info "Removing old service file..."
                sudo rm -f /etc/systemd/system/postgres_exporter.service
            fi

            # Reload systemd
            sudo systemctl daemon-reload
            sudo systemctl reset-failed

            log_info "Old service has been removed"
        else
            log_error "postgres_exporter service already exists. Use 'uninstall_old_service' parameter to remove old service:"
            log_error "curl -fsSL <script_url> | sudo bash -s uninstall_old_service"
            exit 1
        fi
    else
        log_info "No existing service found"
    fi
}

# Function to check and remove old binary
check_and_remove_old_binary() {
    if [[ -f "/usr/local/bin/postgres_exporter" ]]; then
        log_warn "Found existing postgres_exporter binary"

        if [[ "$UNINSTALL_OLD_SERVICE" == "true" ]]; then
            log_info "Removing old binary..."
            sudo rm -f /usr/local/bin/postgres_exporter
            log_info "Old binary has been removed"
        else
            log_info "Old binary will be overwritten"
        fi
    fi
}

# Function to check and backup old configuration
check_and_backup_old_config() {
    if [[ -d "/etc/postgres_exporter" ]]; then
        log_warn "Found existing configuration directory"

        if [[ "$UNINSTALL_OLD_SERVICE" == "true" ]]; then
            # Backup old configuration
            BACKUP_DIR="/etc/postgres_exporter.backup.$(date +%Y%m%d_%H%M%S)"
            log_info "Backing up old configuration to: $BACKUP_DIR"
            sudo cp -r /etc/postgres_exporter "$BACKUP_DIR"

            # Remove old configuration
            log_info "Removing old configuration..."
            sudo rm -rf /etc/postgres_exporter
            log_info "Old configuration has been backed up and removed"
        else
            log_info "Old configuration will be overwritten"
        fi
    fi
}

# Function to download postgres_exporter
download_postgres_exporter() {
    log_info "Downloading Postgres Exporter v${POSTGRES_EXPORTER_VERSION}..."

    cd /tmp
    curl -LO "https://github.com/prometheus-community/postgres_exporter/releases/download/v${POSTGRES_EXPORTER_VERSION}/postgres_exporter-${POSTGRES_EXPORTER_VERSION}.linux-amd64.tar.gz"

    tar -xzf postgres_exporter-${POSTGRES_EXPORTER_VERSION}.linux-amd64.tar.gz
    sudo mv postgres_exporter-${POSTGRES_EXPORTER_VERSION}.linux-amd64/postgres_exporter /usr/local/bin/
    sudo chmod +x /usr/local/bin/postgres_exporter

    # Cleanup
    rm -rf postgres_exporter-${POSTGRES_EXPORTER_VERSION}.linux-amd64.tar.gz postgres_exporter-${POSTGRES_EXPORTER_VERSION}.linux-amd64

    log_info "Postgres Exporter binary has been installed"
}

# Function to create postgres_exporter system user
create_postgres_exporter_user() {
    log_info "Creating system user postgres_exporter..."

    if id "postgres_exporter" &>/dev/null; then
        log_warn "User postgres_exporter already exists"
    else
        sudo useradd --no-create-home --shell /bin/false postgres_exporter
        log_info "User postgres_exporter has been created"
    fi
}

# Function to create database user for exporter
create_database_user() {
    log_info "Creating database user exporter..."

    # Create exporter user in PostgreSQL
    sudo -u postgres psql << EOF
-- Create user if not exists
DO \$\$
BEGIN
    IF NOT EXISTS (SELECT FROM pg_catalog.pg_roles WHERE rolname = 'exporter') THEN
        CREATE USER exporter WITH PASSWORD '$POSTGRES_PASSWORD';
        RAISE NOTICE 'User exporter created';
    ELSE
        ALTER USER exporter WITH PASSWORD '$POSTGRES_PASSWORD';
        RAISE NOTICE 'User exporter password updated';
    END IF;
END
\$\$;

-- Grant permissions
ALTER ROLE exporter INHERIT;
GRANT pg_monitor TO exporter;

-- Create extension if not exists
CREATE EXTENSION IF NOT EXISTS pg_stat_statements;

\q
EOF

    log_info "Database user exporter has been created with pg_monitor privileges"
}

# Function to create environment file
create_environment_file() {
    log_info "Creating environment file..."

    sudo mkdir -p /etc/postgres_exporter

    # Create DATA_SOURCE_NAME
    DATA_SOURCE_NAME="postgresql://exporter:${POSTGRES_PASSWORD}@${POSTGRES_HOST}:${POSTGRES_PORT}/${POSTGRES_DB}?sslmode=disable"

    sudo tee /etc/postgres_exporter/.env > /dev/null << EOF
# Postgres Exporter Environment Variables
DATA_SOURCE_NAME="${DATA_SOURCE_NAME}"

# Optional: Enable specific collectors
# PG_EXPORTER_DISABLE_DEFAULT_METRICS=false
# PG_EXPORTER_DISABLE_SETTINGS_METRICS=false

# Web configuration
PG_EXPORTER_WEB_TELEMETRY_PATH=/metrics
EOF

    sudo chown -R postgres_exporter:postgres_exporter /etc/postgres_exporter
    sudo chmod 600 /etc/postgres_exporter/.env

    log_info "Environment file has been created at /etc/postgres_exporter/.env"
}

# Function to create systemd service
create_systemd_service() {
    log_info "Creating systemd service..."

    sudo tee /etc/systemd/system/postgres_exporter.service > /dev/null << EOF
[Unit]
Description=Prometheus Postgres Exporter
After=network.target postgresql.service
Wants=postgresql.service

[Service]
Type=simple
User=postgres_exporter
Group=postgres_exporter
EnvironmentFile=/etc/postgres_exporter/.env
ExecStart=/usr/local/bin/postgres_exporter --collector.stat_statements --web.listen-address=:$POSTGRES_EXPORTER_PORT
Restart=always
RestartSec=5
TimeoutStopSec=20

[Install]
WantedBy=multi-user.target
EOF

    log_info "Systemd service has been created"
}

# Function to start service
start_service() {
    log_info "Starting Postgres Exporter service..."

    sudo systemctl daemon-reload
    sudo systemctl enable postgres_exporter.service
    sudo systemctl start postgres_exporter.service

    # Wait for service to start
    sleep 3

    if systemctl is-active --quiet postgres_exporter; then
        log_info "Postgres Exporter service has started successfully"

        # Get actual port
        ACTUAL_PORT=$(sudo netstat -tlnp | grep postgres_exporter | awk '{print $4}' | cut -d: -f2 | head -1)
        log_info "Service is running on port: $ACTUAL_PORT"

        # Test metrics endpoint
        log_info "Testing metrics endpoint..."
        if curl -s "http://localhost:$ACTUAL_PORT/metrics" | head -5; then
            log_info "Metrics endpoint is working properly"
        else
            log_warn "Cannot test metrics endpoint"
        fi
    else
        log_error "Postgres Exporter service failed to start"
        sudo systemctl status postgres_exporter
        exit 1
    fi
}

# Function to display installation information
show_info() {
    log_info "=== INSTALLATION INFORMATION ==="
    echo "Postgres Exporter Version: $POSTGRES_EXPORTER_VERSION"
    echo "Service Port: $POSTGRES_EXPORTER_PORT"
    echo "Database User: exporter"
    echo "Database Password: $POSTGRES_PASSWORD"
    echo "Metrics URL: http://localhost:$POSTGRES_EXPORTER_PORT/metrics"
    echo ""
    echo "=== CHECK COMMANDS ==="
    echo "sudo systemctl status postgres_exporter"
    echo "curl http://localhost:$POSTGRES_EXPORTER_PORT/metrics"
    echo ""
    echo "=== CONFIGURATION FILES ==="
    echo "Environment: /etc/postgres_exporter/.env"
    echo "Service: /etc/systemd/system/postgres_exporter.service"
    echo ""
    echo "=== SCRIPT USAGE ==="
    echo "New installation:     curl -fsSL <script_url> | sudo bash"
    echo "Override service:     curl -fsSL <script_url> | sudo bash -s uninstall_old_service"
    echo ""
    log_warn "Save database password: $POSTGRES_PASSWORD"
}

# Main installation flow
main() {
    log_info "Starting Postgres Exporter installation..."

    # Check and handle old installation
    check_and_remove_old_service
    check_and_remove_old_binary
    check_and_backup_old_config

    download_postgres_exporter
    create_postgres_exporter_user
    create_database_user
    create_environment_file
    create_systemd_service
    start_service
    show_info

    log_info "Installation completed!"
}

# Execute script
main "$@"