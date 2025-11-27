#!/bin/bash
# Скрипт для создания контрольных точек (Git тегов)
# Использование: ./create_checkpoint.sh [имя_тега] [описание]

VERSION=$1
DESCRIPTION=$2

if [ -z "$VERSION" ]; then
    VERSION="backup-$(date +%Y-%m-%d-%H%M)"
fi

if [ -z "$DESCRIPTION" ]; then
    DESCRIPTION="Checkpoint: $VERSION"
fi

cd /root/arabica_app || exit 1

echo "📦 Создание контрольной точки: $VERSION"
echo "   Описание: $DESCRIPTION"

# Проверяем, есть ли незакоммиченные изменения
if [ -n "$(git status --porcelain)" ]; then
    echo "⚠️  Обнаружены незакоммиченные изменения. Коммитим их..."
    git add -A
    git commit -m "Auto-commit before checkpoint: $VERSION" || true
fi

# Создаем тег
if git tag -a "$VERSION" -m "$DESCRIPTION" 2>/dev/null; then
    echo "✅ Тег создан: $VERSION"
else
    echo "❌ Ошибка: тег $VERSION уже существует"
    echo "   Используйте другое имя или удалите существующий тег: git tag -d $VERSION"
    exit 1
fi

# Отправляем на сервер
echo "📤 Отправка тега на сервер..."
git push origin main
git push origin "$VERSION"

echo ""
echo "✅ Контрольная точка создана успешно!"
echo "   Тег: $VERSION"
echo "   Для отката используйте: git checkout $VERSION"
echo "   Для просмотра всех тегов: git tag -l"

