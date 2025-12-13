# Автоматическое исправление локальных проблем с кодом пересменки
# Запустите этот скрипт после git pull если видите выбор сотрудника

Write-Host "🔧 Исправление локальных проблем..." -ForegroundColor Cyan

$errors = @()

# 1. Удаляем старый файл shift_employee_selection_page.dart
Write-Host "`n1. Проверка файла shift_employee_selection_page.dart..." -ForegroundColor Yellow
if (Test-Path "lib\shift_employee_selection_page.dart") {
    Remove-Item "lib\shift_employee_selection_page.dart" -Force
    Write-Host "   ✅ Удален: lib\shift_employee_selection_page.dart" -ForegroundColor Green
} else {
    Write-Host "   ✅ Файл не существует (правильно)" -ForegroundColor Green
}

# 2. Убираем старый импорт из main_menu_page.dart
Write-Host "`n2. Проверка импортов в main_menu_page.dart..." -ForegroundColor Yellow
$menuFile = "lib\main_menu_page.dart"
if (Test-Path $menuFile) {
    $content = Get-Content $menuFile -Raw -Encoding UTF8
    
    # Удаляем старый импорт
    if ($content -match "import\s+['\`"]shift_employee_selection_page\.dart['\`"];?\s*\r?\n") {
        $content = $content -replace "import\s+['\`"]shift_employee_selection_page\.dart['\`"];?\s*\r?\n", ""
        Write-Host "   ✅ Удален старый импорт shift_employee_selection_page" -ForegroundColor Green
    }
    
    # Проверяем наличие правильного импорта
    if (-not ($content -match "import\s+['\`"]shift_shop_selection_page\.dart['\`"]")) {
        Write-Host "   ⚠️ Отсутствует импорт shift_shop_selection_page.dart" -ForegroundColor Red
        $errors += "Отсутствует импорт shift_shop_selection_page.dart"
    } else {
        Write-Host "   ✅ Правильный импорт shift_shop_selection_page найден" -ForegroundColor Green
    }
    
    # Проверяем код пересменки
    if ($content -match "ShiftEmployeeSelectionPage") {
        Write-Host "   ❌ Найден старый код ShiftEmployeeSelectionPage!" -ForegroundColor Red
        $errors += "Найден старый код ShiftEmployeeSelectionPage"
    } else {
        Write-Host "   ✅ Старый код ShiftEmployeeSelectionPage не найден" -ForegroundColor Green
    }
    
    # Проверяем правильный код
    if ($content -match "ShiftShopSelectionPage") {
        Write-Host "   ✅ Найден правильный код ShiftShopSelectionPage" -ForegroundColor Green
    } else {
        Write-Host "   ❌ Отсутствует правильный код ShiftShopSelectionPage!" -ForegroundColor Red
        $errors += "Отсутствует правильный код ShiftShopSelectionPage"
    }
    
    # Сохраняем изменения
    $content | Set-Content $menuFile -NoNewline -Encoding UTF8
} else {
    Write-Host "   ❌ Файл main_menu_page.dart не найден!" -ForegroundColor Red
    $errors += "Файл main_menu_page.dart не найден"
}

# 3. Проверяем использование листа Работники
Write-Host "`n3. Проверка использования листа Работники..." -ForegroundColor Yellow
$employeesFile = "lib\employees_page.dart"
if (Test-Path $employeesFile) {
    $content = Get-Content $employeesFile -Raw -Encoding UTF8
    if ($content -match "Работники|sheet.*Работники") {
        Write-Host "   ⚠️ Найдено использование листа Работники" -ForegroundColor Yellow
        Write-Host "   Проверьте, что используется Лист11" -ForegroundColor Yellow
    } else {
        Write-Host "   ✅ Лист Работники не используется" -ForegroundColor Green
    }
    
    if ($content -match "Лист11|sheet=Лист11") {
        Write-Host "   ✅ Используется правильный лист Лист11" -ForegroundColor Green
    } else {
        Write-Host "   ⚠️ Не найден лист Лист11" -ForegroundColor Yellow
    }
}

# Итоги
Write-Host "`n" + ("="*50) -ForegroundColor Cyan
if ($errors.Count -eq 0) {
    Write-Host "✅ Все проверки пройдены успешно!" -ForegroundColor Green
    Write-Host "`nТеперь выполните:" -ForegroundColor Cyan
    Write-Host "   flutter clean" -ForegroundColor Yellow
    Write-Host "   flutter pub get" -ForegroundColor Yellow
    Write-Host "   flutter run" -ForegroundColor Yellow
} else {
    Write-Host "❌ Найдены проблемы:" -ForegroundColor Red
    foreach ($error in $errors) {
        Write-Host "   - $error" -ForegroundColor Red
    }
    Write-Host "`nПожалуйста, проверьте код вручную." -ForegroundColor Yellow
}
Write-Host ("="*50) -ForegroundColor Cyan











