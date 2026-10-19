#!/bin/bash
set -e

# ==========================================
# Скрипт восстановления MYSQL SLAVE (192.168.205.106)
# Запускать от root (sudo bash mysql-slave.sh)
# ==========================================

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

echo ">>> Установка MySQL, клиента и Git..."
export DEBIAN_FRONTEND=noninteractive
apt update && apt install -y mysql-server mysql-client git

echo ">>> Клонирование конфигов из репозитория..."
rm -rf /tmp/repo
git clone https://github.com/Neltharion-afk/linux-final-project.git /tmp/repo

echo ">>> Применение конфига Slave..."
cp /tmp/repo/mysql/slave.cnf /etc/mysql/mysql.conf.d/mysqld.cnf
systemctl restart mysql

echo ">>> Подключение к Мастеру (192.168.205.105) и создание дампа..."
# Создаем дамп с мастера (предполагается, что root на мастере без пароля)
mysqldump -h 192.168.205.105 -u root -p'RootPass123!' --all-databases --source-data=2 --single-transaction > /tmp/master_dump.sql

echo ">>> Извлечение позиции бинлога..."
BINLOG_FILE=$(grep -m1 "CHANGE REPLICATION SOURCE" /tmp/master_dump.sql | sed -n "s/.*SOURCE_LOG_FILE='\([^']*\)'.*/\1/p")
BINLOG_POS=$(grep -m1 "CHANGE REPLICATION SOURCE" /tmp/master_dump.sql | sed -n "s/.*SOURCE_LOG_POS=\([0-9]*\).*/\1/p")

if [ -z "$BINLOG_FILE" ] || [ -z "$BINLOG_POS" ]; then
    echo "ОШИБКА: Не удалось получить позицию бинлога с мастера!"
    exit 1
fi

echo ">>> Заливка дампа в локальную базу..."
mysql < /tmp/master_dump.sql

echo ">>> Настройка репликации..."
mysql -e "STOP REPLICA;"
mysql -e "CHANGE REPLICATION SOURCE TO SOURCE_HOST='192.168.205.105', SOURCE_USER='replicator', SOURCE_PASSWORD='Repl1c@torPass!', SOURCE_LOG_FILE='$BINLOG_FILE', SOURCE_LOG_POS=$BINLOG_POS, GET_SOURCE_PUBLIC_KEY=1;"
mysql -e "START REPLICA;"

echo ">>> Установка Node Exporter..."
cd /tmp
wget -q https://github.com/prometheus/node_exporter/releases/download/v1.8.2/node_exporter-1.8.2.linux-amd64.tar.gz
tar -xzf node_exporter-*.tar.gz
cp node_exporter-*/node_exporter /usr/local/bin/
useradd --no-create-home --shell /bin/false node_exporter || true
cp /tmp/repo/monitoring/node_exporter.service /etc/systemd/system/
systemctl daemon-reload && systemctl enable --now node_exporter

echo ">>> MYSQL SLAVE успешно восстановлен!"
echo ">>> Текущий статус репликации:"
mysql -e "SHOW REPLICA STATUS\G" | grep -E "Replica_IO_Running|Replica_SQL_Running"
