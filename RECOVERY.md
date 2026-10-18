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

## Общие требования к VM
- Ubuntu Server 22.04/24.04
- Сеть: NAT (VMware), шлюз 192.168.205.2
- Доступ по SSH

---

## Шаг 1. Базовая настройка всех 6 VM

Для каждой из 6 виртуальных машин выполнить:

1. Установить hostname (например, `frontend`, `backend1` и т.д.):
```bash
sudo hostnamectl set-hostname <name>
```
Настроить статический IP через netplan (/etc/netplan/00-installer-config.yaml):

```
yaml
network:
  version: 2
  renderer: networkd
  ethernets:
    ens33:
      dhcp4: no
      addresses: [192.168.205.X/24] # где X - номер VM
      routes:
        - to: default
          via: 192.168.205.2
      nameservers:
        addresses: [8.8.8.8, 1.1.1.1]
```
Применить: sudo netplan apply

Прописать sudo nano /etc/hosts на каждой VM:

```
192.168.205.102 frontend
192.168.205.103 backend1
192.168.205.104 backend2
192.168.205.105 mysql-master
192.168.205.106 mysql-slave
192.168.205.107 elk
```
## Шаг 2. Восстановление MySQL Master (192.168.205.105)
Установить MySQL:

```
sudo apt update && sudo apt install -y mysql-server
```
Скопировать конфиг из репозитория:

```
git clone https://github.com/Neltharion-afk/linux-final-project.git
sudo cp linux-final-project/mysql/master.cnf /etc/mysql/mysql.conf.d/mysqld.cnf
sudo systemctl restart mysql
```
Создать пользователей и базу:

sudo mysql
```
CREATE USER 'replicator'@'%' IDENTIFIED WITH caching_sha2_password BY 'Repl1c@torPass!';
GRANT REPLICATION SLAVE, REPLICATION CLIENT ON *.* TO 'replicator'@'%';
CREATE DATABASE wordpress CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
CREATE USER 'wpuser'@'%' IDENTIFIED WITH caching_sha2_password BY 'WpPass123!';
GRANT ALL PRIVILEGES ON wordpress.* TO 'wpuser'@'%';
FLUSH PRIVILEGES;
EXIT;
```
Восстановить дамп (если есть бэкап):

```
sudo mysql < /backup/mysql/wordpress_FULL_<DATE>.sql
```

### Шаг 3. Восстановление MySQL Slave (192.168.205.106)
Установить MySQL:

```
sudo apt update && sudo apt install -y mysql-server
```
Скопировать конфиг:

```
sudo cp linux-final-project/mysql/slave.cnf /etc/mysql/mysql.conf.d/mysqld.cnf
sudo systemctl restart mysql
```
Сделать дамп с Master и перенести на Slave:
(На Master):

```
sudo mysqldump -u root --all-databases --source-data=2 --single-transaction > /tmp/master_backup.sql
scp /tmp/master_backup.sql nikolay@192.168.205.106:/tmp/
```

```
sudo mysql < /tmp/master_backup.sql
sudo mysql
CHANGE REPLICATION SOURCE TO
  SOURCE_HOST='192.168.205.105',
  SOURCE_USER='replicator',
  SOURCE_PASSWORD='Repl1c@torPass!',
  SOURCE_LOG_FILE='mysql-bin.000001',
  SOURCE_LOG_POS=<позиция из дампа>,
  GET_SOURCE_PUBLIC_KEY=1;
START REPLICA;
SHOW REPLICA STATUS\G
```
Настроить скрипт бэкапа и cron:

```
sudo cp linux-final-project/scripts/backup_mysql.sh /opt/scripts/
sudo cp linux-final-project/cron/backup_mysql /etc/cron.d/
```

### Шаг 4. Восстановление Backend-серверов (192.168.205.103 и .104)
На backend1 и backend2 выполнить:

Установить Apache, PHP и WordPress:

