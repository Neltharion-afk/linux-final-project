#!/bin/bash
set -e

# ==========================================
# Скрипт восстановления FRONTEND (192.168.205.102)
# Запускать от root (sudo bash frontend.sh)
# ==========================================

echo ">>> Настройка сети и hostname..."
hostnamectl set-hostname frontend
cat > /etc/netplan/00-installer-config.yaml << 'EOF'
network:
  version: 2
  renderer: networkd
  ethernets:
    ens33:
      dhcp4: no
      addresses: [192.168.205.102/24]
      routes:
        - to: default
          via: 192.168.205.2
      nameservers:
        addresses: [8.8.8.8, 1.1.1.1]
EOF
netplan apply

# Ждем пару секунд, чтобы сеть поднялась
sleep 3

echo ">>> Обновление системы и установка пакетов..."
export DEBIAN_FRONTEND=noninteractive
apt update && apt install -y nginx git wget curl adduser libfontconfig1 musl

echo ">>> Клонирование конфигов из репозитория..."
rm -rf /tmp/repo
git clone https://github.com/Neltharion-afk/linux-final-project.git /tmp/repo

echo ">>> Настройка Nginx (балансировка)..."
cp /tmp/repo/nginx/balance.conf /etc/nginx/sites-available/balance
ln -sf /etc/nginx/sites-available/balance /etc/nginx/sites-enabled/balance
rm -f /etc/nginx/sites-enabled/default
nginx -t && systemctl restart nginx

echo ">>> Установка Node Exporter..."
cd /tmp
wget -q https://github.com/prometheus/node_exporter/releases/download/v1.8.2/node_exporter-1.8.2.linux-amd64.tar.gz
tar -xzf node_exporter-*.tar.gz
cp node_exporter-*/node_exporter /usr/local/bin/
useradd --no-create-home --shell /bin/false node_exporter || true
cp /tmp/repo/monitoring/node_exporter.service /etc/systemd/system/
systemctl daemon-reload && systemctl enable --now node_exporter

echo ">>> Установка Prometheus..."
cd /tmp
wget -q https://github.com/prometheus/prometheus/releases/download/v2.50.0/prometheus-2.50.0.linux-amd64.tar.gz
tar xzf prometheus-*.tar.gz
cp prometheus-*/prometheus /usr/local/bin/
cp prometheus-*/promtool /usr/local/bin/
mkdir -p /etc/prometheus /var/lib/prometheus
cp /tmp/repo/monitoring/prometheus.yml /etc/prometheus/
cp /tmp/repo/monitoring/prometheus.service /etc/systemd/system/
useradd --no-create-home --shell /bin/false prometheus || true
chown -R prometheus:prometheus /etc/prometheus /var/lib/prometheus
systemctl daemon-reload && systemctl enable --now prometheus

echo ">>> Установка Grafana..."
cd /tmp
wget -q https://dl.grafana.com/oss/release/grafana_11.6.0_amd64.deb
dpkg -i grafana_11.6.0_amd64.deb || apt install -f -y
systemctl enable --now grafana-server

echo ">>> Установка и настройка Filebeat..."
cd /tmp
wget -q https://artifacts.elastic.co/downloads/beats/filebeat/filebeat-8.19.23-amd64.deb
dpkg -i filebeat-8.19.23-amd64.deb || apt install -f -y

# Копируем готовый конфиг из репо
cp /tmp/repo/elk/filebeat.yml /etc/filebeat/filebeat.yml
filebeat modules enable nginx
systemctl enable --now filebeat

echo ">>> FRONTEND успешно восстановлен! (Nginx:80, Prometheus:9090, Grafana:3000, Filebeat)"
