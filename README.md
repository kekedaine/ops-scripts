# PostgreSQL Management Scripts

Bộ script tự động quản lý PostgreSQL database và user.

## 1. Tạo Database + User mới
```bash
curl -fsSL https://ops.bhtas.co/pg-create-db-user.sh | bash -s mydb myuser
```

## 2. Tạo Owner cho Database có sẵn
```bash
curl -fsSL https://ops.bhtas.co/pg-create-owner-for-exist-db.sh | bash -s existing_db new_owner
```

## 3. Tạo Backup User cho Database có sẵn
```bash
curl -fsSL https://ops.bhtas.co/pg-create-backup-user-for-exist-db.sh | bash -s existing_db backup_user
```

## 4. Tạo Readonly User cho Database có sẵn
```bash
curl -fsSL https://ops.bhtas.co/pg-create-readonly-user-for-exist-db.sh | bash -s existing_db readonly_user
```

## 5. Cài đặt PostgreSQL Exporter
```bash
curl -fsSL https://ops.bhtas.co/install-postgres-exporter.sh | bash
```

## 6. Disable SSH Password Auth (Ubuntu 20.04 → 26.04)
```bash
curl -fsSL https://ops.bhtas.co/ubuntu-disable-ssh-password.sh | sudo bash
```
> Yêu cầu đã có SSH public key trong `authorized_keys` trước khi chạy, nếu không sẽ bị lock-out.

---
**Lưu ý:** Tất cả script đều hiển thị password, connection string và private IP sau khi chạy thành công.