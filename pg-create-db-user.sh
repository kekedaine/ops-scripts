#!/bin/bash

# Script tự động tạo PostgreSQL Database và User
# Usage: ./create-db-user.sh <db_name> <user_name>
# Cách dùng (example):
#   ./create-db-user.sh <db_name> <user_name>
#
# Hoặc chạy trực tiếp bằng curl (không cần tải file về):
#   curl -fsSL https://raw.githubusercontent.com/kekedaine/ops-scripts/refs/heads/main/pg-create-db-user.sh | bash -s <db_name> <user_name>
#
# Ví dụ:
#   curl -fsSL https://raw.githubusercontent.com/kekedaine/ops-scripts/refs/heads/main/pg-create-db-user.sh | bash -s mydb myuser


set -e

# Colors
GREEN='\033[0;32m'
RED='\033[0;31m'
NC='\033[0m'

log_info() { echo -e "${GREEN}[INFO]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }

# Check parameters
if [ $# -ne 2 ]; then
    log_error "Usage: $0 <db_name> <user_name>"
    exit 1
fi

DB_NAME=$1
USER_NAME=$2

# Validate names
if [[ ! $DB_NAME =~ ^[a-zA-Z][a-zA-Z0-9_]*$ ]] || [[ ! $USER_NAME =~ ^[a-zA-Z][a-zA-Z0-9_]*$ ]]; then
    log_error "Names must start with letter and contain only letters, numbers, underscores"
    exit 1
fi

# Generate password
PASSWORD=$(openssl rand -base64 20 | tr -d "=+/" | cut -c1-16)

# Get private IP
PRIVATE_IP=$(hostname -I | awk '{print $1}')

# Check PostgreSQL is running
if ! systemctl is-active --quiet postgresql; then
    log_error "PostgreSQL is not running"
    exit 1
fi

# Check if database/user exists
if sudo -u postgres psql -lqt | cut -d \| -f 1 | grep -qw "$DB_NAME"; then
    log_error "Database '$DB_NAME' already exists"
    exit 1
fi

if sudo -u postgres psql -t -c "SELECT 1 FROM pg_roles WHERE rolname='$USER_NAME'" | grep -q 1; then
    log_error "User '$USER_NAME' already exists"
    exit 1
fi

log_info "Creating database and user..."

# Create database and user
sudo -u postgres psql << EOF
CREATE DATABASE $DB_NAME ENCODING 'UTF8';
CREATE USER $USER_NAME WITH PASSWORD '$PASSWORD';
GRANT CONNECT ON DATABASE $DB_NAME TO $USER_NAME;
\c $DB_NAME
GRANT USAGE, CREATE ON SCHEMA public TO $USER_NAME;
GRANT ALL PRIVILEGES ON ALL TABLES IN SCHEMA public TO $USER_NAME;
GRANT ALL PRIVILEGES ON ALL SEQUENCES IN SCHEMA public TO $USER_NAME;
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL PRIVILEGES ON TABLES TO $USER_NAME;
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL PRIVILEGES ON SEQUENCES TO $USER_NAME;
EOF

# Test connection
if PGPASSWORD="$PASSWORD" psql -h localhost -U "$USER_NAME" -d "$DB_NAME" -c "SELECT 1;" > /dev/null 2>&1; then
    log_info "✅ Creation successful!"
    echo ""
    echo "Database: $DB_NAME"
    echo "Username: $USER_NAME"
    echo "Password: $PASSWORD"
    echo "Private IP: $PRIVATE_IP"
    echo ""
    echo "Local Connection: postgresql://$USER_NAME:$PASSWORD@localhost:5432/$DB_NAME"
    echo "Remote Connection: postgresql://$USER_NAME:$PASSWORD@$PRIVATE_IP:5432/$DB_NAME"
    echo ""
    echo "Test Local: psql -h localhost -U $USER_NAME -d $DB_NAME"
    echo "Test Remote: psql -h $PRIVATE_IP -U $USER_NAME -d $DB_NAME"
else
    log_error "Connection test failed"
    exit 1
fi