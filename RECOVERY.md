# План аварийного восстановления

## Архитектура

| VM | IP | Роль |
|----|-----|------|
| frontend | 192.168.205.102 | nginx (балансировщик), Prometheus, Grafana |
| backend1 | 192.168.205.103 | apache (8080, 8082), WordPress |
| backend2 | 192.168.205.104 | apache (8081), WordPress |
| mysql-master | 192.168.205.105 | MySQL Master |
| mysql-slave | 192.168.205.106 | MySQL Slave + бэкап |
| elk | 192.168.205.107 | ELK (логи) |

## Требования к новой VM

- Ubuntu Server 22.04/24.04
- 2+ GB RAM, 20+ GB диска
- Доступ по SSH
- Сеть: 192.168.205.0/24, шлюз 192.168.205.2

## Порядок восстановления

### 1. Создать 6 VM и настроить сеть

На каждой VM:
```bash
sudo hostnamectl set-hostname <name>
sudo nano /etc/netplan/00-installer-config.yaml
```

```yaml
network:
  version: 2
  renderer: networkd
  ethernets:
    ens33:
      dhcp4: no
      addresses: [192.168.205.X/24]
      routes:
        - to: default
          via: 192.168.205.2
      nameservers:
        addresses: [8.8.8.8, 1.1.1.1]
```

```bash
sudo netplan apply
```

### 2. Настроить /etc/hosts на всех VM

```text
192.168.205.102 frontend
192.168.205.103 backend1
192.168.205.104 backend2
192.168.205.105 mysql-master
192.168.205.106 mysql-slave
192.168.205.107 elk
```

### 3. MySQL Master (mysql-master)

```bash
sudo apt install -y mysql-server
sudo nano /etc/mysql/mysql.conf.d/mysqld.cnf
```

```ini
[mysqld]
server-id = 1
log_bin = /var/log/mysql/mysql-bin.log
binlog_format = ROW
bind-address = 0.0.0.0
```

```bash
sudo systemctl restart mysql
sudo mysql
```

```sql
CREATE USER 'replicator'@'%' IDENTIFIED WITH caching_sha2_password BY 'Repl1c@torPass!';
GRANT REPLICATION SLAVE, REPLICATION CLIENT ON *.* TO 'replicator'@'%';
CREATE DATABASE wordpress CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
CREATE USER 'wpuser'@'%' IDENTIFIED WITH caching_sha2_password BY 'WpPass123!';
GRANT ALL PRIVILEGES ON wordpress.* TO 'wpuser'@'%';
FLUSH PRIVILEGES;
```

### 4. MySQL Slave (mysql-slave)

```bash
sudo apt install -y mysql-server
sudo nano /etc/mysql/mysql.conf.d/mysqld.cnf
```

```ini
[mysqld]
server-id = 2
relay-log = /var/log/mysql/mysql-relay-bin.log
log_bin = /var/log/mysql/mysql-bin.log
binlog_format = ROW
read_only = ON
bind-address = 0.0.0.0
```

На master:
```bash
sudo mysqldump -u root --all-databases --source-data=2 --single-transaction > /tmp/master_backup.sql
scp /tmp/master_backup.sql nikolay@192.168.205.106:/tmp/
```

На slave:
```bash
sudo mysql < /tmp/master_backup.sql
sudo mysql
```

```sql
CHANGE REPLICATION SOURCE TO
  SOURCE_HOST='192.168.205.105',
  SOURCE_USER='replicator',
  SOURCE_PASSWORD='Repl1c@torPass!',
  SOURCE_LOG_FILE='mysql-bin.000001',
  SOURCE_LOG_POS=<позиция из дампа>,
  GET_SOURCE_PUBLIC_KEY=1;
START REPLICA;
```

### 5. Apache + WordPress (backend1, backend2)

```bash
sudo apt install -y apache2 php libapache2-mod-php php-mysql php-curl php-gd php-mbstring php-xml php-xmlrpc php-soap php-intl php-zip
```

Настройка портов (backend1 — 8080/8082, backend2 — 8081):
```bash
sudo nano /etc/apache2/ports.conf
```
```apache
Listen 8080
Listen 8082  # только для backend1
```

Виртуальные хосты:
```bash
sudo nano /etc/apache2/sites-available/000-default.conf
```
```apache
<VirtualHost *:8080>
    DocumentRoot /var/www/html
</VirtualHost>
```

Установка WordPress:
```bash
cd /tmp
wget https://wordpress.org/latest.tar.gz
tar -xzf latest.tar.gz
sudo rm -rf /var/www/html/*
sudo cp -r wordpress/* /var/www/html/
sudo chown -R www-data:www-data /var/www/html/
sudo cp /var/www/html/wp-config-sample.php /var/www/html/wp-config.php
```

Настройка wp-config.php (DB_HOST = 192.168.205.105).

```bash
sudo systemctl restart apache2
```

### 6. Nginx (frontend)

```bash
sudo apt install -y nginx
sudo nano /etc/nginx/sites-available/balance
```
```nginx
upstream apache_backend {
    server 192.168.205.103:8080;
    server 192.168.205.103:8082;
    server 192.168.205.104:8081;
}

server {
    listen 80 default_server;
    server_name _;
    location / {
        proxy_pass http://apache_backend;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
    }
}
```
```bash
sudo ln -s /etc/nginx/sites-available/balance /etc/nginx/sites-enabled/
sudo rm /etc/nginx/sites-enabled/default
sudo nginx -t && sudo systemctl restart nginx
```

### 7. Восстановить БД из бэкапа

На slave:
```bash
ls /backup/mysql/
sudo mysql < /backup/mysql/wordpress_FULL_<DATE>.sql
```

### 8. Мониторинг (Prometheus + Grafana)

На **всех VM** (frontend, backend1, backend2, mysql-master, mysql-slave) установить `node_exporter`:

```bash
wget https://github.com/prometheus/node_exporter/releases/download/v1.8.2/node_exporter-1.8.2.linux-amd64.tar.gz
tar -xzf node_exporter-*.tar.gz
sudo cp node_exporter-*/node_exporter /usr/local/bin/
sudo useradd --no-create-home --shell /bin/false node_exporter

Создать systemd-сервис /etc/systemd/system/node_exporter.service (конфиг в monitoring/node_exporter.service):

bash
sudo cp monitoring/node_exporter.service /etc/systemd/system/
sudo systemctl daemon-reload
sudo systemctl enable --now node_exporter
На frontend установить Prometheus и Grafana. Готовые конфиги лежат в папке monitoring/:

bash
sudo cp monitoring/prometheus.yml /etc/prometheus/prometheus.yml
sudo cp monitoring/prometheus.service /etc/systemd/system/
sudo systemctl daemon-reload
sudo systemctl enable --now prometheus
Установить Grafana:

bash
sudo apt install -y grafana
sudo systemctl enable --now grafana-server
Подключить Prometheus как datasource в Grafana (http://localhost:9090) и импортировать дашборд Node Exporter Full (ID 1860).
```

### 9. Проверка

- `curl http://192.168.205.102` — WordPress открывается.
- `sudo mysql -e "SHOW REPLICA STATUS\G"` на slave — Replica_IO_Running: Yes, Replica_SQL_Running: Yes.
- `curl http://192.168.205.102:9090/targets` — все UP.
- `curl http://192.168.205.102:3000` — Grafana работает.
