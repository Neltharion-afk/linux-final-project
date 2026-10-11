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

# ==== 1. Полный дамп с БД ====
FULL_DUMP="$BACKUP_DIR/${DB_NAME}_FULL_${DATE}.sql"
log "Creating full dump: $(basename $FULL_DUMP)"

mysqldump -u "$MYSQL_USER" ${MYSQL_PASS:+-p"$MYSQL_PASS"} \
    --single-transaction \
    --source-data=2 \
    --skip-lock-tables \
    --databases "$DB_NAME" > "$FULL_DUMP" 2>>"$LOG_FILE"

if [ $? -ne 0 ]; then
    log "ERROR: Full dump failed"
    exit 1
fi

log "Full dump OK ($(du -h $FULL_DUMP | cut -f1))"

# ==== 2. Извлекаем позицию BINLOG из полного дампа ====
BINLOG_LINE=$(grep -m1 "CHANGE REPLICATION SOURCE TO" "$FULL_DUMP")
BINLOG_FILE=$(echo "$BINLOG_LINE" | sed -n "s/.*SOURCE_LOG_FILE='\([^']*\)'.*/\1/p")
BINLOG_POS=$(echo "$BINLOG_LINE" | sed -n "s/.*SOURCE_LOG_POS=\([0-9]*\).*/\1/p")

if [ -z "$BINLOG_FILE" ] || [ -z "$BINLOG_POS" ]; then
    log "WARNING: Could not extract binlog position from full dump"
else
    log "Binlog position from full dump: $BINLOG_FILE:$BINLOG_POS"
fi

# ==== 3. Потабличные дампы  ====
TABLES=$(mysql -u "$MYSQL_USER" ${MYSQL_PASS:+-p"$MYSQL_PASS"} -N -e "SHOW TABLES FROM $DB_NAME")

if [ -z "$TABLES" ]; then
    log "WARNING: No tables found in $DB_NAME"
else
    for TABLE in $TABLES; do
        FILE="$BACKUP_DIR/${DB_NAME}_${TABLE}_${DATE}.sql"
        mysqldump -u "$MYSQL_USER" ${MYSQL_PASS:+-p"$MYSQL_PASS"} \
            --single-transaction \
            --skip-lock-tables \
            "$DB_NAME" "$TABLE" > "$FILE" 2>>"$LOG_FILE"

        if [ $? -eq 0 ]; then
            log "Table $TABLE -> $(basename $FILE) ($(du -h $FILE | cut -f1))"
        else
            log "ERROR: Failed to backup table $TABLE"
        fi
    done
fi

# ==== 4. Сщхраняем метаданные ====
META_FILE="$BACKUP_DIR/backup_${DATE}.meta"
cat > "$META_FILE" << EOF
DATE=$DATE
DB_NAME=$DB_NAME
FULL_DUMP=$(basename $FULL_DUMP)
BINLOG_FILE=$BINLOG_FILE
BINLOG_POS=$BINLOG_POS
EOF

log "Metadata saved to $META_FILE"
log "===== Backup completed ====="
