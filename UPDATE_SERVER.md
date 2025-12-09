# Инструкция по обновлению сервера

## Быстрое обновление (если есть доступ к серверу):

```bash
# 1. Подключитесь к серверу
ssh root@62.113.41.32

# 2. Перейдите в директорию проекта
cd /path/to/loyalty-proxy

# 3. Обновите код из GitHub
git pull origin main

# 4. Установите зависимости
npm install

# 5. Создайте директорию для фото
mkdir -p /var/www/shift-photos
chmod 755 /var/www/shift-photos

# 6. Перезапустите сервер
pm2 restart loyalty-proxy
```

## Или используйте автоматический скрипт:

```bash
cd /path/to/loyalty-proxy
./update-server.sh
```

## Что обновлено:

1. ✅ Добавлен эндпоинт `POST /upload-photo` для загрузки фото
2. ✅ Добавлен эндпоинт `POST /api/recount-reports` для создания отчетов
3. ✅ Добавлен эндпоинт `GET /api/recount-reports` для получения отчетов
4. ✅ Добавлен эндпоинт `POST /api/recount-reports/:id/rating` для оценки
5. ✅ Добавлен эндпоинт `POST /api/recount-reports/:id/notify` для уведомлений
6. ✅ Добавлена статическая раздача фото через `/shift-photos`
7. ✅ Автоматическое создание директории `/var/www/shift-photos`
8. ✅ Добавлена зависимость `multer` для обработки файлов

## Проверка работы:

После обновления проверьте:

```bash
# Проверка загрузки фото
curl -X POST -F "photo=@test.jpg" https://arabica26.ru/upload-photo

# Проверка создания отчета
curl -X POST https://arabica26.ru/api/recount-reports \
  -H "Content-Type: application/json" \
  -d '{"id":"test","employeeName":"Test","shopAddress":"Test"}'
```

## Если сервер не запускается:

1. Проверьте логи:
   ```bash
   pm2 logs loyalty-proxy
   ```

2. Проверьте, что порт 3000 свободен:
   ```bash
   netstat -tulpn | grep 3000
   ```

3. Проверьте права на директорию:
   ```bash
   ls -la /var/www/shift-photos
   ```




