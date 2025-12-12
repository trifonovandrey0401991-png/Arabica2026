# Скрипт для обновления кода и исправления проблем
# Запустите: .\FIX_AND_UPDATE.ps1

Write-Host "🔧 Обновление кода и исправление проблем..." -ForegroundColor Cyan

# 1. Сохраняем локальные файлы
Write-Host "`n1. Сохранение локальных файлов..." -ForegroundColor Yellow
$localFiles = @("fix-firebase-imports.ps1", "get-sha-certificates.ps1", "run-sha-script.bat")
foreach ($file in $localFiles) {
    if (Test-Path $file) {
        Copy-Item $file "$file.backup" -Force
        Write-Host "   ✅ Сохранен: $file" -ForegroundColor Green
    }
}

# 2. Временно удаляем конфликтующие файлы
Write-Host "`n2. Временное удаление конфликтующих файлов..." -ForegroundColor Yellow
foreach ($file in $localFiles) {
    if (Test-Path $file) {
        Remove-Item $file -Force
        Write-Host "   ✅ Временно удален: $file" -ForegroundColor Green
    }
}

# 3. Сбрасываем изменения в сгенерированных файлах Flutter
Write-Host "`n3. Сброс изменений в сгенерированных файлах..." -ForegroundColor Yellow
$flutterFiles = @(
    "linux/flutter/generated_plugin_registrant.cc",
    "linux/flutter/generated_plugin_registrant.h",
    "linux/flutter/generated_plugins.cmake",
    "macos/Flutter/GeneratedPluginRegistrant.swift",
    "pubspec.lock",
    "windows/flutter/generated_plugin_registrant.cc",
    "windows/flutter/generated_plugin_registrant.h",
    "windows/flutter/generated_plugins.cmake"
)
foreach ($file in $flutterFiles) {
    if (Test-Path $file) {
        git restore $file 2>$null
    }
}

# 4. Обновляем код с GitHub
Write-Host "`n4. Обновление кода с GitHub..." -ForegroundColor Yellow
try {
    git pull origin main
    Write-Host "   ✅ Код обновлен" -ForegroundColor Green
} catch {
    Write-Host "   ⚠️ Ошибка при обновлении: $_" -ForegroundColor Red
}

# 5. Восстанавливаем локальные файлы
Write-Host "`n5. Восстановление локальных файлов..." -ForegroundColor Yellow
foreach ($file in $localFiles) {
    if (Test-Path "$file.backup") {
        Copy-Item "$file.backup" $file -Force
        Remove-Item "$file.backup" -Force
        Write-Host "   ✅ Восстановлен: $file" -ForegroundColor Green
    }
}

# 6. Удаляем старый файл shift_employee_selection_page.dart (если еще есть)
Write-Host "`n6. Проверка старого файла..." -ForegroundColor Yellow
if (Test-Path "lib\shift_employee_selection_page.dart") {
    Remove-Item "lib\shift_employee_selection_page.dart" -Force
    Write-Host "   ✅ Удален: lib\shift_employee_selection_page.dart" -ForegroundColor Green
} else {
    Write-Host "   ✅ Файл уже удален" -ForegroundColor Green
}

# 7. Убираем старый импорт из main_menu_page.dart
Write-Host "`n7. Исправление импортов..." -ForegroundColor Yellow
$menuFile = "lib\main_menu_page.dart"
if (Test-Path $menuFile) {
    $content = Get-Content $menuFile -Raw -Encoding UTF8
    
    # Удаляем старый импорт
    $oldImport = "import\s+['\`"]shift_employee_selection_page\.dart['\`"];?\s*\r?\n"
    if ($content -match $oldImport) {
        $content = $content -replace $oldImport, ""
        $content | Set-Content $menuFile -NoNewline -Encoding UTF8
        Write-Host "   ✅ Удален старый импорт" -ForegroundColor Green
    } else {
        Write-Host "   ✅ Старый импорт не найден" -ForegroundColor Green
    }
    
    # Проверяем правильный импорт
    if ($content -match "import\s+['\`"]shift_shop_selection_page\.dart['\`"]") {
        Write-Host "   ✅ Правильный импорт найден" -ForegroundColor Green
    } else {
        Write-Host "   ⚠️ Правильный импорт не найден!" -ForegroundColor Red
    }
}

# 8. Очищаем кэш Flutter
Write-Host "`n8. Очистка кэша Flutter..." -ForegroundColor Yellow
Write-Host "   Выполните вручную: flutter clean" -ForegroundColor Cyan

# Итоги
Write-Host "`n" + ("="*50) -ForegroundColor Cyan
Write-Host "✅ Готово! Теперь выполните:" -ForegroundColor Green
Write-Host "   flutter clean" -ForegroundColor Yellow
Write-Host "   flutter pub get" -ForegroundColor Yellow
Write-Host "   flutter run" -ForegroundColor Yellow
Write-Host ("="*50) -ForegroundColor Cyan







