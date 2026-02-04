# Hướng dẫn cài đặt PostgreSQL 18 và Postgres Exporter (Ubuntu 24)

## 1. Cài đặt PostgreSQL 18

```bash
sudo sh -c 'echo "deb http://apt.postgresql.org/pub/repos/apt $(lsb_release -cs)-pgdg main" > /etc/apt/sources.list.d/pgdg.list'
wget --quiet -O - https://www.postgresql.org/media/keys/ACCC4CF8.asc | sudo tee /etc/apt/trusted.gpg.d/pgdg.asc > /dev/null

sudo apt-get update

# Cài đặt PostgreSQL 18
sudo apt-get install -y postgresql-18 postgresql-client-18 postgresql-contrib-18
```

## 2. Cấu hình PostgreSQL cho monitoring

### Kích hoạt thư viện thống kê
```sql
-- Kết nối vào PostgreSQL với quyền superuser
sudo -u postgres psql

-- Thêm các cấu hình monitoring
ALTER SYSTEM SET shared_preload_libraries = 'pg_stat_statements';
ALTER SYSTEM SET track_activity_query_size = '4096';
ALTER SYSTEM SET pg_stat_statements.track = 'ALL';
ALTER SYSTEM SET pg_stat_statements.max = '10000';
ALTER SYSTEM SET pg_stat_statements.track_utility = 'off';
ALTER SYSTEM SET track_io_timing = 'on';

-- Khởi động lại PostgreSQL để áp dụng cấu hình
\q
```

```bash
sudo systemctl restart postgresql
```

### Cấu hình kết nối từ xa
```bash
# Sửa listen_addresses trong postgresql.conf
sudo sed -i "s/^#*listen_addresses = 'localhost'/listen_addresses = '*'/" /etc/postgresql/18/main/postgresql.conf

# Thêm cấu hình authentication vào pg_hba.conf
echo "host    all             all             0.0.0.0/0               scram-sha-256" | sudo tee -a /etc/postgresql/18/main/pg_hba.conf

# Sửa local authentication từ peer thành md5 (cho phép kết nối local bằng password)
sudo sed -i 's/local   all             all                                     peer/local   all             all                                     md5/' /etc/postgresql/18/main/pg_hba.conf

# Khởi động lại PostgreSQL
sudo systemctl restart postgresql
```

## 3. Cài đặt Postgres Exporter

### Cài đặt bằng script tự động
```bash
# Cài đặt mới (sẽ báo lỗi nếu đã có service cũ)
curl -fsSL https://raw.githubusercontent.com/ongtungduong/postgres_exporter/master/install-postgres-exporter.sh | sudo bash

# Cài đặt và xóa service cũ (nếu có)
curl -fsSL https://raw.githubusercontent.com/ongtungduong/postgres_exporter/master/install-postgres-exporter.sh | sudo bash -s uninstall_old_service

# Tùy chỉnh port (ví dụ port 9999)
curl -fsSL https://raw.githubusercontent.com/ongtungduong/postgres_exporter/master/install-postgres-exporter.sh | sudo POSTGRES_EXPORTER_PORT=9999 bash
```

### Kiểm tra service
sudo systemctl status postgres_exporter

## 4. Kiểm tra

### Kiểm tra PostgreSQL
```bash
sudo -u postgres psql -c "SELECT version();"
```

### Kiểm tra Postgres Exporter
```bash
# Kiểm tra service
sudo systemctl status postgres_exporter

# Lấy port thực tế đang sử dụng
EXPORTER_PORT=$(sudo netstat -tlnp | grep postgres_exporter | awk '{print $4}' | cut -d: -f2 | head -1)
echo "Postgres Exporter đang chạy trên port: $EXPORTER_PORT"

# Kiểm tra metrics endpoint
curl http://localhost:$EXPORTER_PORT/metrics
```

### Kiểm tra pg_stat_statements
```sql
sudo -u postgres psql -c "SELECT * FROM pg_stat_statements LIMIT 5;"
```

## 5. Lưu ý

- Thay đổi mật khẩu mặc định `password` thành mật khẩu mạnh
- **Bảo mật**: Cấu hình `0.0.0.0/0` cho phép kết nối từ mọi IP - chỉ sử dụng trong môi trường phát triển
- Cấu hình firewall để mở port 5432 (PostgreSQL) và 9187 (Exporter) nếu cần
- Kiểm tra log nếu có lỗi: `sudo journalctl -u postgres_exporter -f`

## Troubleshooting

### Lỗi kết nối database
```bash
# Kiểm tra PostgreSQL đang chạy
sudo systemctl status postgresql

# Kiểm tra user exporter có thể kết nối
psql -h localhost -U exporter -d postgres
```

### Lỗi port đã được sử dụng
```bash
# Kiểm tra port đang được sử dụng
sudo lsof -i :9187

# Thay đổi port trong file service
sudo systemctl edit postgres_exporter
```