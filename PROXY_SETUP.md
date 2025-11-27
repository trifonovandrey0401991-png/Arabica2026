# Настройка прокси-сервера для регистрации

## Проблема

При запуске приложения появляется ошибка:
```
Ошибка регистрации: Exception: Ошибка при отправке запроса: 
ClientException: Failed to fetch, uri=http://127.0.0.1:3000
```

Это означает, что приложение пытается подключиться к локальному прокси-серверу, который не запущен.

## Решение 1: Использовать прямой URL (рекомендуется)

Если у вас есть рабочий URL сервера (`https://arabica26.ru`), убедитесь, что он правильно настроен в `lib/google_script_config.dart`:

```dart
const String googleScriptUrl = 'https://arabica26.ru';
```

## Решение 2: Запустить локальный прокси-сервер

Если нужно использовать локальный прокси для разработки:

### Шаг 1: Установите зависимости Node.js

```powershell
# Перейдите в папку прокси
cd loyalty-proxy

# Установите зависимости
npm install express node-fetch body-parser cors
```

### Шаг 2: Настройте URL в прокси

Откройте `loyalty-proxy/index.js` и замените:
```javascript
const SCRIPT_URL = "ТВОЙ_URL_ОТ_APPS_SCRIPT";
```

На реальный URL вашего Google Apps Script, например:
```javascript
const SCRIPT_URL = "https://script.google.com/macros/s/AKfycby.../exec";
```

Или если используете `https://arabica26.ru`:
```javascript
const SCRIPT_URL = "https://arabica26.ru";
```

### Шаг 3: Запустите прокси-сервер

```powershell
# В папке loyalty-proxy
node index.js
```

Вы должны увидеть:
```
Proxy listening on port 3000
```

### Шаг 4: Обновите конфигурацию приложения

Откройте `lib/google_script_config.dart` и измените на:
```dart
const String googleScriptUrl = 'http://127.0.0.1:3000';
```

### Шаг 5: Перезапустите приложение

```powershell
flutter run -d chrome
```

## Решение 3: Проверить доступность сервера

Проверьте, доступен ли сервер `https://arabica26.ru`:

### В браузере:
Откройте: `https://arabica26.ru?action=getClient&phone=%2B79001234567`

### Через curl (Linux/Mac):
```bash
curl "https://arabica26.ru?action=getClient&phone=%2B79001234567"
```

### Через PowerShell (Windows):
```powershell
Invoke-WebRequest -Uri "https://arabica26.ru?action=getClient&phone=%2B79001234567"
```

Если сервер не отвечает, нужно:
1. Проверить, что сервер запущен
2. Проверить настройки CORS
3. Использовать прокси-сервер

## Быстрая проверка

1. **Проверьте текущий URL в коде:**
   ```powershell
   cat lib/google_script_config.dart
   ```

2. **Если используется `https://arabica26.ru`:**
   - Убедитесь, что сервер доступен
   - Проверьте CORS настройки на сервере

3. **Если нужно использовать прокси:**
   - Запустите `node loyalty-proxy/index.js`
   - Измените URL на `http://127.0.0.1:3000`

## Примечание

Для работы в браузере Chrome может потребоваться прокси-сервер из-за ограничений CORS. Для мобильных приложений можно использовать прямой URL.






