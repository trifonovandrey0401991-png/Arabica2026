# Исправление проблемы с сервером

## Проблема

Сервер `https://arabica26.ru` возвращает HTML вместо JSON:
```
POST error: FetchError: invalid json response body... Unexpected token '<', "<html>"... is not valid JSON
```

## Решение

Сервер `https://arabica26.ru` не настроен для работы с JSON API напрямую. Нужно использовать прокси-сервер.

### Шаг 1: Убедитесь, что конфигурация правильная

В файле `lib/google_script_config.dart` должно быть:
```dart
const String googleScriptUrl = 'http://127.0.0.1:3000';
```

### Шаг 2: Запустите прокси-сервер

В отдельном окне PowerShell:
```powershell
cd arabica_app\loyalty-proxy
node index.js
```

### Шаг 3: Перезапустите Flutter приложение

В окне с Flutter нажмите `R` для hot restart.

## Альтернативное решение

Если у вас есть правильный URL Google Apps Script, измените в `loyalty-proxy/index.js`:

```javascript
const SCRIPT_URL = "https://script.google.com/macros/s/ВАШ_SCRIPT_ID/exec";
```

Или если сервер должен работать по другому пути:
```javascript
const SCRIPT_URL = "https://arabica26.ru/api";
// или
const SCRIPT_URL = "https://arabica26.ru/exec";
```

## Проверка

После запуска прокси-сервера в консоли должны появляться логи:
- `POST request to script: https://arabica26.ru`
- `Response status: 200`
- `Response content-type: application/json`

Если видите ошибку про HTML, значит URL сервера неправильный или сервер не настроен для API.






