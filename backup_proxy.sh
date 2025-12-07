#!/bin/bash
# Скрипт для создания бэкапа конфигурации прокси-сервера
# Использование: ./backup_proxy.sh

BACKUP_DIR="/root/loyalty-proxy/backups"
TIMESTAMP=$(date +%Y-%m-%d-%H%M%S)
BACKUP_FILE="$BACKUP_DIR/index.js.$TIMESTAMP"

mkdir -p "$BACKUP_DIR"

if [ -f "/root/loyalty-proxy/index.js" ]; then
    cp /root/loyalty-proxy/index.js "$BACKUP_FILE"
    echo "✅ Бэкап создан: $BACKUP_FILE"
    
    # Оставляем только последние 10 бэкапов
    ls -t "$BACKUP_DIR"/index.js.* 2>/dev/null | tail -n +11 | xargs rm -f 2>/dev/null || true
    
    echo "📋 Последние бэкапы:"
    ls -lt "$BACKUP_DIR"/index.js.* 2>/dev/null | head -5 || echo "   (нет бэкапов)"
else
    echo "❌ Файл /root/loyalty-proxy/index.js не найден"
    exit 1
fi







