#!/bin/bash
# ===========================================
# ARABICA BACKUP SCRIPT
# Запускать через cron: 0 2 * * * /root/arabica_app/loyalty-proxy/backup-script.sh
# ===========================================

BACKUP_DIR="/var/backups/arabica"
DATA_DIR="/var/www"
DATE=$(date +%Y%m%d_%H%M%S)
BACKUP_FILE="$BACKUP_DIR/arabica_$DATE.tar.gz"
MAX_BACKUPS=7  # Хранить бэкапы за последние 7 дней

# Создать директорию для бэкапов если не существует
mkdir -p $BACKUP_DIR

echo "🚀 Starting backup at $(date)"

# Создать архив всех данных
tar -czf $BACKUP_FILE \
  $DATA_DIR/employees \
  $DATA_DIR/shops \
  $DATA_DIR/shift-reports \
  $DATA_DIR/shift-handover-reports \
  $DATA_DIR/recount-reports \
  $DATA_DIR/envelope-reports \
  $DATA_DIR/rko-reports \
  $DATA_DIR/attendance \
  $DATA_DIR/orders \
  $DATA_DIR/clients \
  $DATA_DIR/efficiency-penalties \
  $DATA_DIR/bonus-penalties \
  $DATA_DIR/task-assignments \
  $DATA_DIR/recurring-tasks \
  $DATA_DIR/suppliers \
  $DATA_DIR/training-articles \
  $DATA_DIR/test-questions \
  $DATA_DIR/test-results \
  $DATA_DIR/fortune-wheel \
  $DATA_DIR/employee-ratings \
  $DATA_DIR/referral-clients \
  $DATA_DIR/work-schedule \
  $DATA_DIR/shop-settings \
  $DATA_DIR/points-settings \
  $DATA_DIR/employee-chats \
  $DATA_DIR/employee-chat-groups \
  $DATA_DIR/withdrawals \
  $DATA_DIR/geofence-settings.json \
  $DATA_DIR/loyalty-promo.json \
  2>/dev/null

if [ $? -eq 0 ]; then
  SIZE=$(du -h $BACKUP_FILE | cut -f1)
  echo "✅ Backup created: $BACKUP_FILE ($SIZE)"
else
  echo "❌ Backup failed!"
  exit 1
fi

# Удалить старые бэкапы (оставить только последние MAX_BACKUPS)
cd $BACKUP_DIR
ls -t arabica_*.tar.gz | tail -n +$((MAX_BACKUPS + 1)) | xargs -r rm -f

echo "🧹 Old backups cleaned (keeping last $MAX_BACKUPS)"
echo "✅ Backup complete at $(date)"
