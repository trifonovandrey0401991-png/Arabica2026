@echo off
echo ========================================
echo  Arabica Loyalty Proxy - Local Dev
echo ========================================
echo.

REM Проверка Node.js
where node >nul 2>nul
if %ERRORLEVEL% NEQ 0 (
    echo ERROR: Node.js not found!
    echo Please install Node.js from https://nodejs.org/
    pause
    exit /b 1
)

echo Node.js version:
node --version
echo.

REM Создание тестовой структуры
echo Setting up test data...
node setup-local.js
echo.

REM Запуск сервера
echo Starting server...
set DATA_DIR=./test-data
node index.js
