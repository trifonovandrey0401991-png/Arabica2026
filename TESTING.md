# Инструкция по проверке приложения

## Быстрая проверка через терминал/PowerShell

### Windows (PowerShell)

```powershell
# Перейти в директорию проекта
cd arabica_app

# Запустить скрипт проверки
.\test_app.ps1
```

### Linux/Mac (Bash)

```bash
# Перейти в директорию проекта
cd arabica_app

# Сделать скрипт исполняемым
chmod +x test_app.sh

# Запустить скрипт проверки
./test_app.sh
```

## Ручная проверка (пошагово)

### 1. Проверка установки Flutter

```powershell
# Windows PowerShell
flutter --version

# Linux/Mac
flutter --version
```

### 2. Проверка окружения

```powershell
flutter doctor
```

Это покажет:
- Установлен ли Flutter SDK
- Настроен ли Android Studio / Xcode
- Подключены ли устройства/эмуляторы

### 3. Установка зависимостей

```powershell
cd arabica_app
flutter pub get
```

### 4. Анализ кода на ошибки

```powershell
flutter analyze
```

### 5. Проверка доступных устройств

```powershell
flutter devices
```

Вы увидите список доступных устройств:
- Эмуляторы Android
- Физические устройства
- Браузеры (Chrome, Edge)
- Desktop платформы (Windows, Linux, macOS)

### 6. Запуск приложения

#### На подключенном устройстве/эмуляторе:
```powershell
flutter run
```

#### На конкретном устройстве:
```powershell
# Android эмулятор
flutter run -d android

# iOS симулятор (только Mac)
flutter run -d ios

# Chrome браузер
flutter run -d chrome

# Windows
flutter run -d windows

# Linux
flutter run -d linux
```

#### В режиме отладки с горячей перезагрузкой:
```powershell
flutter run --debug
```

#### В режиме релиза:
```powershell
flutter run --release
```

### 7. Сборка приложения (без запуска)

#### Android APK:
```powershell
# Debug версия
flutter build apk --debug

# Release версия
flutter build apk --release
```

#### Web:
```powershell
flutter build web
```

#### Windows:
```powershell
flutter build windows
```

#### Linux:
```powershell
flutter build linux
```

## Проверка конкретных функций

### Проверка регистрации пользователя

1. Запустите приложение
2. При первом запуске должно открыться окно регистрации
3. Заполните имя и номер телефона
4. После регистрации должно появиться приветствие "Здравствуйте, [имя]!"

### Проверка проверки номера в базе

1. Зарегистрируйте пользователя
2. Закройте приложение
3. Запустите снова
4. Приложение должно проверить номер в базе и показать приветствие

### Тестирование без реального устройства

#### Использование эмулятора Android:

1. Установите Android Studio
2. Создайте эмулятор через AVD Manager
3. Запустите эмулятор
4. Выполните: `flutter run`

#### Использование браузера:

```powershell
flutter run -d chrome
```

**Примечание:** Некоторые функции (камера для QR-сканера) могут не работать в браузере.

## Полезные команды

### Просмотр логов в реальном времени:
```powershell
flutter run --verbose
```

### Очистка проекта:
```powershell
flutter clean
flutter pub get
```

### Обновление зависимостей:
```powershell
flutter pub upgrade
```

### Проверка форматирования кода:
```powershell
flutter format .
```

### Запуск тестов:
```powershell
flutter test
```

## Устранение проблем

### Flutter не найден:
- Убедитесь, что Flutter добавлен в PATH
- Перезапустите терминал/PowerShell

### Нет доступных устройств:
- Для Android: запустите эмулятор или подключите устройство с включенной отладкой
- Для Web: установите Chrome
- Для Desktop: выполните `flutter config --enable-windows-desktop` (или linux/macos)

### Ошибки сборки:
```powershell
flutter clean
flutter pub get
flutter run
```



