#!/bin/bash
set -e

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
apt update && apt install -y mysql-server mysql-client git

echo ">>> Жесткая настройка пароля root..."
sudo systemctl stop mysql || true

# Стираем старый конфиг (убираем auth_socket) и ставим конфиг мастера
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

# Сбрасываем пароль
mysql -u root <<EOF
FLUSH PRIVILEGES;
ALTER USER 'root'@'localhost' IDENTIFIED WITH caching_sha2_password BY 'MasterPass123!';
EOF

# Возвращаем нормальный режим
sudo rm -rf /etc/systemd/system/mysql.service.d
sudo systemctl daemon-reload
sudo systemctl restart mysql
sleep 3

echo ">>> Создание пользователей и базы..."
mysql -u root -p'MasterPass123!' -e "CREATE USER IF NOT EXISTS 'replicator'@'%' IDENTIFIED WITH caching_sha2_password BY 'Repl1c@torPass!';"
mysql -u root -p'MasterPass123!' -e "GRANT REPLICATION SLAVE, REPLICATION CLIENT, RELOAD, PROCESS ON *.* TO 'replicator'@'%';"
mysql -u root -p'MasterPass123!' -e "CREATE DATABASE IF NOT EXISTS wordpress CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;"
mysql -u root -p'MasterPass123!' -e "CREATE USER IF NOT EXISTS 'wpuser'@'%' IDENTIFIED WITH caching_sha2_password BY 'WpPass123!';"
mysql -u root -p'MasterPass123!' -e "GRANT ALL PRIVILEGES ON wordpress.* TO 'wpuser'@'%';"
mysql -u root -p'MasterPass123!' -e "FLUSH PRIVILEGES;"

echo ">>> Клонирование конфигов и бэкапа..."
rm -rf /tmp/repo
git clone https://github.com/Neltharion-afk/linux-final-project.git /tmp/repo

echo ">>> Восстановление базы данных из бэкапа..."
if [ -f /tmp/repo/backup/wordpress_dump.sql ]; then
    mysql -u root -p'MasterPass123!' wordpress < /tmp/repo/backup/wordpress_dump.sql
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

echo ">>> MYSQL MASTER успешно восстановлен! (Пароль root: MasterPass123!)"
