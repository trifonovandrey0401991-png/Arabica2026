# Исправление ошибки Gradle кэша

## Проблема
Ошибка: "Failed to create Jar file" в Gradle кэше

## Решение

### Шаг 1: Удаление проблемного Gradle кэша
```powershell
# Удалите проблемную папку jars-9
$gradleCache = "$env:USERPROFILE\.gradle\caches"
Remove-Item -Recurse -Force "$gradleCache\jars-9" -ErrorAction SilentlyContinue

# Также удалите другие проблемные папки
Remove-Item -Recurse -Force "$gradleCache\transforms-*" -ErrorAction SilentlyContinue
Remove-Item -Recurse -Force "$gradleCache\modules-*" -ErrorAction SilentlyContinue
```

### Шаг 2: Очистка локального Android кэша
```powershell
cd android
Remove-Item -Recurse -Force .gradle -ErrorAction SilentlyContinue
Remove-Item -Recurse -Force app\build -ErrorAction SilentlyContinue
cd ..
```

### Шаг 3: Очистка Flutter
```powershell
flutter clean
flutter pub get
```

### Шаг 4: Запуск
```powershell
flutter run
```

## Если проблема сохраняется

### Вариант 1: Полная очистка Gradle кэша
```powershell
# ВНИМАНИЕ: Это удалит весь Gradle кэш, что может замедлить первую сборку
$gradleCache = "$env:USERPROFILE\.gradle\caches"
Remove-Item -Recurse -Force $gradleCache -ErrorAction SilentlyContinue
```

### Вариант 2: Перезапуск Gradle daemon
```powershell
cd android
.\gradlew --stop
cd ..
```

### Вариант 3: Проверка прав доступа
Убедитесь, что у вас есть права на запись в папку `C:\Users\Admin\.gradle\caches`. Если нет, запустите PowerShell от имени администратора.

