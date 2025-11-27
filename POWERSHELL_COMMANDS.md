# Команды PowerShell для запуска приложения через сервер

## Быстрый старт

### Вариант 1: Автоматический запуск (рекомендуется)

```powershell
# Перейдите в папку проекта
cd arabica_app

# Запустите скрипт
.\START_SERVER.ps1
```

### Вариант 2: Ручной запуск (пошагово)

## Шаг 1: Настройка конфигурации

Сначала измените URL в файле `lib/google_script_config.dart`:

```dart
const String googleScriptUrl = 'http://127.0.0.1:3000';
```

**Важно:** Это нужно сделать ОДИН РАЗ перед первым запуском.

## Шаг 2: Откройте ДВА терминала PowerShell

Вам нужно два терминала:
- **Терминал 1** - для прокси-сервера
- **Терминал 2** - для Flutter приложения

## Шаг 3: Запуск прокси-сервера (Терминал 1)

```powershell
# Перейдите в папку прокси
cd arabica_app\loyalty-proxy

# Установите зависимости (только первый раз)
npm install

# Запустите прокси-сервер
node index.js
```

Вы должны увидеть:
```
Proxy listening on port 3000
```

**Оставьте этот терминал открытым!**

## Шаг 4: Запуск Flutter приложения (Терминал 2)

```powershell
# Перейдите в папку проекта
cd arabica_app

# Запустите приложение
flutter run -d chrome
```

Или для другого устройства:
```powershell
# Android эмулятор
flutter run -d android

# Windows
flutter run -d windows

# Linux
flutter run -d linux
```

## Полный пример команд

### Терминал 1 (Прокси-сервер):
```powershell
cd C:\путь\к\проекту\arabica_app\loyalty-proxy
npm install
node index.js
```

### Терминал 2 (Flutter):
```powershell
cd C:\путь\к\проекту\arabica_app
flutter run -d chrome
```

## Проверка работы

1. **Прокси-сервер работает**, если в Терминале 1 видно: `Proxy listening on port 3000`
2. **Приложение запущено**, если открылся браузер/эмулятор с приложением
3. **Регистрация работает**, если можно зарегистрировать пользователя без ошибок

## Остановка

1. В Терминале 2 нажмите `q` или `Ctrl+C` для остановки Flutter
2. В Терминале 1 нажмите `Ctrl+C` для остановки прокси-сервера

## Устранение проблем

### Ошибка: "npm не распознан"
```powershell
# Установите Node.js с https://nodejs.org/
# Перезапустите PowerShell после установки
```

### Ошибка: "port 3000 is already in use"
```powershell
# Порт 3000 занят, найдите и закройте процесс:
netstat -ano | findstr :3000
taskkill /PID <номер_процесса> /F
```

### Ошибка: "flutter не распознан"
```powershell
# Убедитесь, что Flutter добавлен в PATH
# Перезапустите PowerShell
flutter doctor
```

### Прокси не запускается
```powershell
# Проверьте, что вы в правильной папке
cd arabica_app\loyalty-proxy
ls  # Должен быть файл index.js

# Переустановите зависимости
rm -r node_modules
npm install
```

## Альтернатива: Использование прямого URL

Если сервер `https://arabica26.ru` доступен и поддерживает CORS, можно использовать прямой URL:

1. В `lib/google_script_config.dart` укажите:
   ```dart
   const String googleScriptUrl = 'https://arabica26.ru';
   ```

2. Запустите только Flutter (без прокси):
   ```powershell
   cd arabica_app
   flutter run -d chrome
   ```

**Примечание:** Для работы в браузере Chrome обычно требуется прокси из-за ограничений CORS.

## Полезные команды

### Проверка версий
```powershell
node --version
npm --version
flutter --version
```

### Очистка проекта Flutter
```powershell
cd arabica_app
flutter clean
flutter pub get
```

### Просмотр логов прокси
Логи прокси-сервера отображаются в Терминале 1 в реальном времени.

### Просмотр логов Flutter
Логи Flutter отображаются в Терминале 2. Для подробных логов:
```powershell
flutter run -d chrome --verbose
```






