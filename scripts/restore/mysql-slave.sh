#!/bin/bash
set -e

echo ">>> Настройка сети и hostname..."
hostnamectl set-hostname mysql-slave
cat > /etc/netplan/00-installer-config.yaml << 'EOF'
network:
  version: 2
  renderer: networkd
  ethernets:
    ens33:
      dhcp4: no
      addresses: [192.168.205.106/24]
      routes:
        - to: default
          via: 192.168.205.2
      nameservers:
        addresses: [8.8.8.8, 1.1.1.1]
EOF
netplan apply
sleep 3

echo ">>> Установка MySQL и Git..."
export DEBIAN_FRONTEND=noninteractive
apt update && apt install -y mysql-server mysql-client git

echo ">>> Жесткая настройка пароля root..."
sudo systemctl stop mysql || true

# Удаляем старый конфиг, чтобы убрать auth_socket, и ставим свой базовый
cat > /etc/mysql/mysql.conf.d/mysqld.cnf << 'EOF'
[mysqld]
server-id = 1
log_bin = /var/log/mysql/mysql-bin.log
binlog_format = ROW
bind-address = 0.0.0.0
EOF

# Настраиваем systemd на аварийный режим
sudo mkdir -p /etc/systemd/system/mysql.service.d
cat > /etc/systemd/system/mysql.service.d/override.conf << 'EOF'
[Service]
ExecStart=
ExecStart=/usr/sbin/mysqld --skip-grant-tables --skip-networking
EOF
sudo systemctl daemon-reload
sudo systemctl start mysql
sleep 5

# Сбрасываем пароль (теперь auth_socket тут не помешает)
mysql -u root <<EOF
FLUSH PRIVILEGES;
ALTER USER 'root'@'localhost' IDENTIFIED WITH caching_sha2_password BY 'MasterPass123!';
EOF

# Возвращаем нормальный режим
sudo rm -rf /etc/systemd/system/mysql.service.d
sudo systemctl daemon-reload
sudo systemctl restart mysql
sleep 3
echo ">>> Настройка конфигов слейва..."
rm -rf /tmp/repo
git clone https://github.com/Neltharion-afk/linux-final-project.git /tmp/repo
cp /tmp/repo/mysql/slave.cnf /etc/mysql/mysql.conf.d/mysqld.cnf
systemctl restart mysql

echo ">>> Получение координат с Мастера (192.168.205.105)..."
MASTER_INFO=$(mysql -h 192.168.205.105 -u replicator -p'Repl1c@torPass!' -e "SHOW BINARY LOG STATUS\G")
BINLOG_FILE=$(echo "$MASTER_INFO" | grep "File:" | awk '{print $2}')
BINLOG_POS=$(echo "$MASTER_INFO" | grep "Position:" | awk '{print $2}')

if [ -z "$BINLOG_FILE" ] || [ -z "$BINLOG_POS" ]; then
    echo "ОШИБКА: Не удалось получить координаты с мастера!"
    exit 1
fi
echo ">>> Координаты мастера: $BINLOG_FILE, $BINLOG_POS"

echo ">>> Создание дампа и заливка локально..."
mysqldump -h 192.168.205.105 -u replicator -p'Repl1c@torPass!' --all-databases --source-data=2 --single-transaction > /tmp/master_dump.sql
mysql -u root -p'SlavePass123!' < /tmp/master_dump.sql

echo ">>> Настройка репликации..."
mysql -u root -p'SlavePass123!' -e "STOP REPLICA;"
mysql -u root -p'SlavePass123!' -e "CHANGE REPLICATION SOURCE TO SOURCE_HOST='192.168.205.105', SOURCE_USER='replicator', SOURCE_PASSWORD='Repl1c@torPass!', SOURCE_LOG_FILE='$BINLOG_FILE', SOURCE_LOG_POS=$BINLOG_POS, GET_SOURCE_PUBLIC_KEY=1;"
mysql -u root -p'SlavePass123!' -e "START REPLICA;"

echo ">>> Установка Node Exporter..."
cd /tmp
wget -q https://github.com/prometheus/node_exporter/releases/download/v1.8.2/node_exporter-1.8.2.linux-amd64.tar.gz
tar -xzf node_exporter-*.tar.gz
cp node_exporter-*/node_exporter /usr/local/bin/
useradd --no-create-home --shell /bin/false node_exporter || true
cp /tmp/repo/monitoring/node_exporter.service /etc/systemd/system/
systemctl daemon-reload && systemctl enable --now node_exporter

echo ">>> MYSQL SLAVE успешно восстановлен! (Пароль root: SlavePass123!)"
echo ">>> Статус репликации:"
mysql -u root -p'SlavePass123!' -e "SHOW REPLICA STATUS\G" | grep -E "Replica_IO_Running|Replica_SQL_Running"
