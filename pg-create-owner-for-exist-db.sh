#!/bin/bash

# Script tự động tạo PostgreSQL Owner User cho Database có sẵn
# Usage: ./pg-create-owner-for-exist-db.sh <existing_db_name> <new_owner_name>
# Cách dùng (example):
#   ./pg-create-owner-for-exist-db.sh <existing_db_name> <new_owner_name>
#
# Hoặc chạy trực tiếp bằng curl (không cần tải file về):
#   curl -fsSL https://raw.githubusercontent.com/kekedaine/ops-scripts/refs/heads/main/pg-create-owner-for-exist-db.sh | bash -s <existing_db_name> <new_owner_name>
#
# Ví dụ:
#   curl -fsSL https://raw.githubusercontent.com/kekedaine/ops-scripts/refs/heads/main/pg-create-owner-for-exist-db.sh | bash -s mydb myowner

set -e

# Colors
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m'

log_info() { echo -e "${GREEN}[INFO]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }
log_warning() { echo -e "${YELLOW}[WARNING]${NC} $1"; }

# Check parameters
if [ $# -ne 2 ]; then
    log_error "Usage: $0 <existing_db_name> <new_owner_name>"
    exit 1
fi

DB_NAME=$1
OWNER_NAME=$2

# Validate names
if [[ ! $DB_NAME =~ ^[a-zA-Z][a-zA-Z0-9_]*$ ]] || [[ ! $OWNER_NAME =~ ^[a-zA-Z][a-zA-Z0-9_]*$ ]]; then
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
if sudo -u postgres psql -t -c "SELECT 1 FROM pg_roles WHERE rolname='$OWNER_NAME'" | grep -q 1; then
    log_error "User '$OWNER_NAME' already exists"
    exit 1
fi

# Get current database owner
CURRENT_OWNER=$(sudo -u postgres psql -t -c "SELECT pg_catalog.pg_get_userbyid(d.datdba) FROM pg_catalog.pg_database d WHERE d.datname = '$DB_NAME';" | xargs)

log_info "Database '$DB_NAME' currently owned by: $CURRENT_OWNER"
log_info "Creating new owner user '$OWNER_NAME'..."

# Create owner user and transfer ownership
sudo -u postgres psql << EOF
-- Create new owner user
CREATE USER $OWNER_NAME WITH PASSWORD '$PASSWORD';

-- Grant necessary privileges to new owner
GRANT CONNECT ON DATABASE $DB_NAME TO $OWNER_NAME;

-- Connect to the database to set up permissions
\c $DB_NAME

-- Grant schema privileges
GRANT USAGE, CREATE ON SCHEMA public TO $OWNER_NAME;

-- Grant privileges on existing objects
GRANT ALL PRIVILEGES ON ALL TABLES IN SCHEMA public TO $OWNER_NAME;
GRANT ALL PRIVILEGES ON ALL SEQUENCES IN SCHEMA public TO $OWNER_NAME;
GRANT ALL PRIVILEGES ON ALL FUNCTIONS IN SCHEMA public TO $OWNER_NAME;

-- Set default privileges for future objects
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL PRIVILEGES ON TABLES TO $OWNER_NAME;
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL PRIVILEGES ON SEQUENCES TO $OWNER_NAME;
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL PRIVILEGES ON FUNCTIONS TO $OWNER_NAME;

-- Change database owner
ALTER DATABASE $DB_NAME OWNER TO $OWNER_NAME;

-- Change schema owner
ALTER SCHEMA public OWNER TO $OWNER_NAME;
EOF

# Test connection
if PGPASSWORD="$PASSWORD" psql -h localhost -U "$OWNER_NAME" -d "$DB_NAME" -c "SELECT 1;" > /dev/null 2>&1; then
    log_info "✅ Owner creation successful!"
    echo ""
    echo "Database: $DB_NAME"
    echo "New Owner: $OWNER_NAME"
    echo "Password: $PASSWORD"
    echo "Private IP: $PRIVATE_IP"
    echo "Previous Owner: $CURRENT_OWNER"
    echo ""
    echo "Local Connection: postgresql://$OWNER_NAME:$PASSWORD@localhost:5432/$DB_NAME"
    echo "Remote Connection: postgresql://$OWNER_NAME:$PASSWORD@$PRIVATE_IP:5432/$DB_NAME"
    echo ""
    echo "Test Local: psql -h localhost -U $OWNER_NAME -d $DB_NAME"
    echo "Test Remote: psql -h $PRIVATE_IP -U $OWNER_NAME -d $DB_NAME"
    echo ""
    log_warning "Note: Previous owner '$CURRENT_OWNER' still has access. Revoke if needed."
else
    log_error "Connection test failed"
    exit 1
fi