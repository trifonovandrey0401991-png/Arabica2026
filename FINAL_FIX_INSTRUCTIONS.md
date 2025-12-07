# Финальная инструкция по исправлению Firebase

## Проблема
Ошибка: "Unsupported operation: Firebase App не доступен на этой платформе"

Это означает, что используется stub вместо реального Firebase Core.

## Решение

### Шаг 1: Исправьте импорты автоматически

Скопируйте файл `fix-firebase-imports.ps1` на ваш компьютер и выполните:

```powershell
cd C:\Users\Admin\arabica2026
powershell -ExecutionPolicy Bypass -File .\fix-firebase-imports.ps1
```

### Шаг 2: Или исправьте вручную

Проверьте и исправьте эти файлы:

#### 1. lib/firebase_wrapper.dart (строка 5)
**Должно быть:**
```dart
import 'package:firebase_core/firebase_core.dart' as firebase_core;
```

**НЕ должно быть:**
```dart
import 'firebase_core_stub.dart' as firebase_core if (dart.library.io) 'package:firebase_core/firebase_core.dart';
```

#### 2. lib/firebase_service.dart (строка 15)
**Должно быть:**
```dart
import 'package:firebase_core/firebase_core.dart' as firebase_core;
```

#### 3. lib/main.dart (строка 14)
**Должно быть:**
```dart
import 'package:firebase_core/firebase_core.dart' as firebase_core;
```

### Шаг 3: Полная очистка и пересборка

```powershell
cd C:\Users\Admin\arabica2026

# Очистка Flutter
flutter clean

# Очистка Android
cd android
.\gradlew clean
cd ..

# Обновление зависимостей
flutter pub get

# Запуск
flutter run
```

## Проверка

После исправления в логах должны появиться:
- ✅ Firebase.initializeApp() завершен успешно
- ✅ Firebase App доступен: [DEFAULT]
- ✅ Экземпляр FirebaseMessaging создан
- 📱 FCM Token получен: ...

## Если проблема сохраняется

1. Убедитесь, что SHA-сертификаты добавлены в Firebase Console
2. Проверьте, что google-services.json находится в `android/app/google-services.json`
3. Убедитесь, что все файлы сохранены после исправления
4. Попробуйте полностью удалить папку `build` и `.dart_tool`:
   ```powershell
   Remove-Item -Recurse -Force build, .dart_tool
   flutter pub get
   flutter run
   ```

