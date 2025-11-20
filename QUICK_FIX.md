# Быстрое исправление ошибки JAVA_HOME

## Проблема: PowerShell блокирует выполнение скрипта

Ошибка: `PSSecurityException: UnauthorizedAccess` означает, что выполнение скриптов отключено.

## Решение 1: Разрешить выполнение скрипта (быстро)

В PowerShell выполните:

```powershell
# Разрешить выполнение скрипта для текущей сессии
Set-ExecutionPolicy -ExecutionPolicy Bypass -Scope Process

# Теперь запустите скрипт
.\setup_java_home.ps1
```

## Решение 2: Выполнить команды вручную (рекомендуется, если не хотите менять политику)

Просто скопируйте и выполните эти команды в PowerShell:

```powershell
# 1. Установите JAVA_HOME для текущей сессии
$env:JAVA_HOME = "C:\Program Files\Android\Android Studio\jbr"
$env:PATH = "$env:JAVA_HOME\bin;$env:PATH"

# 2. Проверьте, что Java найдена
java -version

# 3. Очистите кэш Gradle (исправляет ошибку с JAR файлом)
Remove-Item -Recurse -Force $env:USERPROFILE\.gradle\caches -ErrorAction SilentlyContinue
Remove-Item -Recurse -Force $env:USERPROFILE\.gradle\daemon -ErrorAction SilentlyContinue

# 4. Очистите проект Flutter
cd C:\Users\Admin\arabica_app
flutter clean

# 5. Обновите зависимости
flutter pub get

# 6. Попробуйте собрать снова
flutter run
```

## Если путь к JDK другой

Если Android Studio установлена в другом месте, найдите JDK:

```powershell
# Проверьте эти пути:
Test-Path "C:\Program Files\Android\Android Studio\jbr"
Test-Path "C:\Program Files\JetBrains\Android Studio\jbr"
Test-Path "C:\Program Files (x86)\Android\Android Studio\jbr"

# Или найдите вручную через Android Studio:
# File -> Settings -> Build, Execution, Deployment -> Build Tools -> Gradle -> Gradle JDK
```

Затем используйте найденный путь вместо `C:\Program Files\Android\Android Studio\jbr` в команде выше.

## Постоянная установка JAVA_HOME (опционально)

Если хотите установить JAVA_HOME постоянно:

1. Нажмите `Win + R`, введите `sysdm.cpl`
2. Перейдите на вкладку "Дополнительно" → "Переменные среды"
3. В "Системные переменные" нажмите "Создать":
   - Имя: `JAVA_HOME`
   - Значение: `C:\Program Files\Android\Android Studio\jbr`
4. Найдите `PATH` → "Изменить" → "Создать" → добавьте: `%JAVA_HOME%\bin`
5. Перезапустите PowerShell/IDE

## После исправления

Проект должен собираться успешно. Если ошибка сохраняется, проверьте:

1. Правильность пути к JDK
2. Что Java версии 11 или выше установлена
3. Что кэш Gradle полностью очищен



