#!/bin/bash
# Скрипт для отката к контрольной точке
# Использование: ./restore_checkpoint.sh [имя_тега]

TAG=$1

if [ -z "$TAG" ]; then
    echo "📋 Доступные контрольные точки:"
    git tag -l | sort -V
    echo ""
    echo "Использование: ./restore_checkpoint.sh [имя_тега]"
    exit 1
fi

cd /root/arabica_app || exit 1

# Проверяем, существует ли тег
if ! git tag -l | grep -q "^$TAG$"; then
    echo "❌ Ошибка: тег '$TAG' не найден"
    echo ""
    echo "Доступные теги:"
    git tag -l | sort -V
    exit 1
fi

echo "⚠️  ВНИМАНИЕ: Вы собираетесь откатиться к версии: $TAG"
echo "   Текущая ветка: $(git branch --show-current)"
echo ""
read -p "Продолжить? (y/N): " -n 1 -r
echo ""

if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "❌ Отменено"
    exit 1
fi

# Сохраняем текущее состояние
CURRENT_BRANCH=$(git branch --show-current)
BACKUP_BRANCH="backup-$(date +%Y-%m-%d-%H%M)-before-restore"

echo "💾 Создание резервной копии текущего состояния..."
git branch "$BACKUP_BRANCH" 2>/dev/null || true

echo "🔄 Откат к версии: $TAG"
git checkout "$TAG"

echo ""
echo "✅ Откат выполнен!"
echo "   Текущая версия: $TAG"
echo "   Резервная копия сохранена в ветке: $BACKUP_BRANCH"
echo ""
echo "Для возврата к последней версии:"
echo "   git checkout $CURRENT_BRANCH"
echo ""
echo "Для создания новой ветки от этой версии:"
echo "   git checkout -b restore-$TAG"

















