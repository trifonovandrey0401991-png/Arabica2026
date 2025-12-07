# PowerShell скрипт для получения SHA-1 и SHA-256 сертификатов для Firebase
# Использование: 
#   powershell -ExecutionPolicy Bypass -File .\get-sha-certificates.ps1
#   или
#   Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser
#   .\get-sha-certificates.ps1

# Проверка политики выполнения
$executionPolicy = Get-ExecutionPolicy
if ($executionPolicy -eq "Restricted") {
    Write-Host "⚠️ Политика выполнения скриптов: $executionPolicy" -ForegroundColor Yellow
    Write-Host "Попробуйте выполнить:" -ForegroundColor Yellow
    Write-Host "powershell -ExecutionPolicy Bypass -File .\get-sha-certificates.ps1" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "Или разрешите выполнение скриптов для текущего пользователя:" -ForegroundColor Yellow
    Write-Host "Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser" -ForegroundColor Cyan
    Write-Host ""
    $continue = Read-Host "Продолжить выполнение? (Y/N)"
    if ($continue -ne "Y" -and $continue -ne "y") {
        exit 1
    }
}

Write-Host "╔══════════════════════════════════════════════════════════════╗" -ForegroundColor Cyan
Write-Host "║  ПОЛУЧЕНИЕ SHA-СЕРТИФИКАТОВ ДЛЯ FIREBASE                    ║" -ForegroundColor Cyan
Write-Host "╚══════════════════════════════════════════════════════════════╝" -ForegroundColor Cyan
Write-Host ""

# Поиск Java в стандартных местах
Write-Host "🔍 Поиск Java..." -ForegroundColor Yellow
$javaPaths = @(
    "C:\Program Files\Android\Android Studio\jbr",
    "C:\Program Files\Android\Android Studio\jre",
    "$env:LOCALAPPDATA\Android\Sdk\jbr",
    "$env:LOCALAPPDATA\Android\Sdk\jre",
    "C:\Program Files\Java",
    "C:\Program Files (x86)\Java"
)

$javaFound = $false
$javaPath = $null

foreach ($path in $javaPaths) {
    $keytoolPath = Join-Path $path "bin\keytool.exe"
    if (Test-Path $keytoolPath) {
        Write-Host "✅ Java найдена: $path" -ForegroundColor Green
        $javaPath = $path
        $javaFound = $true
        break
    }
}

if (-not $javaFound) {
    Write-Host "❌ Java не найдена в стандартных местах" -ForegroundColor Red
    Write-Host ""
    Write-Host "Попробуйте один из вариантов:" -ForegroundColor Yellow
    Write-Host "1. Откройте Android Studio и используйте встроенный терминал" -ForegroundColor White
    Write-Host "2. Найдите Java вручную и укажите путь:" -ForegroundColor White
    Write-Host "   Get-ChildItem 'C:\Program Files' -Recurse -Filter 'keytool.exe' -ErrorAction SilentlyContinue" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "3. Или используйте Gradle через Android Studio:" -ForegroundColor White
    Write-Host "   - Откройте проект в Android Studio" -ForegroundColor White
    Write-Host "   - Откройте панель Gradle (справа)" -ForegroundColor White
    Write-Host "   - android → Tasks → android → signingReport" -ForegroundColor White
    exit 1
}

# Установка JAVA_HOME
$env:JAVA_HOME = $javaPath
$env:PATH = "$javaPath\bin;$env:PATH"

Write-Host ""
Write-Host "🔧 Настройка JAVA_HOME: $javaPath" -ForegroundColor Green
Write-Host ""

# Проверка наличия debug.keystore
$keystorePath = "$env:USERPROFILE\.android\debug.keystore"
if (-not (Test-Path $keystorePath)) {
    Write-Host "❌ Файл debug.keystore не найден: $keystorePath" -ForegroundColor Red
    Write-Host ""
    Write-Host "Создание debug.keystore..." -ForegroundColor Yellow
    Write-Host "Это произойдет автоматически при первом запуске Flutter приложения" -ForegroundColor White
    Write-Host ""
    Write-Host "Попробуйте:" -ForegroundColor Yellow
    Write-Host "1. Запустить приложение один раз: flutter run" -ForegroundColor White
    Write-Host "2. Затем снова запустить этот скрипт" -ForegroundColor White
    exit 1
}

