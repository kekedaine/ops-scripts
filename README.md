## ops-scripts

Automation scripts for PostgreSQL and Ubuntu host management. Each script is one-liner ready via `curl | bash`.

#### 1. Create new database + user
```bash
curl -fsSL https://ops.bhtas.co/pg-create-db-user.sh | bash -s mydb myuser
```

#### 2. Create owner for an existing database
```bash
curl -fsSL https://ops.bhtas.co/pg-create-owner-for-exist-db.sh | bash -s existing_db new_owner
```

#### 3. Create backup user for an existing database
```bash
curl -fsSL https://ops.bhtas.co/pg-create-backup-user-for-exist-db.sh | bash -s existing_db backup_user
```

#### 4. Create readonly user for an existing database
```bash
curl -fsSL https://ops.bhtas.co/pg-create-readonly-user-for-exist-db.sh | bash -s existing_db readonly_user
```

#### 5. Install PostgreSQL Exporter
```bash
curl -fsSL https://ops.bhtas.co/install-postgres-exporter.sh | bash
```

#### 6. Disable SSH password auth (Ubuntu 20.04 → 26.04)
```bash
curl -fsSL https://ops.bhtas.co/ubuntu-disable-ssh-password.sh | sudo bash
```
> Make sure your SSH public key is already in `authorized_keys` before running, otherwise you may lock yourself out.

---
**Note:** All scripts print the password, connection string and private IP on success.
