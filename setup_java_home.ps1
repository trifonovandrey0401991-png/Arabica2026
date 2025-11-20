# Скрипт для настройки JAVA_HOME для Flutter проекта
# Запустите этот скрипт от имени администратора для постоянной установки

Write-Host "🔍 Поиск JDK в Android Studio..." -ForegroundColor Cyan

# Возможные пути к JDK
$possiblePaths = @(
    "C:\Program Files\Android\Android Studio\jbr",
    "C:\Program Files\JetBrains\Android Studio\jbr",
    "C:\Program Files (x86)\Android\Android Studio\jbr"
)

$jdkPath = $null

foreach ($path in $possiblePaths) {
    if (Test-Path $path) {
        $javaExe = Join-Path $path "bin\java.exe"
        if (Test-Path $javaExe) {
            $jdkPath = $path
            Write-Host "✅ Найден JDK: $jdkPath" -ForegroundColor Green
            break
        }
    }
}

if (-not $jdkPath) {
    Write-Host "❌ JDK не найден в стандартных местах." -ForegroundColor Red
    Write-Host "Пожалуйста, укажите путь к JDK вручную:" -ForegroundColor Yellow
    $jdkPath = Read-Host "Введите путь к JDK (например, C:\Program Files\Android\Android Studio\jbr)"
    
    if (-not (Test-Path $jdkPath)) {
        Write-Host "❌ Указанный путь не существует!" -ForegroundColor Red
        exit 1
    }
}

# Установка JAVA_HOME для текущей сессии
$env:JAVA_HOME = $jdkPath
$env:PATH = "$jdkPath\bin;$env:PATH"

Write-Host "`n✅ JAVA_HOME установлен для текущей сессии: $jdkPath" -ForegroundColor Green

# Проверка версии Java
Write-Host "`n🔍 Проверка версии Java..." -ForegroundColor Cyan
try {
    $javaVersion = & "$jdkPath\bin\java.exe" -version 2>&1 | Select-Object -First 1
    Write-Host $javaVersion -ForegroundColor Green
} catch {
    Write-Host "⚠️ Не удалось проверить версию Java" -ForegroundColor Yellow
}

# Предложение установить постоянно
Write-Host "`n❓ Хотите установить JAVA_HOME постоянно (требуются права администратора)?" -ForegroundColor Yellow
$response = Read-Host "Введите 'y' для установки или 'n' для пропуска"

if ($response -eq 'y' -or $response -eq 'Y') {
    try {
        [System.Environment]::SetEnvironmentVariable("JAVA_HOME", $jdkPath, [System.EnvironmentVariableTarget]::Machine)
        Write-Host "✅ JAVA_HOME установлен постоянно в системных переменных" -ForegroundColor Green
        Write-Host "⚠️ Перезапустите PowerShell/IDE для применения изменений" -ForegroundColor Yellow
    } catch {
        Write-Host "❌ Не удалось установить переменную. Запустите скрипт от имени администратора." -ForegroundColor Red
    }
}

Write-Host "`n📝 Следующие шаги:" -ForegroundColor Cyan
Write-Host "1. Если вы установили JAVA_HOME постоянно, перезапустите PowerShell" -ForegroundColor White
Write-Host "2. Выполните: flutter clean" -ForegroundColor White
Write-Host "3. Выполните: flutter pub get" -ForegroundColor White
Write-Host "4. Выполните: flutter run" -ForegroundColor White



