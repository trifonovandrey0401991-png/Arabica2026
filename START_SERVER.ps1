# Скрипт для запуска прокси-сервера и Flutter приложения
# Использование: .\START_SERVER.ps1

Write-Host "=== Запуск Arabica App через прокси-сервер ===" -ForegroundColor Green
Write-Host ""

# Проверка Node.js
Write-Host "Проверка Node.js..." -ForegroundColor Yellow
try {
    $nodeVersion = node --version
    Write-Host "Node.js установлен: $nodeVersion" -ForegroundColor Green
} catch {
    Write-Host "ОШИБКА: Node.js не установлен!" -ForegroundColor Red
    Write-Host "Установите Node.js с https://nodejs.org/" -ForegroundColor Yellow
    exit 1
}

# Проверка Flutter
Write-Host "Проверка Flutter..." -ForegroundColor Yellow
try {
    $flutterVersion = flutter --version 2>&1 | Select-Object -First 1
    Write-Host "Flutter установлен" -ForegroundColor Green
} catch {
    Write-Host "ОШИБКА: Flutter не установлен!" -ForegroundColor Red
    Write-Host "Установите Flutter с https://flutter.dev/" -ForegroundColor Yellow
    exit 1
}

Write-Host ""
Write-Host "=== Инструкция ===" -ForegroundColor Cyan
Write-Host ""
Write-Host "1. Откройте ДВА терминала PowerShell" -ForegroundColor White
Write-Host ""
Write-Host "2. В ПЕРВОМ терминале выполните:" -ForegroundColor White
Write-Host "   cd arabica_app\loyalty-proxy" -ForegroundColor Yellow
Write-Host "   npm install" -ForegroundColor Yellow
Write-Host "   node index.js" -ForegroundColor Yellow
Write-Host ""
Write-Host "3. Во ВТОРОМ терминале выполните:" -ForegroundColor White
Write-Host "   cd arabica_app" -ForegroundColor Yellow
Write-Host "   # Сначала измените URL в lib/google_script_config.dart на:" -ForegroundColor Gray
Write-Host "   # const String googleScriptUrl = 'http://127.0.0.1:3000';" -ForegroundColor Gray
Write-Host "   flutter run -d chrome" -ForegroundColor Yellow
Write-Host ""
Write-Host "4. Оставьте оба терминала открытыми" -ForegroundColor White
Write-Host ""
Write-Host "Нажмите любую клавишу для автоматического запуска..." -ForegroundColor Cyan
$null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")

# Автоматический запуск
Write-Host ""
Write-Host "=== Запуск прокси-сервера ===" -ForegroundColor Green

# Переход в папку прокси
Set-Location "loyalty-proxy"

# Проверка и установка зависимостей
if (-not (Test-Path "node_modules")) {
    Write-Host "Установка зависимостей..." -ForegroundColor Yellow
    npm install
    if ($LASTEXITCODE -ne 0) {
        Write-Host "ОШИБКА: Не удалось установить зависимости" -ForegroundColor Red
        exit 1
    }
}

# Запуск прокси-сервера
Write-Host "Запуск прокси-сервера на порту 3000..." -ForegroundColor Green
Write-Host "Оставьте этот терминал открытым!" -ForegroundColor Yellow
Write-Host ""
node index.js

