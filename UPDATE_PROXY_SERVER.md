# Обновление прокси-сервера на arabica26.ru

## ✅ Файл обновлен в репозитории

Я обновил файл `loyalty-proxy/index.js` с новым URL Google Apps Script:
```
https://script.google.com/macros/s/AKfycbzaH6AqH8j9E93Tf4SFCie35oeESGfBL6p51cTHl9EvKq0Y5bfzg4UbmsDKB1B82yPS/exec
```

## 📋 Что нужно сделать на сервере arabica26.ru:

### Шаг 1: Подключитесь к серверу

```bash
ssh user@arabica26.ru
# или используйте ваш способ подключения
```

### Шаг 2: Перейдите в директорию прокси-сервера

```bash
cd /path/to/loyalty-proxy
# или где находится ваш прокси-сервер
```

### Шаг 3: Обновите код с GitHub

```bash
git pull origin main
```

Или вручную обновите файл `index.js`:

Откройте файл `loyalty-proxy/index.js` и измените строку 11:

**Было:**
```javascript
const SCRIPT_URL = process.env.SCRIPT_URL || "https://script.google.com/macros/s/AKfycbz0ROkJVhliPpWSTlXqJbfqu4LXbRzvMxmWqWZv6jR2K14pBbxvVGsf8PBR-3mYzgda/exec";
```

**Стало:**
```javascript
const SCRIPT_URL = process.env.SCRIPT_URL || "https://script.google.com/macros/s/AKfycbzaH6AqH8j9E93Tf4SFCie35oeESGfBL6p51cTHl9EvKq0Y5bfzg4UbmsDKB1B82yPS/exec";
```

### Шаг 4: Перезапустите прокси-сервер

**Если используете PM2:**
```bash
pm2 restart loyalty-proxy
# или
pm2 restart all
```

**Если используете systemd:**
```bash
sudo systemctl restart loyalty-proxy
```

**Если запускаете вручную:**
```bash
# Остановите процесс (Ctrl+C или kill)
# Запустите заново:
node index.js
# или
npm start
```

### Шаг 5: Проверьте работу

Проверьте, что сервер работает:

```bash
curl "https://arabica26.ru?action=getUserRole&phone=79054443224"
```

Должен вернуться JSON:
```json
{
  "success": true,
  "clientName": "Имя",
  "employeeName": null,
  "isAdmin": 0
}
```

## ✅ После обновления:

1. Прокси-сервер будет использовать новый URL Google Apps Script
2. Endpoint `getUserRole` будет работать правильно
3. Система ролей будет полностью функциональна

## 🔍 Проверка в приложении:

После обновления прокси-сервера, в консоли приложения должно быть:
```
✅ Роль определена: client/employee/admin
```

Вместо:
```
! Сервер вернул success: false
```









