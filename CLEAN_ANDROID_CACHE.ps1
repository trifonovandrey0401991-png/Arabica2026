# Агрессивная очистка кэша Android для исправления ошибки v1 embedding
# Запустите этот скрипт в PowerShell из корня проекта

Write-Host "=== Агрессивная очистка кэша Android ===" -ForegroundColor Cyan

# 1. Очистка Flutter
Write-Host "`n1. Очистка Flutter..." -ForegroundColor Yellow
flutter clean
if ($LASTEXITCODE -ne 0) {
    Write-Host "Ошибка при выполнении flutter clean" -ForegroundColor Red
    exit 1
}

# 2. Очистка Android кэша
Write-Host "`n2. Очистка Android кэша..." -ForegroundColor Yellow
cd android

# Удаление всех build папок
$folders = @(".gradle", "app\build", "build", "app\.cxx", "app\.externalNativeBuild")
foreach ($folder in $folders) {
    if (Test-Path $folder) {
        Write-Host "  Удаление: $folder" -ForegroundColor Gray
        Remove-Item -Recurse -Force $folder -ErrorAction SilentlyContinue
    }
}

cd ..

# 3. Очистка корневой папки build
Write-Host "`n3. Очистка корневой папки build..." -ForegroundColor Yellow
if (Test-Path "build") {
    Remove-Item -Recurse -Force "build" -ErrorAction SilentlyContinue
    Write-Host "  Удалена папка build" -ForegroundColor Green
}

# 4. Очистка глобального Gradle кэша (опционально, раскомментируйте если нужно)
# Write-Host "`n4. Очистка глобального Gradle кэша..." -ForegroundColor Yellow
# $gradleCache = "$env:USERPROFILE\.gradle\caches"
# if (Test-Path $gradleCache) {
#     Write-Host "  Удаление глобального кэша Gradle..." -ForegroundColor Gray
#     Remove-Item -Recurse -Force "$gradleCache\transforms-*" -ErrorAction SilentlyContinue
#     Remove-Item -Recurse -Force "$gradleCache\modules-*" -ErrorAction SilentlyContinue
# }

# 5. Удаление .flutter-plugins и других файлов
Write-Host "`n5. Очистка файлов Flutter..." -ForegroundColor Yellow
$files = @(".flutter-plugins", ".flutter-plugins-dependencies", ".dart_tool")
foreach ($file in $files) {
    if (Test-Path $file) {
        Remove-Item -Recurse -Force $file -ErrorAction SilentlyContinue
        Write-Host "  Удален: $file" -ForegroundColor Gray
    }
}

# 6. Получение зависимостей
Write-Host "`n6. Получение зависимостей..." -ForegroundColor Yellow
flutter pub get
if ($LASTEXITCODE -ne 0) {
    Write-Host "Ошибка при выполнении flutter pub get" -ForegroundColor Red
    exit 1
}

# 7. Проверка конфигурации
Write-Host "`n7. Проверка конфигурации Android..." -ForegroundColor Yellow

$manifestPath = "android\app\src\main\AndroidManifest.xml"
if (Test-Path $manifestPath) {
    $content = Get-Content $manifestPath -Raw
    if ($content -match 'android:value="2"') {
        Write-Host "  ✓ AndroidManifest.xml содержит flutterEmbedding=2" -ForegroundColor Green
    } else {
        Write-Host "  ✗ AndroidManifest.xml НЕ содержит flutterEmbedding=2!" -ForegroundColor Red
    }
    
    if ($content -match "FlutterActivity") {
        Write-Host "  ✓ AndroidManifest.xml содержит FlutterActivity" -ForegroundColor Green
    }
} else {
    Write-Host "  ✗ AndroidManifest.xml не найден!" -ForegroundColor Red
}

$mainActivityPath = "android\app\src\main\kotlin\com\example\arabica_app\MainActivity.kt"
if (Test-Path $mainActivityPath) {
    $content = Get-Content $mainActivityPath -Raw
    if ($content -match "FlutterActivity") {
        Write-Host "  ✓ MainActivity.kt использует FlutterActivity (v2)" -ForegroundColor Green
    } else {
        Write-Host "  ✗ MainActivity.kt НЕ использует FlutterActivity!" -ForegroundColor Red
    }
} else {
    Write-Host "  ✗ MainActivity.kt не найден!" -ForegroundColor Red
}

Write-Host "`n=== Очистка завершена ===" -ForegroundColor Cyan
Write-Host "Теперь выполните: flutter run" -ForegroundColor Green







