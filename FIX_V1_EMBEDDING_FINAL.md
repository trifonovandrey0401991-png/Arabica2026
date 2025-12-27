# Финальное решение проблемы Android v1 embedding

## Проблема
Ошибка: "Build failed due to use of deleted Android v1 embedding"

## Решение (выполните ВСЕ шаги по порядку)

### Шаг 1: Полная очистка Flutter
```powershell
flutter clean
```

### Шаг 2: Удаление ВСЕХ Android build папок
```powershell
# Перейдите в папку android
cd android

# Удалите все возможные папки кэша
Remove-Item -Recurse -Force .gradle -ErrorAction SilentlyContinue
Remove-Item -Recurse -Force app\build -ErrorAction SilentlyContinue
Remove-Item -Recurse -Force build -ErrorAction SilentlyContinue
Remove-Item -Recurse -Force app\.cxx -ErrorAction SilentlyContinue
Remove-Item -Recurse -Force app\.externalNativeBuild -ErrorAction SilentlyContinue
Remove-Item -Recurse -Force .idea -ErrorAction SilentlyContinue

# Вернитесь в корень
cd ..
```

### Шаг 3: Удаление корневой папки build
```powershell
Remove-Item -Recurse -Force build -ErrorAction SilentlyContinue
```

### Шаг 4: Удаление файлов Flutter
```powershell
Remove-Item -Force .flutter-plugins -ErrorAction SilentlyContinue
Remove-Item -Force .flutter-plugins-dependencies -ErrorAction SilentlyContinue
Remove-Item -Recurse -Force .dart_tool -ErrorAction SilentlyContinue
```

### Шаг 5: Очистка глобального Gradle кэша
```powershell
$gradleCache = "$env:USERPROFILE\.gradle\caches"
if (Test-Path $gradleCache) {
    Remove-Item -Recurse -Force "$gradleCache\transforms-*" -ErrorAction SilentlyContinue
    Remove-Item -Recurse -Force "$gradleCache\modules-*" -ErrorAction SilentlyContinue
    Remove-Item -Recurse -Force "$gradleCache\jars-*" -ErrorAction SilentlyContinue
}
```

### Шаг 6: Проверка конфигурации
```powershell
# Проверьте AndroidManifest.xml
Select-String -Path "android\app\src\main\AndroidManifest.xml" -Pattern "flutterEmbedding.*2"

# Проверьте MainActivity.kt
Select-String -Path "android\app\src\main\kotlin\com\example\arabica_app\MainActivity.kt" -Pattern "FlutterActivity"
```

### Шаг 7: Получение зависимостей
```powershell
flutter pub get
```

### Шаг 8: Запуск
```powershell
flutter run
```

## Если проблема сохраняется

### Вариант 1: Проверка версии Flutter
```powershell
flutter --version
flutter doctor -v
```

### Вариант 2: Пересоздание Android платформы
```powershell
# Создайте резервную копию
Copy-Item -Recurse android android_backup

# Удалите android папку
Remove-Item -Recurse -Force android

# Пересоздайте платформу
flutter create --platforms=android .

# Восстановите конфигурацию из резервной копии
# Скопируйте обратно AndroidManifest.xml, MainActivity.kt и другие важные файлы
```

### Вариант 3: Проверка плагинов
Возможно, один из плагинов использует v1 embedding. Попробуйте временно удалить плагины из pubspec.yaml и проверить, работает ли сборка.

### Вариант 4: Использование старой версии Flutter
Если проблема критична, можно попробовать откатиться на более старую версию Flutter, которая поддерживает v1 embedding (но это не рекомендуется).

## Проверка правильности конфигурации

Убедитесь, что:

1. **android/app/src/main/AndroidManifest.xml** содержит:
   ```xml
   <meta-data
       android:name="flutterEmbedding"
       android:value="2" />
   ```

2. **android/app/src/main/kotlin/com/example/arabica_app/MainActivity.kt** содержит:
   ```kotlin
   import io.flutter.embedding.android.FlutterActivity
   class MainActivity: FlutterActivity()
   ```

3. **android/app/src/main/java/io/flutter/plugins/GeneratedPluginRegistrant.java** использует:
   ```java
   import io.flutter.embedding.engine.FlutterEngine;
   public static void registerWith(@NonNull FlutterEngine flutterEngine)
   ```







