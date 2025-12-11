#!/bin/bash

# Скрипт для настройки сервера для отчетов пересчета

echo "🔧 Настройка сервера для отчетов пересчета..."

# 1. Создание директории для фото
echo "1. Создание директории для фото..."
mkdir -p /var/www/shift-photos
chmod 755 /var/www/shift-photos
chown www-data:www-data /var/www/shift-photos 2>/dev/null || chown nginx:nginx /var/www/shift-photos 2>/dev/null || echo "⚠️ Не удалось изменить владельца, проверьте права вручную"
echo "✅ Директория создана: /var/www/shift-photos"

# 2. Установка зависимостей
echo ""
echo "2. Установка зависимостей Node.js..."
if [ -f "package.json" ]; then
    npm install
    echo "✅ Зависимости установлены"
else
    echo "❌ Файл package.json не найден"
    exit 1
fi

# 3. Проверка установки multer
echo ""
echo "3. Проверка установки multer..."
if npm list multer > /dev/null 2>&1; then
    echo "✅ multer установлен"
else
    echo "⚠️ multer не найден, устанавливаем..."
    npm install multer
fi

echo ""
echo "✅ Настройка завершена!"
echo ""
echo "Следующие шаги:"
echo "1. Перезапустите сервер Node.js:"
echo "   pm2 restart loyalty-proxy"
echo "   или"
echo "   node index.js"
echo ""
echo "2. Проверьте работу:"
echo "   curl -X POST -F 'photo=@test.jpg' https://arabica26.ru/upload-photo"






