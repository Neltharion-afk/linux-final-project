#!/bin/bash
# Запускать nginx в Docker с проброшенным конфигом балансировки
docker run -d \
--name nginx-dz \
-p 8090:80 \
-v /home/nikolay/linux-final-project/nginx/balance.conf:/etc/nginx/conf.d/default.conf:ro \nginx
