# Финальное решение проблемы Gradle Jar файла

## Проблема
Ошибка: "Failed to create Jar file" в Gradle кэше, даже после очистки

## Решение (выполните ВСЕ шаги)

### Шаг 1: Завершите все процессы Java/Gradle

```powershell
# Завершите все процессы Java и Gradle
Get-Process | Where-Object { $_.ProcessName -like "*java*" -or $_.ProcessName -like "*gradle*" } | Stop-Process -Force -ErrorAction SilentlyContinue

# Подождите 2 секунды
Start-Sleep -Seconds 2
```

### Шаг 2: Удалите ВСЮ папку .gradle

```powershell
# Удалите всю папку .gradle из пользовательской директории
$gradleHome = "$env:USERPROFILE\.gradle"
if (Test-Path $gradleHome) {
    # Сначала попробуйте разблокировать все файлы
    Get-ChildItem $gradleHome -Recurse -File | ForEach-Object {
        $_.Attributes = 'Normal'
    }
    # Удалите папку
    Remove-Item -Recurse -Force $gradleHome -ErrorAction SilentlyContinue
    Write-Host "Папка .gradle удалена" -ForegroundColor Green
}
```

### Шаг 3: Установите новый путь для Gradle кэша

```powershell
# Создайте новую папку для Gradle кэша
$newGradleHome = "C:\temp\gradle-home"
New-Item -ItemType Directory -Path $newGradleHome -Force | Out-Null

# Установите переменную окружения для текущей сессии
$env:GRADLE_USER_HOME = $newGradleHome

# Установите переменную окружения постоянно
[System.Environment]::SetEnvironmentVariable('GRADLE_USER_HOME', $newGradleHome, 'User')

Write-Host "Gradle кэш будет использовать: $newGradleHome" -ForegroundColor Green
```

### Шаг 4: Очистка локального Android кэша

```powershell
cd android
Remove-Item -Recurse -Force .gradle -ErrorAction SilentlyContinue
Remove-Item -Recurse -Force app\build -ErrorAction SilentlyContinue
cd ..
```

### Шаг 5: Очистка Flutter

```powershell
flutter clean
flutter pub get
```

### Шаг 6: Запуск

```powershell
flutter run
```

## Альтернативное решение: Использование локального кэша

Если проблема сохраняется, попробуйте использовать локальный кэш Gradle:

1. Создайте файл `android/gradle.properties` (если его нет)
2. Добавьте строку:
   ```
   org.gradle.caching=false
   org.gradle.daemon=false
   org.gradle.parallel=false
   ```

3. Выполните:
   ```powershell
   flutter clean
   flutter pub get
   flutter run
   ```

## Если ничего не помогает

Попробуйте пересоздать Android структуру:

```powershell
# Создайте резервную копию
Copy-Item android android_backup -Recurse

# Удалите android папку
Remove-Item -Recurse -Force android

# Пересоздайте платформу
flutter create --platforms=android .

# Восстановите важные файлы из резервной копии:
# - AndroidManifest.xml
# - MainActivity.kt
# - build.gradle
# - google-services.json (если есть)
```




