Write-Host "🔍 Проверка файлов системы ролей..." -ForegroundColor Cyan
Write-Host ""

# Проверка наличия файлов
Write-Host "1. Проверка наличия файлов:" -ForegroundColor Yellow
if (Test-Path "lib\role_test_page.dart") {
    Write-Host "   ✅ lib/role_test_page.dart существует" -ForegroundColor Green
} else {
    Write-Host "   ❌ lib/role_test_page.dart НЕ НАЙДЕН" -ForegroundColor Red
}

if (Test-Path "lib\user_role_model.dart") {
    Write-Host "   ✅ lib/user_role_model.dart существует" -ForegroundColor Green
} else {
    Write-Host "   ❌ lib/user_role_model.dart НЕ НАЙДЕН" -ForegroundColor Red
}

if (Test-Path "lib\user_role_service.dart") {
    Write-Host "   ✅ lib/user_role_service.dart существует" -ForegroundColor Green
} else {
    Write-Host "   ❌ lib/user_role_service.dart НЕ НАЙДЕН" -ForegroundColor Red
}

Write-Host ""
Write-Host "2. Проверка импортов в main_menu_page.dart:" -ForegroundColor Yellow
$mainMenuContent = Get-Content "lib\main_menu_page.dart" -Raw -ErrorAction SilentlyContinue

if ($mainMenuContent -match "import 'role_test_page.dart';") {
    Write-Host "   ✅ Импорт role_test_page.dart найден" -ForegroundColor Green
} else {
    Write-Host "   ❌ Импорт role_test_page.dart НЕ НАЙДЕН" -ForegroundColor Red
}

if ($mainMenuContent -match "import 'user_role_model.dart';") {
    Write-Host "   ✅ Импорт user_role_model.dart найден" -ForegroundColor Green
} else {
    Write-Host "   ❌ Импорт user_role_model.dart НЕ НАЙДЕН" -ForegroundColor Red
}

if ($mainMenuContent -match "import 'user_role_service.dart';") {
    Write-Host "   ✅ Импорт user_role_service.dart найден" -ForegroundColor Green
} else {
    Write-Host "   ❌ Импорт user_role_service.dart НЕ НАЙДЕН" -ForegroundColor Red
}

Write-Host ""
Write-Host "3. Проверка кнопки 'Тест ролей':" -ForegroundColor Yellow
if ($mainMenuContent -match "Тест ролей") {
    Write-Host "   ✅ Кнопка 'Тест ролей' найдена в коде" -ForegroundColor Green
    Write-Host "   Строки с кнопкой:" -ForegroundColor Gray
    $lines = Get-Content "lib\main_menu_page.dart" -ErrorAction SilentlyContinue
    $lineNumber = 0
    foreach ($line in $lines) {
        $lineNumber++
        if ($line -match "Тест ролей") {
            Write-Host "   Строка $lineNumber : $line" -ForegroundColor Gray
        }
    }
} else {
    Write-Host "   ❌ Кнопка 'Тест ролей' НЕ НАЙДЕНА" -ForegroundColor Red
}

Write-Host ""
Write-Host "4. Проверка метода _getMenuItems():" -ForegroundColor Yellow
if ($mainMenuContent -match "_getMenuItems\(\)") {
    Write-Host "   ✅ Метод _getMenuItems() найден" -ForegroundColor Green
    Write-Host "   Вызов метода:" -ForegroundColor Gray
    $lineNumber = 0
    foreach ($line in $lines) {
        $lineNumber++
        if ($line -match "_getMenuItems") {
            Write-Host "   Строка $lineNumber : $line" -ForegroundColor Gray
        }
    }
} else {
    Write-Host "   ❌ Метод _getMenuItems() НЕ НАЙДЕН" -ForegroundColor Red
}

Write-Host ""
Write-Host "5. Проверка последних коммитов:" -ForegroundColor Yellow
try {
    $commits = git log --oneline -5 2>$null
    $roleCommits = $commits | Select-String -Pattern "role|Role"
    if ($roleCommits) {
        Write-Host "   Найдены коммиты с ролями:" -ForegroundColor Green
        $roleCommits | ForEach-Object { Write-Host "   $_" -ForegroundColor Gray }
    } else {
        Write-Host "   ⚠️ Коммиты с ролями не найдены в последних 5" -ForegroundColor Yellow
    }
} catch {
    Write-Host "   ⚠️ Не удалось проверить коммиты (git не найден или не в репозитории)" -ForegroundColor Yellow
}

Write-Host ""
Write-Host "6. Проверка статуса git:" -ForegroundColor Yellow
try {
    $status = git status --short 2>$null
    if ($status) {
        Write-Host "   ⚠️ Есть незакоммиченные изменения:" -ForegroundColor Yellow
        $status | ForEach-Object { Write-Host "   $_" -ForegroundColor Gray }
    } else {
        Write-Host "   ✅ Нет незакоммиченных изменений" -ForegroundColor Green
    }
} catch {
    Write-Host "   ⚠️ Не удалось проверить статус git" -ForegroundColor Yellow
}

Write-Host ""
Write-Host "✅ Проверка завершена!" -ForegroundColor Cyan












