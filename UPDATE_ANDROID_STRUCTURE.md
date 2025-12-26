# Обновление Android структуры для исправления v1 embedding

## Проблема
Ошибка "Build failed due to use of deleted Android v1 embedding" может возникать из-за устаревшей структуры Android проекта.

## Решение

### Вариант 1: Обновление структуры Android (рекомендуется)

```powershell
# 1. Создайте резервную копию важных файлов
Copy-Item android\app\src\main\AndroidManifest.xml android\app\src\main\AndroidManifest.xml.backup
Copy-Item android\app\src\main\kotlin\com\example\arabica_app\MainActivity.kt android\app\src\main\kotlin\com\example\arabica_app\MainActivity.kt.backup

# 2. Обновите Android структуру (это обновит только структуру, не удалит ваши файлы)
flutter create --platforms=android .

# 3. Восстановите ваши изменения из резервной копии
Copy-Item android\app\src\main\AndroidManifest.xml.backup android\app\src\main\AndroidManifest.xml -Force
Copy-Item android\app\src\main\kotlin\com\example\arabica_app\MainActivity.kt.backup android\app\src\main\kotlin\com\example\arabica_app\MainActivity.kt -Force

# 4. Убедитесь, что AndroidManifest.xml содержит flutterEmbedding=2
# Откройте файл и проверьте наличие:
# <meta-data
#     android:name="flutterEmbedding"
#     android:value="2" />

# 5. Очистка и пересборка
flutter clean
flutter pub get
flutter run
```

### Вариант 2: Обновление Flutter (если вариант 1 не помог)

```powershell
# Обновите Flutter до последней версии
flutter upgrade

# Затем выполните вариант 1
```

### Вариант 3: Проверка плагинов

Возможно, один из плагинов все еще использует v1 embedding. Проверьте:

```powershell
# Проверьте устаревшие зависимости
flutter pub outdated

# Обновите зависимости
flutter pub upgrade
```

## Важные файлы для проверки после обновления

1. **android/app/src/main/AndroidManifest.xml** - должен содержать:
   ```xml
   <meta-data
       android:name="flutterEmbedding"
       android:value="2" />
   ```

2. **android/app/src/main/kotlin/com/example/arabica_app/MainActivity.kt** - должен содержать:
   ```kotlin
   import io.flutter.embedding.android.FlutterActivity
   class MainActivity: FlutterActivity()
   ```

3. **android/app/src/main/java/io/flutter/plugins/GeneratedPluginRegistrant.java** - должен использовать:
   ```java
   import io.flutter.embedding.engine.FlutterEngine;
   public static void registerWith(@NonNull FlutterEngine flutterEngine)
   ```




