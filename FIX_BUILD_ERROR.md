# Исправление ошибки сборки Flutter

## Проблема: JAVA_HOME is not set

Ошибка возникает из-за того, что Gradle не может найти Java. Вот несколько способов решения:

## Решение 1: Установить JAVA_HOME в системе (рекомендуется)

### В PowerShell (временно для текущей сессии):
```powershell
# Проверьте, где находится JDK Android Studio
$jdkPath = "C:\Program Files\Android\Android Studio\jbr"
$env:JAVA_HOME = $jdkPath
$env:PATH = "$jdkPath\bin;$env:PATH"

# Проверьте, что Java найдена
java -version
```

### Постоянная установка через системные переменные:
1. Нажмите `Win + R`, введите `sysdm.cpl` и нажмите Enter
2. Перейдите на вкладку "Дополнительно"
3. Нажмите "Переменные среды"
4. В разделе "Системные переменные" нажмите "Создать"
5. Имя переменной: `JAVA_HOME`
6. Значение переменной: `C:\Program Files\Android\Android Studio\jbr`
7. Найдите переменную `PATH` в системных переменных
8. Нажмите "Изменить" и добавьте: `%JAVA_HOME%\bin`
9. Нажмите "ОК" во всех окнах
10. **Перезапустите PowerShell/IDE**

## Решение 2: Очистить кэш Gradle

Если проблема с созданием JAR файла, очистите кэш:

```powershell
# Остановите все процессы Gradle
Get-Process | Where-Object {$_.ProcessName -like "*java*" -or $_.ProcessName -like "*gradle*"} | Stop-Process -Force

# Удалите кэш Gradle
Remove-Item -Recurse -Force $env:USERPROFILE\.gradle\caches
Remove-Item -Recurse -Force $env:USERPROFILE\.gradle\daemon

# Очистите проект
cd C:\Users\Admin\arabica_app
flutter clean
cd android
.\gradlew clean --no-daemon
cd ..

# Обновите зависимости
flutter pub get

# Попробуйте собрать снова
flutter run
```

## Решение 3: Использовать JDK из Android Studio напрямую

Если Android Studio установлена в другом месте, найдите JDK:

```powershell
# Обычные пути к JDK в Android Studio:
# C:\Program Files\Android\Android Studio\jbr
# C:\Program Files\JetBrains\Android Studio\jbr
# Или проверьте в настройках Android Studio: File -> Settings -> Build, Execution, Deployment -> Build Tools -> Gradle -> Gradle JDK
```

Затем установите JAVA_HOME на этот путь (см. Решение 1).

## Решение 4: Проверить версию Java

Убедитесь, что установлена Java 11 или выше:

```powershell
# После установки JAVA_HOME проверьте версию
java -version
# Должно быть что-то вроде: openjdk version "11.0.x" или выше
```

## После исправления

Выполните следующие команды:

```powershell
cd C:\Users\Admin\arabica_app
flutter clean
flutter pub get
flutter run
```

## Если проблема сохраняется

1. Убедитесь, что Android Studio полностью установлена
2. Проверьте, что путь к JDK правильный
3. Перезапустите компьютер (чтобы переменные окружения точно применились)
4. Попробуйте собрать проект из Android Studio напрямую



