# Скрипт для проверки Flutter приложения
# Использование: .\test_app.ps1

Write-Host "=== Проверка Flutter приложения Arabica ===" -ForegroundColor Green
Write-Host ""

# 1. Проверка версии Flutter
Write-Host "1. Проверка версии Flutter..." -ForegroundColor Yellow
flutter --version
if ($LASTEXITCODE -ne 0) {
    Write-Host "ОШИБКА: Flutter не установлен или не найден в PATH" -ForegroundColor Red
    exit 1
}
Write-Host ""

# 2. Проверка окружения
Write-Host "2. Проверка окружения Flutter..." -ForegroundColor Yellow
flutter doctor
Write-Host ""

# 3. Проверка зависимостей
Write-Host "3. Проверка зависимостей проекта..." -ForegroundColor Yellow
flutter pub get
if ($LASTEXITCODE -ne 0) {
    Write-Host "ОШИБКА: Не удалось установить зависимости" -ForegroundColor Red
    exit 1
}
Write-Host ""

# 4. Анализ кода
Write-Host "4. Анализ кода..." -ForegroundColor Yellow
flutter analyze
Write-Host ""

# 5. Проверка подключенных устройств
Write-Host "5. Проверка доступных устройств..." -ForegroundColor Yellow
flutter devices
Write-Host ""

# 6. Сборка в режиме отладки (без запуска)
Write-Host "6. Проверка сборки приложения..." -ForegroundColor Yellow
Write-Host "Выберите платформу для проверки:" -ForegroundColor Cyan
Write-Host "  [1] Android (APK)"
Write-Host "  [2] Web"
Write-Host "  [3] Windows"
Write-Host "  [4] Linux"
Write-Host "  [5] Пропустить сборку"
Write-Host ""
$choice = Read-Host "Введите номер (1-5)"

switch ($choice) {
    "1" {
        Write-Host "Сборка Android APK..." -ForegroundColor Yellow
        flutter build apk --debug
    }
    "2" {
        Write-Host "Сборка Web..." -ForegroundColor Yellow
        flutter build web
    }
    "3" {
        Write-Host "Сборка Windows..." -ForegroundColor Yellow
        flutter build windows
    }
    "4" {
        Write-Host "Сборка Linux..." -ForegroundColor Yellow
        flutter build linux
    }
    "5" {
        Write-Host "Сборка пропущена" -ForegroundColor Gray
    }
    default {
        Write-Host "Неверный выбор, сборка пропущена" -ForegroundColor Gray
    }
}

Write-Host ""
Write-Host "=== Проверка завершена ===" -ForegroundColor Green
Write-Host ""
Write-Host "Для запуска приложения используйте:" -ForegroundColor Cyan
Write-Host "  flutter run                    # Запуск на подключенном устройстве"
Write-Host "  flutter run -d chrome          # Запуск в браузере Chrome"
Write-Host "  flutter run -d windows         # Запуск на Windows"
Write-Host "  flutter run -d linux           # Запуск на Linux"
Write-Host "  flutter run -d android         # Запуск на Android"






