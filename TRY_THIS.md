# Попробуйте это решение

## Проблема с jlink.exe

Ошибка связана с несовместимостью `shared_preferences_android` и Java 21. 

## Решение: Используйте Java 11

Попробуйте использовать Java 11 вместо Java 21. Android Studio обычно поставляется с несколькими версиями JDK.

### Шаг 1: Найдите Java 11 в Android Studio

Обычно Java 11 находится здесь:
- `C:\Program Files\Android\Android Studio\jbr` (может быть Java 11 или 17)
- Или проверьте в настройках Android Studio: File → Settings → Build, Execution, Deployment → Build Tools → Gradle → Gradle JDK

### Шаг 2: Установите Java 11 как JAVA_HOME

```powershell
# Если у вас есть Java 11 отдельно, используйте её
# Или используйте встроенную версию из Android Studio
$env:JAVA_HOME = "C:\Program Files\Android\Android Studio\jbr"
$env:PATH = "$env:JAVA_HOME\bin;$env:PATH"

# Проверьте версию (должна быть 11.x.x)
java -version
```

### Шаг 3: Измените настройки в build.gradle

В `android/app/build.gradle` уже установлено Java 17. Попробуйте изменить на Java 11:

```gradle
compileOptions {
    sourceCompatibility = JavaVersion.VERSION_11
    targetCompatibility = JavaVersion.VERSION_11
}

kotlinOptions {
    jvmTarget = '11'
}
```

### Шаг 4: Полная очистка и пересборка

```powershell
# Полностью удалите кэш Gradle
Remove-Item -Recurse -Force $env:USERPROFILE\.gradle -ErrorAction SilentlyContinue

# Очистите проект
cd C:\Users\Admin\arabica_app
flutter clean
Remove-Item -Recurse -Force build -ErrorAction SilentlyContinue
Remove-Item -Recurse -Force android\build -ErrorAction SilentlyContinue

# Обновите зависимости
flutter pub get

# Попробуйте собрать
flutter run
```

## Альтернатива: Используйте более старую версию shared_preferences

Если проблема сохраняется, можно временно использовать более старую версию:

В `pubspec.yaml`:
```yaml
shared_preferences: 2.2.0
```

Затем:
```powershell
flutter pub get
flutter clean
flutter run
```



