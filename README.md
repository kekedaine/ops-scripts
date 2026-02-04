# PostgreSQL Management Scripts

Bộ script tự động quản lý PostgreSQL database và user.

## 1. Tạo Database + User mới
```bash
curl -fsSL https://raw.githubusercontent.com/kekedaine/ops-scripts/refs/heads/main/pg-create-db-user.sh | bash -s mydb myuser
```

## 2. Tạo Owner cho Database có sẵn
```bash
curl -fsSL https://raw.githubusercontent.com/kekedaine/ops-scripts/refs/heads/main/pg-create-owner-for-exist-db.sh | bash -s existing_db new_owner
```

## 3. Tạo Backup User cho Database có sẵn
```bash
curl -fsSL https://raw.githubusercontent.com/kekedaine/ops-scripts/refs/heads/main/pg-create-backup-user-for-exist-db.sh | bash -s existing_db backup_user
```

## 4. Tạo Readonly User cho Database có sẵn
```bash
curl -fsSL https://raw.githubusercontent.com/kekedaine/ops-scripts/refs/heads/main/pg-create-readonly-user-for-exist-db.sh | bash -s existing_db readonly_user
```

## 5. Cài đặt PostgreSQL Exporter
```bash
curl -fsSL https://raw.githubusercontent.com/kekedaine/ops-scripts/refs/heads/main/install-postgres-exporter.sh | bash
```

---
**Lưu ý:** Tất cả script đều hiển thị password, connection string và private IP sau khi chạy thành công.