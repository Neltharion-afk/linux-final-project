# Анализ HTTP-сессии через tcpdump

## Захват
- На backend1: `tcpdump -i any -nn -w /tmp/http_capture.pcap 'tcp port 8080'`
- С frontend: `curl http://192.168.205.103:8080`

## Трёхсторонний handshake
1. Client → Server: SYN (флаг [S])
2. Server → Client: SYN/ACK (флаг [S.])
3. Client → Server: ACK (флаг [.])

## HTTP-обмен
- Запрос: `GET / HTTP/1.1` с Host: 192.168.205.103:8080
- Ответ: `HTTP/1.1 200 OK` с телом `<h1>Backend1 - port 8080</h1>`

## Файлы
- http_capture.pcap — сырой дамп
