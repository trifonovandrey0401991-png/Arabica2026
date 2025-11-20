# Полное исправление проблемы сборки

## Найденные проблемы:

1. **Несоответствие версий Java**: В `build.gradle` указана Java 17, но система использует Java 21
2. **Устаревшая версия Android Gradle Plugin**: Версия 8.1.0 имеет проблемы с Java 21 и функцией jlink
3. **Проблемная функция jlink**: `shared_preferences_android` пытается использовать jlink, который не работает с Java 21

## Внесенные исправления:

1. ✅ Изменена Java с 17 на 11 в `android/app/build.gradle` (более стабильная версия)
2. ✅ Обновлен Android Gradle Plugin с 8.1.0 до 8.2.2
3. ✅ Обновлен Gradle с 8.3 до 8.2 (совместим с AGP 8.2.2)
4. ✅ Удалены проблемные настройки из `gradle.properties`
5. ✅ Упрощен `android/build.gradle`

## Выполните следующие команды:

```powershell
# 1. Установите JAVA_HOME (если еще не установлен)
$env:JAVA_HOME = "C:\Program Files\Android\Android Studio\jbr"
$env:PATH = "$env:JAVA_HOME\bin;$env:PATH"

# 2. ПОЛНОСТЬЮ удалите кэш Gradle (это критически важно!)
Remove-Item -Recurse -Force $env:USERPROFILE\.gradle -ErrorAction SilentlyContinue

# 3. Остановите все процессы Gradle
Get-Process | Where-Object {$_.ProcessName -like "*java*" -or $_.ProcessName -like "*gradle*"} | Stop-Process -Force -ErrorAction SilentlyContinue

# 4. Перейдите в папку проекта
cd C:\Users\Admin\arabica_app

# 5. Очистите проект Flutter
flutter clean

# 6. Удалите все локальные папки build
Remove-Item -Recurse -Force build -ErrorAction SilentlyContinue
Remove-Item -Recurse -Force android\build -ErrorAction SilentlyContinue
Remove-Item -Recurse -Force android\.gradle -ErrorAction SilentlyContinue
Remove-Item -Recurse -Force android\app\build -ErrorAction SilentlyContinue

# 7. Обновите зависимости
flutter pub get

# 8. Попробуйте собрать проект
flutter run
```

## Важно:

После удаления кэша Gradle (`$env:USERPROFILE\.gradle`) Gradle скачает все зависимости заново, что может занять время, но это необходимо для исправления проблемы.

## Если проблема сохраняется:

1. Проверьте версию Java:
   ```powershell
   java -version
   ```
   Должна быть версия 11 или выше (но не обязательно 21).

2. Убедитесь, что JAVA_HOME установлен:
   ```powershell
   echo $env:JAVA_HOME
   ```

3. Попробуйте собрать с подробным выводом:
   ```powershell
   cd android
   .\gradlew assembleDebug --stacktrace
   cd ..
   ```



