# Скрипт для исправления локального кода

Write-Host "🔧 Исправление локального кода..." -ForegroundColor Cyan

# 1. Разрешаем конфликт с файлами (сохраняем локальные версии)
Write-Host "`n1. Сохраняем локальные файлы..." -ForegroundColor Yellow
$files = @("fix-firebase-imports.ps1", "get-sha-certificates.ps1", "run-sha-script.bat")
foreach ($file in $files) {
    if (Test-Path $file) {
        Write-Host "   Сохранен: $file" -ForegroundColor Green
    }
}

# 2. Удаляем старый файл shift_employee_selection_page.dart
Write-Host "`n2. Удаляем старый файл..." -ForegroundColor Yellow
if (Test-Path "lib\shift_employee_selection_page.dart") {
    Remove-Item "lib\shift_employee_selection_page.dart" -Force
    Write-Host "   ✅ Удален: lib\shift_employee_selection_page.dart" -ForegroundColor Green
} else {
    Write-Host "   ⚠️ Файл не найден (уже удален)" -ForegroundColor Yellow
}

# 3. Убираем импорт из main_menu_page.dart
Write-Host "`n3. Убираем импорт из main_menu_page.dart..." -ForegroundColor Yellow
$content = Get-Content "lib\main_menu_page.dart" -Raw
if ($content -match "import 'shift_employee_selection_page.dart';") {
    $content = $content -replace "import 'shift_employee_selection_page\.dart';\s*\r?\n", ""
    $content | Set-Content "lib\main_menu_page.dart" -NoNewline
    Write-Host "   ✅ Импорт удален" -ForegroundColor Green
} else {
    Write-Host "   ⚠️ Импорт не найден (уже удален)" -ForegroundColor Yellow
}

# 4. Проверяем, что импорт shift_shop_selection_page есть
Write-Host "`n4. Проверяем правильный импорт..." -ForegroundColor Yellow
if ($content -match "import 'shift_shop_selection_page\.dart';") {
    Write-Host "   ✅ Правильный импорт найден" -ForegroundColor Green
} else {
    Write-Host "   ⚠️ Нужно добавить: import 'shift_shop_selection_page.dart';" -ForegroundColor Red
}

# 5. Обновляем с GitHub (stash локальные изменения)
Write-Host "`n5. Обновляем с GitHub..." -ForegroundColor Yellow
git stash push -m "Локальные файлы перед обновлением" -- fix-firebase-imports.ps1 get-sha-certificates.ps1 run-sha-script.bat
git pull origin main
git stash pop

Write-Host "`n✅ Готово! Теперь выполните:" -ForegroundColor Green
Write-Host "   flutter clean" -ForegroundColor Cyan
Write-Host "   flutter pub get" -ForegroundColor Cyan
Write-Host "   flutter run" -ForegroundColor Cyan









