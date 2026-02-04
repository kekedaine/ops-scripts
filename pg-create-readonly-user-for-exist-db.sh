#!/bin/bash

# Script tự động tạo PostgreSQL Readonly User cho Database có sẵn
# Usage: ./pg-create-readonly-user-for-exist-db.sh <existing_db_name> <readonly_user_name>
# Cách dùng (example):
#   ./pg-create-readonly-user-for-exist-db.sh <existing_db_name> <readonly_user_name>
#
# Hoặc chạy trực tiếp bằng curl (không cần tải file về):
#   curl -fsSL https://raw.githubusercontent.com/kekedaine/ops-scripts/refs/heads/main/pg-create-readonly-user-for-exist-db.sh | bash -s <existing_db_name> <readonly_user_name>
#
# Ví dụ:
#   curl -fsSL https://raw.githubusercontent.com/kekedaine/ops-scripts/refs/heads/main/pg-create-readonly-user-for-exist-db.sh | bash -s mydb readonly_user

set -e

# Colors
GREEN='\033[0;32m'
RED='\033[0;31m'
CYAN='\033[0;36m'
NC='\033[0m'

log_info() { echo -e "${GREEN}[INFO]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }
log_note() { echo -e "${CYAN}[NOTE]${NC} $1"; }

# Check parameters
if [ $# -ne 2 ]; then
    log_error "Usage: $0 <existing_db_name> <readonly_user_name>"
    exit 1
fi

DB_NAME=$1
READONLY_USER=$2

# Validate names
if [[ ! $DB_NAME =~ ^[a-zA-Z][a-zA-Z0-9_]*$ ]] || [[ ! $READONLY_USER =~ ^[a-zA-Z][a-zA-Z0-9_]*$ ]]; then
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

# Check if database exists
if ! sudo -u postgres psql -lqt | cut -d \| -f 1 | grep -qw "$DB_NAME"; then
    log_error "Database '$DB_NAME' does not exist"
    exit 1
fi

# Check if user already exists
if sudo -u postgres psql -t -c "SELECT 1 FROM pg_roles WHERE rolname='$READONLY_USER'" | grep -q 1; then
    log_error "User '$READONLY_USER' already exists"
    exit 1
fi

log_info "Creating readonly user '$READONLY_USER' for database '$DB_NAME'..."

# Create readonly user with SELECT-only privileges
sudo -u postgres psql << EOF
-- Create readonly user
CREATE USER $READONLY_USER WITH PASSWORD '$PASSWORD';

-- Grant connect privilege
GRANT CONNECT ON DATABASE $DB_NAME TO $READONLY_USER;

-- Connect to the database to set up readonly privileges
\c $DB_NAME

-- Grant usage on schema (required to access objects)
GRANT USAGE ON SCHEMA public TO $READONLY_USER;

-- Grant SELECT on all existing tables
GRANT SELECT ON ALL TABLES IN SCHEMA public TO $READONLY_USER;

-- Grant SELECT on all existing sequences (for reading sequence values)
GRANT SELECT ON ALL SEQUENCES IN SCHEMA public TO $READONLY_USER;

-- Grant default privileges for future tables and sequences
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT SELECT ON TABLES TO $READONLY_USER;
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT SELECT ON SEQUENCES TO $READONLY_USER;

-- Explicitly revoke any write privileges (safety measure)
REVOKE INSERT, UPDATE, DELETE, TRUNCATE ON ALL TABLES IN SCHEMA public FROM $READONLY_USER;
REVOKE USAGE, UPDATE ON ALL SEQUENCES IN SCHEMA public FROM $READONLY_USER;
REVOKE CREATE ON SCHEMA public FROM $READONLY_USER;
EOF

# Test connection and readonly access
if PGPASSWORD="$PASSWORD" psql -h localhost -U "$READONLY_USER" -d "$DB_NAME" -c "SELECT 1;" > /dev/null 2>&1; then
    log_info "✅ Readonly user creation successful!"
    echo ""
    echo "Database: $DB_NAME"
    echo "Readonly User: $READONLY_USER"
    echo "Password: $PASSWORD"
    echo "Private IP: $PRIVATE_IP"
    echo ""
    echo "Local Connection: postgresql://$READONLY_USER:$PASSWORD@localhost:5432/$DB_NAME"
    echo "Remote Connection: postgresql://$READONLY_USER:$PASSWORD@$PRIVATE_IP:5432/$DB_NAME"
    echo ""
    echo "Test Local: psql -h localhost -U $READONLY_USER -d $DB_NAME"
    echo "Test Remote: psql -h $PRIVATE_IP -U $READONLY_USER -d $DB_NAME"
    echo ""
    log_note "Readonly Access - Allowed Operations:"
    echo "✅ SELECT queries"
    echo "✅ Reading table data"
    echo "✅ Reading sequence values"
    echo ""
    log_note "Readonly Access - Restricted Operations:"
    echo "❌ INSERT, UPDATE, DELETE"
    echo "❌ CREATE, DROP, ALTER"
    echo "❌ TRUNCATE, COPY (write mode)"
else
    log_error "Connection test failed"
    exit 1
fi