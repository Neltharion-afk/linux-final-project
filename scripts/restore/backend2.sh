#!/bin/bash
set -e

# ==========================================
# Скрипт восстановления BACKEND 2 (192.168.205.104)
# Запускать от root (sudo bash backend2.sh)
# ==========================================

echo ">>> Настройка сети и hostname..."
hostnamectl set-hostname backend2
cat > /etc/netplan/00-installer-config.yaml << 'EOF'
network:
  version: 2
  renderer: networkd
  ethernets:
    ens33:
      dhcp4: no
      addresses: [192.168.205.104/24]
      routes:
        - to: default
          via: 192.168.205.2
      nameservers:
        addresses: [8.8.8.8, 1.1.1.1]
EOF
netplan apply
sleep 3

echo ">>> Установка пакетов..."
export DEBIAN_FRONTEND=noninteractive
apt update && apt install -y apache2 php libapache2-mod-php php-mysql php-curl php-gd php-mbstring php-xml php-xmlrpc php-soap php-intl php-zip git wget

echo ">>> Клонирование конфигов из репозитория..."
rm -rf /tmp/repo
git clone https://github.com/Neltharion-afk/linux-final-project.git /tmp/repo

echo ">>> Развертывание WordPress..."
cd /tmp && wget -q https://wordpress.org/latest.tar.gz && tar -xzf latest.tar.gz
rm -rf /var/www/html/* && cp -r wordpress/* /var/www/html/
chown -R www-data:www-data /var/www/html/

echo ">>> Настройка Apache (порт 8081)..."
cat > /etc/apache2/ports.conf << 'EOF'
Listen 8081
EOF

cat > /etc/apache2/sites-available/000-default.conf << 'EOF'
<VirtualHost *:8081>
    ServerAdmin webmaster@localhost
    DocumentRoot /var/www/html
    ErrorLog ${APACHE_LOG_DIR}/error-8081.log
    CustomLog ${APACHE_LOG_DIR}/access-8081.log combined
</VirtualHost>
EOF

a2ensite 000-default.conf

echo ">>> Настройка wp-config.php..."
cat > /var/www/html/wp-config.php << 'EOF'
<?php
define( 'DB_NAME', 'wordpress' );
define( 'DB_USER', 'wpuser' );
define( 'DB_PASSWORD', 'WpPass123!' );
define( 'DB_HOST', '192.168.205.105' ); 
define('WP_HOME', 'http://192.168.205.102');
define('WP_SITEURL', 'http://192.168.205.102');
$table_prefix = 'wp_';
require_once ABSPATH . 'wp-settings.php';
EOF
chown www-data:www-data /var/www/html/wp-config.php

echo ">>> Фикс PHP (pcre.jit)..."
echo "pcre.jit=0" >> /etc/php/8.5/apache2/php.ini
systemctl restart apache2

echo ">>> Установка Node Exporter..."
cd /tmp
wget -q https://github.com/prometheus/node_exporter/releases/download/v1.8.2/node_exporter-1.8.2.linux-amd64.tar.gz
tar -xzf node_exporter-*.tar.gz
cp node_exporter-*/node_exporter /usr/local/bin/
useradd --no-create-home --shell /bin/false node_exporter || true
cp /tmp/repo/monitoring/node_exporter.service /etc/systemd/system/
systemctl daemon-reload && systemctl enable --now node_exporter

echo ">>> BACKEND 2 успешно восстановлен! (Apache:8081)"