```
sudo apt install -y apache2 php libapache2-mod-php php-mysql php-curl php-gd php-mbstring php-xml php-xmlrpc php-soap php-intl php-zip
cd /tmp && wget https://wordpress.org/latest.tar.gz && tar -xzf latest.tar.gz
sudo rm -rf /var/www/html/* && sudo cp -r wordpress/* /var/www/html/
sudo chown -R www-data:www-data /var/www/html/
```
Скопировать конфиги Apache из репозитория:
(Для backend1):

```
sudo cp linux-final-project/apache/backend1-ports.conf /etc/apache2/ports.conf
sudo cp linux-final-project/apache/backend1-site-8080.conf /etc/apache2/sites-available/
sudo cp linux-final-project/apache/backend1-site-8082.conf /etc/apache2/sites-available/
sudo a2ensite site-8080 site-8082
```
(Для backend2):

```
sudo cp linux-final-project/apache/backend2-ports.conf /etc/apache2/ports.conf
sudo cp linux-final-project/apache/backend2-site-8081.conf /etc/apache2/sites-available/000-default.conf
```
Настроить wp-config.php (указать DB_HOST = 192.168.205.105 и WP_HOME = http://192.168.205.102).

Перезапустить Apache:

```
sudo systemctl restart apache2
```

## Шаг 5. Восстановление Frontend (192.168.205.102)
Установить Nginx:

```
sudo apt install -y nginx
```
Скопировать конфиг балансировки:

```
sudo cp linux-final-project/nginx/balance.conf /etc/nginx/sites-available/balance
sudo ln -s /etc/nginx/sites-available/balance /etc/nginx/sites-enabled/
sudo rm /etc/nginx/sites-enabled/default
sudo nginx -t && sudo systemctl restart nginx
```
Установить и настроить мониторинг:


### Node Exporter на всех VM (конфиг в monitoring/)
### На frontend - Prometheus и Grafana (конфиги в monitoring/)

```
sudo cp linux-final-project/monitoring/prometheus.yml /etc/prometheus/
sudo cp linux-final-project/monitoring/prometheus.service /etc/systemd/system/
sudo systemctl daemon-reload && sudo systemctl enable --now prometheus
sudo apt install -y grafana && sudo systemctl enable --now grafana-server
```

## Шаг 6. Восстановление логов ELK (192.168.205.107)

1. Установить ELK. Из-за блокировок официального репозитория используем зеркало Яндекса:
```
sudo apt install -y curl gpg apt-transport-https
curl -fsSL https://artifacts.elastic.co/GPG-KEY-elasticsearch | sudo gpg --dearmor -o /usr/share/keyrings/elasticsearch-keyring.gpg
echo "deb [trusted=yes] https://mirror.yandex.ru/mirrors/elastic/8/ stable main" | sudo tee /etc/apt/sources.list.d/elastic-8.list
sudo apt update
sudo apt install -y elasticsearch logstash kibana
```
Настроить Elasticsearch и Kibana (скопировать конфиги из репозитория):

```
git clone https://github.com/Neltharion-afk/linux-final-project.git
sudo cp linux-final-project/elk/elasticsearch.yml /etc/elasticsearch/elasticsearch.yml
sudo cp linux-final-project/elk/kibana.yml /etc/kibana/kibana.yml
```

# Включить и запустить сервисы
```
sudo systemctl daemon-reload
sudo systemctl enable --now elasticsearch
sudo systemctl enable --now kibana
```
Настроить Logstash (конфиг nginx.conf в папке elk/):

```
sudo mkdir -p /etc/logstash/conf.d
sudo cp linux-final-project/elk/logstash-nginx.conf /etc/logstash/conf.d/nginx.conf
sudo systemctl enable --now logstash
```

## Шаг 7. Финальная проверка
curl http://192.168.205.102 — WordPress открывается.

sudo mysql -e "SHOW REPLICA STATUS\G" на slave — Replica_IO_Running: Yes, Replica_SQL_Running: Yes.

curl http://192.168.205.102:9090/targets — все UP.

curl http://192.168.205.102:3000 — Grafana работает.
