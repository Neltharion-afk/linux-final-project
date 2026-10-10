#!/bin/bash

# ==== Настройки ====
BACKUP_DIR="/backup/mysql"
DB_NAME="wordpress"
DATE=$(date +%Y%m%d_%H%M%S)
LOG_FILE="/var/log/mysql_backup.log"
MYSQL_USER="root"
MYSQL_PASS=""

# ==== Функция логирования ====
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"
}

# ==== Начало ====
log "===== Backup started ====="
mkdir -p "$BACKUP_DIR"

# ==== Получение позиции binlog на Slave ====
BINLOG_INFO=$(mysql -u "$MYSQL_USER" ${MYSQL_PASS:+-p"$MYSQL_PASS"} -e "SHOW BINARY LOG STATUS\G" 2>/dev/null)
BINLOG_FILE=$(echo "$BINLOG_INFO" | grep "File:" | awk '{print $2}')
BINLOG_POS=$(echo "$BINLOG_INFO" | grep "Position:" | awk '{print $2}')
log "Binlog position: $BINLOG_FILE:$BINLOG_POS"

# ==== Получение списка таблиц ====
TABLES=$(mysql -u "$MYSQL_USER" ${MYSQL_PASS:+-p"$MYSQL_PASS"} -N -e "SHOW TABLES FROM $DB_NAME")

if [ -z "$TABLES" ]; then
    log "ERROR: No tables found in $DB_NAME"
    exit 1
fi

# ==== Бэкап каждой таблицы ====
for TABLE in $TABLES; do
    FILE="$BACKUP_DIR/${DB_NAME}_${TABLE}_${DATE}.sql"
    mysqldump -u "$MYSQL_USER" ${MYSQL_PASS:+-p"$MYSQL_PASS"} \
        --single-transaction \
        --source-data=2 \
        --skip-lock-tables \
        "$DB_NAME" "$TABLE" > "$FILE" 2>>"$LOG_FILE"

    if [ $? -eq 0 ]; then
        log "Table $TABLE -> $(basename $FILE) ($(du -h $FILE | cut -f1))"
    else
        log "ERROR: Failed to backup table $TABLE"
    fi
done

# ==== Сохранение метаданных ====
META_FILE="$BACKUP_DIR/last_binlog_${DATE}.meta"
echo "DATE=$DATE" > "$META_FILE"
echo "BINLOG_FILE=$BINLOG_FILE" >> "$META_FILE"
echo "BINLOG_POS=$BINLOG_POS" >> "$META_FILE"
log "Metadata saved to $META_FILE"

log "===== Backup completed ====="
