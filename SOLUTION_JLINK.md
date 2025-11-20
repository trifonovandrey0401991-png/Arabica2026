# Решение проблемы с jlink.exe

## Проблема
Ошибка: `Failed to transform core-for-system-modules.jar` при сборке `shared_preferences_android`.

## Решение 1: Использовать более старую версию shared_preferences

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

## Решение 2: Обновить Android Gradle Plugin

Проблема может быть в несовместимости версий. Попробуйте обновить Android Gradle Plugin до версии 8.2.0 или выше.

В `android/settings.gradle`:
```gradle
id "com.android.application" version "8.2.0" apply false
```

## Решение 3: Использовать Java 11 вместо 17

Если Java 21 вызывает проблемы, попробуйте использовать Java 11:

В `android/app/build.gradle`:
```gradle
compileOptions {
    sourceCompatibility = JavaVersion.VERSION_11
    targetCompatibility = JavaVersion.VERSION_11
}

kotlinOptions {
    jvmTarget = '11'
}
```

## Решение 4: Полная очистка и пересборка

```powershell
# 1. Установите JAVA_HOME
$env:JAVA_HOME = "C:\Program Files\Android\Android Studio\jbr"
$env:PATH = "$env:JAVA_HOME\bin;$env:PATH"

# 2. Полностью удалите кэш Gradle
Remove-Item -Recurse -Force $env:USERPROFILE\.gradle -ErrorAction SilentlyContinue

# 3. Очистите проект
cd C:\Users\Admin\arabica_app
flutter clean
Remove-Item -Recurse -Force build -ErrorAction SilentlyContinue
Remove-Item -Recurse -Force android\build -ErrorAction SilentlyContinue
Remove-Item -Recurse -Force android\.gradle -ErrorAction SilentlyContinue

# 4. Обновите зависимости
flutter pub get

# 5. Попробуйте собрать
flutter run
```

## Решение 5: Временный обходной путь

Если ничего не помогает, можно временно закомментировать использование `shared_preferences` и использовать альтернативу или хранить данные локально другим способом.



