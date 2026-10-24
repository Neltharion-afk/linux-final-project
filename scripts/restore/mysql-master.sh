#!/bin/bash
set -e

# ==========================================
# Скрипт восстановления MYSQL MASTER (192.168.205.105)
# Запускать от root (sudo bash mysql-master.sh)
# ==========================================

echo ">>> Настройка сети и hostname..."
hostnamectl set-hostname mysql-master
cat > /etc/netplan/00-installer-config.yaml << 'EOF'
network:
  version: 2
  renderer: networkd
  ethernets:
    ens33:
      dhcp4: no
      addresses: [192.168.205.105/24]
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
apt update && apt install -y mysql-server git

echo ">>> Клонирование конфигов и бэкапа из репозитория..."
rm -rf /tmp/repo
git clone https://github.com/Neltharion-afk/linux-final-project.git /tmp/repo

echo ">>> Применение конфига Master..."
cp /tmp/repo/mysql/master.cnf /etc/mysql/mysql.conf.d/mysqld.cnf
systemctl restart mysql

echo ">>> Создание пользователей и базы..."
mysql -e "CREATE USER IF NOT EXISTS 'replicator'@'%' IDENTIFIED WITH caching_sha2_password BY 'Repl1c@torPass!';"
mysql -e "GRANT REPLICATION SLAVE, REPLICATION CLIENT ON *.* TO 'replicator'@'%';"
mysql -e "CREATE DATABASE IF NOT EXISTS wordpress CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;"
mysql -e "CREATE USER IF NOT EXISTS 'wpuser'@'%' IDENTIFIED WITH caching_sha2_password BY 'WpPass123!';"
mysql -e "GRANT ALL PRIVILEGES ON wordpress.* TO 'wpuser'@'%';"
mysql -e "FLUSH PRIVILEGES;"

echo ">>> Восстановление базы данных из бэкапа..."
if [ -f /tmp/repo/backup/wordpress_dump.sql ]; then
    mysql wordpress < /tmp/repo/backup/wordpress_dump.sql
    echo ">>> База успешно восстановлена!"
else
    echo ">>> ВНИМАНИЕ: Дамп базы не найден в /tmp/repo/backup/"
fi

echo ">>> Установка Node Exporter..."
cd /tmp
wget -q https://github.com/prometheus/node_exporter/releases/download/v1.8.2/node_exporter-1.8.2.linux-amd64.tar.gz
tar -xzf node_exporter-*.tar.gz
cp node_exporter-*/node_exporter /usr/local/bin/
useradd --no-create-home --shell /bin/false node_exporter || true
cp /tmp/repo/monitoring/node_exporter.service /etc/systemd/system/
systemctl daemon-reload && systemctl enable --now node_exporter

echo ">>> Перенастройка Slave на новые координаты..."
# Получаем текущие координаты бинарного лога
BINLOG_FILE=$(mysql -N -e "SHOW BINARY LOG STATUS;" | awk '{print $1}')
BINLOG_POS=$(mysql -N -e "SHOW BINARY LOG STATUS;" | awk '{print $2}')

echo "Новые координаты: $BINLOG_FILE:$BINLOG_POS"

# Отправляем команду на слейв по SSH
echo "!!! ВАЖНО: Если у вас был настроен Slave, выполните на нем:"
echo "STOP REPLICA;"
echo "CHANGE REPLICATION SOURCE TO SOURCE_HOST='192.168.205.105', SOURCE_USER='replicator', SOURCE_PASSWORD='Repl1c@torPass!', SOURCE_LOG_FILE='$BINLOG_FILE', SOURCE_LOG_POS=$BINLOG_POS, GET_SOURCE_PUBLIC_KEY=1;"
echo "START REPLICA;"

echo ">>> MYSQL MASTER успешно восстановлен! (Порт: 3306, База залита)"
