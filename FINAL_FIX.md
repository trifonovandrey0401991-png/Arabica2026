# Финальное исправление ошибки сборки

## Проблема
Ошибка с `jlink.exe` и `core-for-system-modules.jar` при сборке `shared_preferences_android`.

## Решение
Обновлены настройки для использования Java 17 (совместимо с Java 21) и добавлены настройки для отключения проблемной функции.

## Выполните следующие команды:

```powershell
# 1. Убедитесь, что JAVA_HOME установлен (если еще не установлен)
$env:JAVA_HOME = "C:\Program Files\Android\Android Studio\jbr"
$env:PATH = "$env:JAVA_HOME\bin;$env:PATH"

# 2. Полностью очистите кэш Gradle
Remove-Item -Recurse -Force $env:USERPROFILE\.gradle\caches -ErrorAction SilentlyContinue
Remove-Item -Recurse -Force $env:USERPROFILE\.gradle\daemon -ErrorAction SilentlyContinue
Remove-Item -Recurse -Force $env:USERPROFILE\.gradle\wrapper -ErrorAction SilentlyContinue

# 3. Остановите все процессы Gradle
Get-Process | Where-Object {$_.ProcessName -like "*java*" -or $_.ProcessName -like "*gradle*"} | Stop-Process -Force -ErrorAction SilentlyContinue

# 4. Перейдите в папку проекта
cd C:\Users\Admin\arabica_app

# 5. Очистите проект Flutter
flutter clean

# 6. Удалите папку build (если есть)
Remove-Item -Recurse -Force build -ErrorAction SilentlyContinue
Remove-Item -Recurse -Force android\build -ErrorAction SilentlyContinue
Remove-Item -Recurse -Force android\.gradle -ErrorAction SilentlyContinue

# 7. Обновите зависимости
flutter pub get

# 8. Попробуйте собрать проект
flutter run
```

## Если ошибка сохраняется

Попробуйте собрать с дополнительными флагами для диагностики:

```powershell
# Сборка с подробным выводом
cd android
.\gradlew assembleDebug --stacktrace --info
cd ..
```

Или попробуйте использовать другую версию Java:

```powershell
# Если у вас установлена Java 17 отдельно, используйте её
# Найдите путь к Java 17 и установите:
$env:JAVA_HOME = "C:\Program Files\Java\jdk-17"
$env:PATH = "$env:JAVA_HOME\bin;$env:PATH"
java -version
```

## Альтернативное решение

Если проблема не решается, можно временно использовать более старую версию `shared_preferences`:

В `pubspec.yaml` измените:
```yaml
shared_preferences: ^2.2.2
```

Затем:
```powershell
flutter pub get
flutter clean
flutter run
```



