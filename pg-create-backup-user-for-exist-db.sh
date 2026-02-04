#!/bin/bash

# Script tự động tạo PostgreSQL Backup User cho Database có sẵn
# Usage: ./pg-create-backup-user-for-exist-db.sh <existing_db_name> <backup_user_name>
# Cách dùng (example):
#   ./pg-create-backup-user-for-exist-db.sh <existing_db_name> <backup_user_name>
#
# Hoặc chạy trực tiếp bằng curl (không cần tải file về):
#   curl -fsSL https://raw.githubusercontent.com/kekedaine/ops-scripts/refs/heads/main/pg-create-backup-user-for-exist-db.sh | bash -s <existing_db_name> <backup_user_name>
#
# Ví dụ:
#   curl -fsSL https://raw.githubusercontent.com/kekedaine/ops-scripts/refs/heads/main/pg-create-backup-user-for-exist-db.sh | bash -s mydb backup_user

set -e

# Colors
GREEN='\033[0;32m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info() { echo -e "${GREEN}[INFO]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }
log_note() { echo -e "${BLUE}[NOTE]${NC} $1"; }

# Check parameters
if [ $# -ne 2 ]; then
    log_error "Usage: $0 <existing_db_name> <backup_user_name>"
    exit 1
fi

DB_NAME=$1
BACKUP_USER=$2

# Validate names
if [[ ! $DB_NAME =~ ^[a-zA-Z][a-zA-Z0-9_]*$ ]] || [[ ! $BACKUP_USER =~ ^[a-zA-Z][a-zA-Z0-9_]*$ ]]; then
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
if sudo -u postgres psql -t -c "SELECT 1 FROM pg_roles WHERE rolname='$BACKUP_USER'" | grep -q 1; then
    log_error "User '$BACKUP_USER' already exists"
    exit 1
fi

log_info "Creating backup user '$BACKUP_USER' for database '$DB_NAME'..."

# Create backup user with necessary privileges
sudo -u postgres psql << EOF
-- Create backup user
CREATE USER $BACKUP_USER WITH PASSWORD '$PASSWORD';

-- Grant connect privilege
GRANT CONNECT ON DATABASE $DB_NAME TO $BACKUP_USER;

-- Connect to the database to set up backup privileges
\c $DB_NAME

-- Grant usage on schema
GRANT USAGE ON SCHEMA public TO $BACKUP_USER;

-- Grant SELECT on all existing tables (for backup)
GRANT SELECT ON ALL TABLES IN SCHEMA public TO $BACKUP_USER;

-- Grant SELECT on all existing sequences (for backup)
GRANT SELECT ON ALL SEQUENCES IN SCHEMA public TO $BACKUP_USER;

-- Grant default privileges for future tables and sequences
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT SELECT ON TABLES TO $BACKUP_USER;
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT SELECT ON SEQUENCES TO $BACKUP_USER;

-- Grant pg_dump privileges (needed for backup operations)
GRANT pg_read_all_data TO $BACKUP_USER;
EOF

# Test connection
if PGPASSWORD="$PASSWORD" psql -h localhost -U "$BACKUP_USER" -d "$DB_NAME" -c "SELECT 1;" > /dev/null 2>&1; then
    log_info "✅ Backup user creation successful!"
    echo ""
    echo "Database: $DB_NAME"
    echo "Backup User: $BACKUP_USER"
    echo "Password: $PASSWORD"
    echo "Private IP: $PRIVATE_IP"
    echo ""
    echo "Local Connection: postgresql://$BACKUP_USER:$PASSWORD@localhost:5432/$DB_NAME"
    echo "Remote Connection: postgresql://$BACKUP_USER:$PASSWORD@$PRIVATE_IP:5432/$DB_NAME"
    echo ""
    echo "Test Local: psql -h localhost -U $BACKUP_USER -d $DB_NAME"
    echo "Test Remote: psql -h $PRIVATE_IP -U $BACKUP_USER -d $DB_NAME"
    echo ""
    log_note "Backup Commands:"
    echo "Local Backup: pg_dump -h localhost -U $BACKUP_USER -d $DB_NAME > backup.sql"
    echo "Remote Backup: pg_dump -h $PRIVATE_IP -U $BACKUP_USER -d $DB_NAME > backup.sql"
    echo "With Password: PGPASSWORD='$PASSWORD' pg_dump -h localhost -U $BACKUP_USER -d $DB_NAME > backup.sql"
else
    log_error "Connection test failed"
    exit 1
fi