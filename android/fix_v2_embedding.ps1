# Скрипт для исправления ошибки Android v1 embedding
# Запустите этот скрипт в PowerShell из корня проекта

Write-Host "Очистка кэша Flutter..." -ForegroundColor Yellow
flutter clean

Write-Host "Очистка кэша Gradle..." -ForegroundColor Yellow
cd android
if (Test-Path ".gradle") {
    Remove-Item -Recurse -Force ".gradle"
    Write-Host "Удалена папка .gradle" -ForegroundColor Green
}
if (Test-Path "app\build") {
    Remove-Item -Recurse -Force "app\build"
    Write-Host "Удалена папка app\build" -ForegroundColor Green
}
if (Test-Path "build") {
    Remove-Item -Recurse -Force "build"
    Write-Host "Удалена папка build" -ForegroundColor Green
}
cd ..

Write-Host "Очистка папки build..." -ForegroundColor Yellow
if (Test-Path "build") {
    Remove-Item -Recurse -Force "build"
    Write-Host "Удалена папка build" -ForegroundColor Green
}

Write-Host "Получение зависимостей..." -ForegroundColor Yellow
flutter pub get

Write-Host "Проверка конфигурации Android..." -ForegroundColor Yellow

# Проверка MainActivity.kt
$mainActivityPath = "android\app\src\main\kotlin\com\example\arabica_app\MainActivity.kt"
if (Test-Path $mainActivityPath) {
    $content = Get-Content $mainActivityPath -Raw
    if ($content -match "FlutterActivity") {
        Write-Host "✓ MainActivity.kt использует FlutterActivity (v2)" -ForegroundColor Green
    } else {
        Write-Host "✗ MainActivity.kt НЕ использует FlutterActivity!" -ForegroundColor Red
    }
} else {
    Write-Host "✗ MainActivity.kt не найден!" -ForegroundColor Red
}

# Проверка AndroidManifest.xml
$manifestPath = "android\app\src\main\AndroidManifest.xml"
if (Test-Path $manifestPath) {
    $content = Get-Content $manifestPath -Raw
    if ($content -match 'android:value="2"') {
        Write-Host "✓ AndroidManifest.xml содержит flutterEmbedding=2" -ForegroundColor Green
    } else {
        Write-Host "✗ AndroidManifest.xml НЕ содержит flutterEmbedding=2!" -ForegroundColor Red
    }
} else {
    Write-Host "✗ AndroidManifest.xml не найден!" -ForegroundColor Red
}

Write-Host "`nГотово! Теперь выполните: flutter run" -ForegroundColor Green

