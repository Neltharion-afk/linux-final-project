# Linux Final Project

Отказоустойчивый веб-сервер с балансировкой нагрузки.

## Архитектура

- **vm1-frontend** (192.168.205.101): nginx (балансировщик), Prometheus, Grafana, Docker
- **vm2-backend1** (192.168.205.102): apache (8080), WordPress
- **vm3-backend2** (192.168.205.103): apache (8081), WordPress
- **vm4-master** (192.168.205.104): MySQL Master
- **vm5-slave** (192.168.205.105): MySQL Slave + бэкапы

## Компоненты

- nginx upstream балансировка
- MySQL master-slave репликация
- Скрипт бэкапа потаблично с позицией binlog
- Prometheus + Grafana мониторинг
- ELK сбор логов

## Восстановление

См. [RECOVERY.md](RECOVERY.md)
