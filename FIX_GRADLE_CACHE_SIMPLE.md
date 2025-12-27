# Простое исправление ошибки Gradle кэша

## Проблема
Ошибка: "Failed to create Jar file" в Gradle кэше

## Решение (без использования gradlew)

### Шаг 1: Удаление проблемного Gradle кэша
```powershell
# Удалите проблемную папку jars-9
$gradleCache = "$env:USERPROFILE\.gradle\caches"
Remove-Item -Recurse -Force "$gradleCache\jars-9" -ErrorAction SilentlyContinue

# Также удалите другие проблемные папки
Get-ChildItem "$gradleCache" -Directory | Where-Object { $_.Name -like "transforms-*" } | Remove-Item -Recurse -Force -ErrorAction SilentlyContinue
Get-ChildItem "$gradleCache" -Directory | Where-Object { $_.Name -like "modules-*" } | Remove-Item -Recurse -Force -ErrorAction SilentlyContinue
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

### Полная очистка Gradle кэша
```powershell
# ВНИМАНИЕ: Это удалит весь Gradle кэш, что может замедлить первую сборку
$gradleCache = "$env:USERPROFILE\.gradle\caches"
Remove-Item -Recurse -Force $gradleCache -ErrorAction SilentlyContinue

# Затем повторите шаги 2-4
```

## Примечание
Если вы хотите установить JAVA_HOME (опционально):
```powershell
# Установите JAVA_HOME (из вывода flutter doctor видно, что Java находится здесь)
$env:JAVA_HOME = "C:\Program Files\Android\Android Studio\jbr"
[System.Environment]::SetEnvironmentVariable('JAVA_HOME', $env:JAVA_HOME, 'User')
```

Но это не обязательно для решения текущей проблемы.







