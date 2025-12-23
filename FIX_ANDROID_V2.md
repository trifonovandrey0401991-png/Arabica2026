# Исправление ошибки Android v1 embedding

## Проблема
Ошибка: "Build failed due to use of deleted Android v1 embedding"

## Решение

### 1. Очистка кэша и пересборка

Выполните следующие команды в корне проекта:

```bash
flutter clean
cd android
./gradlew clean
cd ..
flutter pub get
flutter run
```

### 2. Проверка конфигурации

Убедитесь, что:

1. **MainActivity.kt** использует `FlutterActivity`:
```kotlin
package com.example.arabica_app
import io.flutter.embedding.android.FlutterActivity
class MainActivity: FlutterActivity()
```

2. **AndroidManifest.xml** содержит:
```xml
<meta-data
    android:name="flutterEmbedding"
    android:value="2" />
```

3. **build.gradle** использует правильные настройки (уже настроено)

### 3. Если проблема сохраняется

Удалите папки кэша вручную:
- `android/.gradle`
- `android/app/build`
- `build/`

Затем выполните:
```bash
flutter clean
flutter pub get
flutter run
```

