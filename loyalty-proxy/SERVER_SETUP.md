# Инструкция по настройке сервера для отчетов пересчета

## 1. Создание директории для фото

Выполните на сервере:

```bash
mkdir -p /var/www/shift-photos
chmod 755 /var/www/shift-photos
chown www-data:www-data /var/www/shift-photos
```

## 2. Установка зависимостей

```bash
cd /path/to/loyalty-proxy
npm install
```

Это установит `multer` для обработки загрузки файлов.

## 3. Перезапуск сервера

```bash
# Если используется PM2:
pm2 restart loyalty-proxy

# Или если запущен напрямую:
# Остановите текущий процесс и запустите заново
node index.js
```

## 4. Проверка работы

После перезапуска проверьте:

1. **Загрузка фото:**
   ```bash
   curl -X POST -F "photo=@test.jpg" https://arabica26.ru/upload-photo
   ```

2. **Создание отчета:**
   ```bash
   curl -X POST https://arabica26.ru/api/recount-reports \
     -H "Content-Type: application/json" \
     -d '{"id":"test","employeeName":"Test","shopAddress":"Test"}'
   ```

## Добавленные эндпоинты:

- `POST /upload-photo` - загрузка фото для пересменки и пересчета
- `POST /api/recount-reports` - создание отчета пересчета
- `GET /api/recount-reports` - получение списка отчетов
- `POST /api/recount-reports/:reportId/rating` - оценка отчета админом
- `POST /api/recount-reports/:reportId/notify` - отправка push-уведомления
- `GET /shift-photos/:filename` - получение фото (статическая раздача)

## Примечания:

- Фото сохраняются в `/var/www/shift-photos/`
- Доступ к фото через `https://arabica26.ru/shift-photos/filename.jpg`
- Максимальный размер файла: 10MB
- Отчеты отправляются в Google Apps Script (если поддерживается) или сохраняются локально


