#!/bin/bash
set -e

# ==========================================
# Скрипт восстановления ELK (192.168.205.107)
# Запускать от root (sudo bash elk.sh)
# ==========================================

echo ">>> Настройка сети и hostname..."
hostnamectl set-hostname elk
cat > /etc/netplan/00-installer-config.yaml << 'EOF'
network:
  version: 2
  renderer: networkd
  ethernets:
    ens33:
      dhcp4: no
      addresses: [192.168.205.107/24]
      routes:
        - to: default
          via: 192.168.205.2
      nameservers:
        addresses: [8.8.8.8, 1.1.1.1]
EOF
netplan apply
sleep 3

echo ">>> Настройка vm.max_map_count для Elasticsearch..."
sysctl -w vm.max_map_count=1048576
echo "vm.max_map_count=1048576" >> /etc/sysctl.conf

echo ">>> Установка ELK (через зеркало Яндекса)..."
export DEBIAN_FRONTEND=noninteractive
apt update && apt install -y curl gpg apt-transport-https git

curl -fsSL https://artifacts.elastic.co/GPG-KEY-elasticsearch | gpg --dearmor -o /usr/share/keyrings/elasticsearch-keyring.gpg
echo "deb [trusted=yes] https://mirror.yandex.ru/mirrors/elastic/8/ stable main" | tee /etc/apt/sources.list.d/elastic-8.list
apt update && apt install -y elasticsearch logstash kibana

echo ">>> Клонирование конфигов из репозитория..."
rm -rf /tmp/repo
git clone https://github.com/Neltharion-afk/linux-final-project.git /tmp/repo

echo ">>> Настройка Elasticsearch..."
cp /tmp/repo/elk/elasticsearch.yml /etc/elasticsearch/elasticsearch.yml
systemctl daemon-reload
systemctl enable --now elasticsearch

# Ждем, пока Elasticsearch поднимется
echo ">>> Ожидание запуска Elasticsearch (30 секунд)..."
sleep 30

echo ">>> Настройка Kibana..."
cp /tmp/repo/elk/kibana.yml /etc/kibana/kibana.yml
systemctl enable --now kibana

echo ">>> Настройка Logstash..."
mkdir -p /etc/logstash/conf.d
cp /tmp/repo/elk/logstash-nginx.conf /etc/logstash/conf.d/nginx.conf
systemctl enable --now logstash

echo ">>> ELK успешно восстановлен! (Elasticsearch:9200, Kibana:5601, Logstash:5044)"
