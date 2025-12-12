# Инструкция по настройке Firebase Cloud Messaging (FCM) для push-уведомлений

## Обзор

Для работы push-уведомлений о новых ответах администратора на отзывы необходимо настроить Firebase Cloud Messaging (FCM).

## Шаг 1: Создание проекта Firebase

1. Перейдите на [Firebase Console](https://console.firebase.google.com/)
2. Нажмите "Добавить проект" или выберите существующий
3. Следуйте инструкциям для создания проекта

## Шаг 2: Добавление приложения Android

1. В Firebase Console выберите ваш проект
2. Нажмите на иконку Android (или "Добавить приложение")
3. Введите:
   - **Имя пакета Android**: `com.example.arabica_app` (проверьте в `android/app/build.gradle`)
   - **Псевдоним приложения** (опционально)
4. Скачайте файл `google-services.json`
5. Поместите файл в `android/app/google-services.json`

## Шаг 3: Добавление приложения iOS (если нужно)

1. В Firebase Console нажмите "Добавить приложение" → iOS
2. Введите:
   - **ID пакета**: проверьте в `ios/Runner.xcodeproj`
   - **Псевдоним приложения** (опционально)
3. Скачайте файл `GoogleService-Info.plist`
4. Поместите файл в `ios/Runner/GoogleService-Info.plist`

## Шаг 4: Установка зависимостей Flutter

Добавьте в `pubspec.yaml`:

```yaml
dependencies:
  firebase_core: ^2.24.2
  firebase_messaging: ^14.7.9
```

Затем выполните:
```bash
flutter pub get
```

## Шаг 5: Настройка Android

### 5.1. Обновите `android/build.gradle`:

```gradle
buildscript {
    dependencies {
        // Добавьте эту строку
        classpath 'com.google.gms:google-services:4.4.0'
    }
}
```

### 5.2. Обновите `android/app/build.gradle`:

В конце файла добавьте:
```gradle
apply plugin: 'com.google.gms.google-services'
```

### 5.3. Обновите минимальную версию SDK в `android/app/build.gradle`:

```gradle
android {
    defaultConfig {
        minSdkVersion 21  // FCM требует минимум 21
    }
}
```

## Шаг 6: Настройка iOS (если нужно)

### 6.1. Обновите `ios/Podfile`:

```ruby
platform :ios, '12.0'  # Минимум iOS 12.0
```

### 6.2. Выполните:

```bash
cd ios
pod install
cd ..
```

### 6.3. В Xcode откройте `ios/Runner.xcworkspace`:
- Добавьте `GoogleService-Info.plist` в проект
- Включите Push Notifications в Capabilities

## Шаг 7: Получение Server Key для сервера

1. В Firebase Console перейдите в **Настройки проекта** (⚙️)
2. Перейдите на вкладку **Облачные сообщения**
3. Скопируйте **Ключ сервера** (Server Key)
4. Сохраните его для использования на сервере

## Шаг 8: Обновление кода приложения

### 8.1. Создайте файл `lib/firebase_service.dart`:

```dart
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

class FirebaseService {
  static final FirebaseMessaging _messaging = FirebaseMessaging.instance;
  static final FlutterLocalNotificationsPlugin _localNotifications = 
      FlutterLocalNotificationsPlugin();

  /// Инициализация Firebase
  static Future<void> initialize() async {
    // Запрашиваем разрешение на уведомления
    NotificationSettings settings = await _messaging.requestPermission(
      alert: true,
      badge: true,
      sound: true,
    );

    if (settings.authorizationStatus == AuthorizationStatus.authorized) {
      print('✅ Пользователь разрешил уведомления');
    }

    // Получаем FCM токен
    String? token = await _messaging.getToken();
    print('📱 FCM Token: $token');
    
    // Сохраняем токен на сервере (нужно реализовать)
    // await _saveTokenToServer(token);

    // Обработка уведомлений в foreground
    FirebaseMessaging.onMessage.listen((RemoteMessage message) {
      print('📨 Получено сообщение: ${message.notification?.title}');
      _showLocalNotification(message);
    });

    // Обработка нажатия на уведомление
    FirebaseMessaging.onMessageOpenedApp.listen((RemoteMessage message) {
      print('👆 Уведомление открыто: ${message.data}');
      // Навигация к диалогу
    });
  }

  /// Показать локальное уведомление
  static Future<void> _showLocalNotification(RemoteMessage message) async {
    const androidDetails = AndroidNotificationDetails(
      'reviews_channel',
      'Отзывы',
      channelDescription: 'Уведомления о новых ответах на отзывы',
      importance: Importance.high,
      priority: Priority.high,
    );

    const iosDetails = DarwinNotificationDetails(
      presentAlert: true,
      presentBadge: true,
      presentSound: true,
    );

    const notificationDetails = NotificationDetails(
      android: androidDetails,
      iOS: iosDetails,
    );

    await _localNotifications.show(
      message.hashCode,
      message.notification?.title ?? 'Новый ответ',
      message.notification?.body ?? 'У вас новый ответ на отзыв',
      notificationDetails,
      payload: message.data['reviewId'],
    );
  }

  /// Сохранить токен на сервере
  static Future<void> saveTokenToServer(String? token, String phone) async {
    if (token == null) return;
    
    // TODO: Реализовать отправку токена на сервер
    // POST /api/fcm-tokens
    // { "phone": phone, "token": token }
  }
}
```

### 8.2. Обновите `lib/main.dart`:

```dart
import 'firebase_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  // Инициализация Firebase
  await Firebase.initializeApp();
  await FirebaseService.initialize();
  
  runApp(const MyApp());
}
```

## Шаг 9: Обновление сервера для отправки push-уведомлений

### 9.1. Установите зависимости на сервере:

```bash
cd /root/loyalty-proxy
npm install firebase-admin
```

### 9.2. Создайте файл `firebase-admin-config.js`:

```javascript
import admin from 'firebase-admin';
import fs from 'fs';
import path from 'path';

// Загрузите ключ сервисного аккаунта из Firebase Console
// Настройки проекта → Облачные сообщения → Создать новый ключ
const serviceAccount = JSON.parse(
  fs.readFileSync(path.join(__dirname, 'firebase-service-account-key.json'), 'utf8')
);

admin.initializeApp({
  credential: admin.credential.cert(serviceAccount),
});

export default admin;
```

### 9.3. Обновите `index.js` для отправки уведомлений:

```javascript
import admin from './firebase-admin-config.js';

// При добавлении сообщения от админа
app.post('/api/reviews/:id/messages', async (req, res) => {
  // ... существующий код ...
  
  if (sender === 'admin') {
    // Получаем FCM токен клиента из базы данных
    const clientToken = await getClientFCMToken(review.clientPhone);
    
    if (clientToken) {
      // Отправляем push-уведомление
      await admin.messaging().send({
        token: clientToken,
        notification: {
          title: 'Новый ответ на ваш отзыв',
          body: text.substring(0, 100),
        },
        data: {
          reviewId: review.id,
          type: 'review_response',
        },
      });
    }
  }
  
  // ... остальной код ...
});
```

## Шаг 10: Хранение FCM токенов

Создайте endpoint для сохранения токенов:

```javascript
// POST /api/fcm-tokens
app.post('/api/fcm-tokens', async (req, res) => {
  const { phone, token } = req.body;
  
  // Сохраните в файл или базу данных
  const tokens = loadFCMTokens();
  tokens[phone] = token;
  saveFCMTokens(tokens);
  
  res.json({ success: true });
});
```

## Проверка работы

1. Запустите приложение
2. Оставьте отзыв
3. Ответьте на отзыв от имени администратора
4. Проверьте, что клиент получил push-уведомление

## Важные замечания

- **Безопасность**: Никогда не коммитьте `google-services.json`, `GoogleService-Info.plist` и `firebase-service-account-key.json` в публичный репозиторий
- **Тестирование**: Используйте тестовые устройства для проверки уведомлений
- **Обработка ошибок**: Добавьте обработку ошибок при отправке уведомлений

## Дополнительные ресурсы

- [Firebase Cloud Messaging документация](https://firebase.google.com/docs/cloud-messaging)
- [Flutter Firebase документация](https://firebase.flutter.dev/)