Write-Host "✅ Файл debug.keystore найден: $keystorePath" -ForegroundColor Green
Write-Host ""

# Получение SHA-сертификатов
Write-Host "🔐 Получение SHA-сертификатов..." -ForegroundColor Yellow
Write-Host ""

$keytoolExe = Join-Path $javaPath "bin\keytool.exe"
$result = & $keytoolExe -list -v -keystore $keystorePath -alias androiddebugkey -storepass android -keypass android 2>&1

if ($LASTEXITCODE -ne 0) {
    Write-Host "❌ Ошибка при выполнении keytool:" -ForegroundColor Red
    Write-Host $result -ForegroundColor Red
    exit 1
}

# Поиск SHA-1 и SHA-256 в выводе
$sha1 = $null
$sha256 = $null

foreach ($line in $result) {
    if ($line -match "SHA1:\s*(.+)") {
        $sha1 = $matches[1].Trim()
    }
    if ($line -match "SHA256:\s*(.+)") {
        $sha256 = $matches[1].Trim()
    }
}

Write-Host "╔══════════════════════════════════════════════════════════════╗" -ForegroundColor Green
Write-Host "║  SHA-СЕРТИФИКАТЫ НАЙДЕНЫ                                    ║" -ForegroundColor Green
Write-Host "╚══════════════════════════════════════════════════════════════╝" -ForegroundColor Green
Write-Host ""

if ($sha1) {
    Write-Host "SHA-1:" -ForegroundColor Cyan
    Write-Host $sha1 -ForegroundColor White
    Write-Host ""
} else {
    Write-Host "⚠️ SHA-1 не найден" -ForegroundColor Yellow
    Write-Host ""
}

if ($sha256) {
    Write-Host "SHA-256:" -ForegroundColor Cyan
    Write-Host $sha256 -ForegroundColor White
    Write-Host ""
} else {
    Write-Host "⚠️ SHA-256 не найден" -ForegroundColor Yellow
    Write-Host ""
}

Write-Host "╔══════════════════════════════════════════════════════════════╗" -ForegroundColor Yellow
Write-Host "║  ЧТО ДЕЛАТЬ ДАЛЬШЕ                                           ║" -ForegroundColor Yellow
Write-Host "╚══════════════════════════════════════════════════════════════╝" -ForegroundColor Yellow
Write-Host ""
Write-Host "1. Откройте Firebase Console:" -ForegroundColor White
Write-Host "   https://console.firebase.google.com/" -ForegroundColor Cyan
Write-Host ""
Write-Host "2. Выберите проект: arabica2027-6d78d" -ForegroundColor White
Write-Host ""
Write-Host "3. Перейдите:" -ForegroundColor White
Write-Host "   Project settings → General → Your apps → Android app (Arabica2027)" -ForegroundColor White
Write-Host ""
Write-Host "4. Найдите раздел 'SHA certificate fingerprints'" -ForegroundColor White
Write-Host ""
Write-Host "5. Нажмите 'Add fingerprint' и добавьте:" -ForegroundColor White
if ($sha1) {
    Write-Host "   SHA-1: $sha1" -ForegroundColor Green
}
if ($sha256) {
    Write-Host "   SHA-256: $sha256" -ForegroundColor Green
}
Write-Host ""
Write-Host "6. Сохраните изменения" -ForegroundColor White
Write-Host ""
Write-Host "7. Перезапустите приложение:" -ForegroundColor White
Write-Host "   flutter clean" -ForegroundColor Cyan
Write-Host "   flutter pub get" -ForegroundColor Cyan
Write-Host "   flutter run" -ForegroundColor Cyan
Write-Host ""

# Копирование в буфер обмена (если доступно)
if ($sha1 -or $sha256) {
    $clipboard = ""
    if ($sha1) {
        $clipboard += "SHA-1: $sha1`n"
    }
    if ($sha256) {
        $clipboard += "SHA-256: $sha256`n"
    }
    
    try {
        $clipboard | Set-Clipboard
        Write-Host "✅ SHA-сертификаты скопированы в буфер обмена" -ForegroundColor Green
    } catch {
        Write-Host "⚠️ Не удалось скопировать в буфер обмена" -ForegroundColor Yellow
    }
}

Write-Host ""

