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

## Сценарий: Упал Backend 1 (192.168.205.103)
**Признаки:** Сайт открывается, но ```Nginx``` отдает ```502 Bad Gateway``` на порт 8080/8082.

**Действия на новой чистой VM (назначить IP ```92.168.205.103```):**
```bash
sudo apt update && sudo apt install -y git
sudo rm -rf /tmp/linux-final-project
git clone https://github.com/Neltharion-afk/linux-final-project.git /tmp/linux-final-project
sudo bash /tmp/linux-final-project/scripts/restore/backend1.sh

```
sudo systemctl status apache2 | grep Active
curl -I http://localhost:8080
curl -I http://localhost:8082
```

**Ожидаемый результат: ```Active (running)``` и ```HTTP/1.1 301 Moved Permanently``` с заголовком ```X-Redirect-By: WordPress```.**

## Сценарий: Упал ```Backend 2``` (192.168.205.104)
**Признаки: Сайт открывается, но ```Nginx``` отдает ```502 Bad Gateway на порт 8081```.

**Действия на новой чистой VM (назначить IP ```192.168.205.104```):**

```
sudo apt update && sudo apt install -y git
sudo rm -rf /tmp/linux-final-project
git clone https://github.com/Neltharion-afk/linux-final-project.git /tmp/linux-final-project
sudo bash /tmp/linux-final-project/scripts/restore/backend2.sh
```

```
sudo systemctl status apache2 | grep Active
curl -I http://localhost:8081
```

## Сценарий: Упал ```Frontend``` (192.168.205.102)

**Признаки: Сайт не открывается вообще (ошибка соединения), ```Nginx``` не работает.**

**Действия на новой чистой VM (назначить IP ```192.168.205.102```):**

```
sudo apt update && sudo apt install -y git
sudo rm -rf /tmp/linux-final-project
git clone https://github.com/Neltharion-afk/linux-final-project.git /tmp/linux-final-project
sudo bash /tmp/linux-final-project/scripts/restore/frontend.sh
```

```
sudo systemctl status nginx | grep Active
curl -I http://localhost
curl http://localhost:9090/targets
```

**Ожидаемый результат: Active (running), HTTP/1.1 200 OK и список таргетов в статусе UP.**

## Сценарий: Упал MySQL Master (192.168.205.105)

**Признаки: Сайт открывается, но не пускает в админку, или ```WordPress``` пишет ```Error establishing a database connection```. ```Slave``` при этом жив.**

1. Действия на новой чистой VM (назначить IP ```192.168.205.105```):

```
sudo apt update && sudo apt install -y git
sudo rm -rf /tmp/linux-final-project
git clone https://github.com/Neltharion-afk/linux-final-project.git /tmp/linux-final-project
sudo bash /tmp/linux-final-project/scripts/restore/mysql-master.sh
```

**2. Получи координаты на новом мастере:**
```
mysql -u root -p'MasterPass123!' -e "SHOW BINARY LOG STATUS\G"
```
(Запиши File и Position).

```
set +H
mysql -u root -p'SlavePass123!' -e "STOP REPLICA;"
mysql -u root -p'SlavePass123!' -e "CHANGE REPLICATION SOURCE TO SOURCE_HOST='192.168.205.105', SOURCE_USER='replicator', SOURCE_PASSWORD='Repl1c@torPass!', SOURCE_LOG_FILE='<File>', SOURCE_LOG_POS=<Position>, GET_SOURCE_PUBLIC_KEY=1;"
mysql -u root -p'SlavePass123!' -e "START REPLICA;"
```

**Проверка:**
```
mysql -u root -p'SlavePass123!' -e "SHOW REPLICA STATUS\G" | grep -E "Replica_IO_Running|Replica_SQL_Running"
```

**Ожидаемый результат: ```Replica_IO_Running: Yes```, ```Replica_SQL_Running: Yes```.**

## Сценарий: Упал ```MySQL Slave``` (192.168.205.106)

**Признаки: Сайт работает, но бэкапы не делаются. Ошибка при ```SHOW REPLICA STATUS``` на слейве.**

**Действия на новой чистой VM (назначить IP ```192.168.205.106```):**

```
sudo apt update && sudo apt install -y git
sudo rm -rf /tmp/linux-final-project
git clone https://github.com/Neltharion-afk/linux-final-project.git /tmp/linux-final-project
sudo bash /tmp/linux-final-project/scripts/restore/mysql-slave.sh
```

```
mysql -u root -p'SlavePass123!' -e "SHOW REPLICA STATUS\G" | grep -E "Replica_IO_Running|Replica_SQL_Running"
ls -lh /backup/mysql/
```

**Ожидаемый результат: ```Replica_IO_Running: Yes```, ```Replica_SQL_Running: Yes``` и свежие дампы в папке.**

## Сценарий: Упал ELK (192.168.205.107)

**Признаки: Логи в Kibana не обновляются.**

**Действия на новой чистой VM (назначить IP ```192.168.205.107```):**

```
sudo apt update && sudo apt install -y git
sudo rm -rf /tmp/linux-final-project
git clone https://github.com/Neltharion-afk/linux-final-project.git /tmp/linux-final-project
sudo bash /tmp/linux-final-project/scripts/restore/elk.sh
```

**Проверка:**
```
curl -k -u elastic:bdKp-nSdx_R8Boo2A_9h "https://localhost:9200/_cat/indices/nginx*?v"
```

**Ожидаемый результат: индекс nginx-* с документами.**

## Сценарий: Полное восстановление с нуля (упало всё)

Поднять 6 чистых VM с Ubuntu Server.

Настроить сеть и ```/etc/hosts``` (см. Шаг 1 ниже).

Восстановить ```MySQL Master``` (см. сценарий выше).

Восстановить ```MySQL Slave``` (см. сценарий выше).

Восстановить ```Backend 1``` (см. сценарий выше).

Восстановить ```Backend 2``` (см. сценарий выше).

Восстановить ```Frontend``` (см. сценарий выше).

Восстановить ```ELK``` (см. сценарий выше).

## Шаг 7. Финальная проверка всей системы

```curl http://192.168.205.102``` — ```WordPress``` открывается.

```sudo mysql -e "SHOW REPLICA STATUS\G"``` на slave — ```Replica_IO_Running: Yes```, ```Replica_SQL_Running: Yes```.

```curl http://192.168.205.102:9090/targets``` — все UP.

```curl http://192.168.205.102:3000``` — Grafana работает.

```curl http://192.168.205.107:5601``` — Kibana открывается.
