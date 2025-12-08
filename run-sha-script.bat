@echo off
REM Batch файл для запуска PowerShell скрипта с обходом политики выполнения
REM Использование: просто дважды кликните на этот файл

echo Запуск скрипта для получения SHA-сертификатов...
echo.

powershell -ExecutionPolicy Bypass -File "%~dp0get-sha-certificates.ps1"

pause




