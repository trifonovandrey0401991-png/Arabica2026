// Условный импорт Firebase Messaging: на веб - stub, на мобильных - реальный пакет
import 'package:firebase_messaging/firebase_messaging.dart' if (dart.library.html) 'firebase_service_stub.dart';
import 'firebase_core_stub.dart' as firebase_core if (dart.library.io) 'package:firebase_core/firebase_core.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'my_dialogs_page.dart';
import 'review_detail_page.dart';
import 'review_service.dart';
import 'review_model.dart';

/// Сервис для работы с Firebase Cloud Messaging (FCM)
class FirebaseService {
  static final FirebaseMessaging _messaging = FirebaseMessaging.instance;
  static final FlutterLocalNotificationsPlugin _localNotifications = 
      FlutterLocalNotificationsPlugin();

  static bool _initialized = false;
  static BuildContext? _globalContext;

  /// Инициализация Firebase Messaging
  static Future<void> initialize() async {
    if (_initialized) return;

    try {
      // Проверяем, что Firebase Core инициализирован
      // ignore: avoid_dynamic_calls
      try {
        // ignore: avoid_dynamic_calls
        firebase_core.Firebase.app();
      } catch (e) {
        print('⚠️ Firebase Core не инициализирован, пропускаем Firebase Messaging');
        return;
      }
      
      // Запрашиваем разрешение на уведомления
      NotificationSettings settings = await _messaging.requestPermission(
        alert: true,
        badge: true,
        sound: true,
        provisional: false,
      );

      if (settings.authorizationStatus == AuthorizationStatus.authorized) {
        print('✅ Пользователь разрешил уведомления');
      } else if (settings.authorizationStatus == AuthorizationStatus.provisional) {
        print('⚠️ Пользователь разрешил временные уведомления');
      } else {
        print('❌ Пользователь не разрешил уведомления');
        return;
      }

      // Инициализация локальных уведомлений
      const androidSettings = AndroidInitializationSettings('@mipmap/ic_launcher');
      const iosSettings = DarwinInitializationSettings(
        requestAlertPermission: true,
        requestBadgePermission: true,
        requestSoundPermission: true,
      );

      const initSettings = InitializationSettings(
        android: androidSettings,
        iOS: iosSettings,
      );

      await _localNotifications.initialize(
        initSettings,
        onDidReceiveNotificationResponse: _onNotificationTapped,
      );

      // Получаем FCM токен
      String? token = await _messaging.getToken();
      if (token != null) {
        print('📱 FCM Token получен: ${token.substring(0, 20)}...');
        await _saveTokenToServer(token);
      }

      // Обработка уведомлений в foreground (когда приложение открыто)
      FirebaseMessaging.onMessage.listen((RemoteMessage message) {
        print('📨 Получено сообщение в foreground: ${message.notification?.title}');
        _showLocalNotification(message);
      });

      // Обработка нажатия на уведомление (когда приложение в фоне)
      FirebaseMessaging.onMessageOpenedApp.listen((RemoteMessage message) {
        print('👆 Уведомление открыто из фона: ${message.data}');
        _handleNotificationTap(message);
      });

      // Обработка уведомления, которое открыло приложение (когда приложение было закрыто)
      RemoteMessage? initialMessage = await _messaging.getInitialMessage();
      if (initialMessage != null) {
        print('👆 Уведомление открыло приложение: ${initialMessage.data}');
        _handleNotificationTap(initialMessage);
      }

      // Обновление токена при его изменении
      _messaging.onTokenRefresh.listen((newToken) {
        print('🔄 FCM Token обновлен: ${newToken.substring(0, 20)}...');
        _saveTokenToServer(newToken);
      });

      _initialized = true;
      print('✅ Firebase Messaging инициализирован');
    } catch (e) {
      print('❌ Ошибка инициализации Firebase Messaging: $e');
    }
  }

  /// Установить глобальный контекст для навигации
  static void setGlobalContext(BuildContext context) {
    _globalContext = context;
  }

  /// Сохранить FCM токен на сервере
  static Future<void> _saveTokenToServer(String token) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final phone = prefs.getString('user_phone');
      
      if (phone == null || phone.isEmpty) {
        print('⚠️ Телефон не найден, токен не сохранен');
        return;
      }

      final response = await http.post(
        Uri.parse('https://arabica26.ru/api/fcm-tokens'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'phone': phone,
          'token': token,
        }),
      ).timeout(
        const Duration(seconds: 10),
        onTimeout: () {
          throw Exception('Таймаут при сохранении токена');
        },
      );

      if (response.statusCode == 200 || response.statusCode == 201) {
        print('✅ FCM токен сохранен на сервере');
      } else {
        print('⚠️ Ошибка сохранения токена: ${response.statusCode}');
      }
    } catch (e) {
      print('❌ Ошибка сохранения FCM токена: $e');
    }
  }

  /// Показать локальное уведомление
  static Future<void> _showLocalNotification(RemoteMessage message) async {
    const androidDetails = AndroidNotificationDetails(
      'reviews_channel',
      'Отзывы',
      channelDescription: 'Уведомления о новых ответах на отзывы',
      importance: Importance.high,
      priority: Priority.high,
      showWhen: true,
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
      payload: jsonEncode(message.data),
    );
  }

  /// Обработка нажатия на уведомление
  static void _onNotificationTapped(NotificationResponse response) {
    if (response.payload != null && _globalContext != null) {
      try {
        final data = jsonDecode(response.payload!) as Map<String, dynamic>;
        _handleNotificationNavigation(data);
      } catch (e) {
        print('❌ Ошибка обработки уведомления: $e');
      }
    }
  }

  /// Обработка навигации при открытии уведомления
  static void _handleNotificationTap(RemoteMessage message) {
    if (_globalContext != null) {
      _handleNotificationNavigation(message.data);
    }
  }

  /// Навигация к диалогу при открытии уведомления
  static void _handleNotificationNavigation(Map<String, dynamic> data) {
    if (_globalContext == null) return;

    final reviewId = data['reviewId'] as String?;
    if (reviewId == null) return;

    // Навигация к диалогу
    Navigator.of(_globalContext!).push(
      MaterialPageRoute(
        builder: (context) => FutureBuilder<Review?>(
          future: ReviewService.getReviewById(reviewId),
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Scaffold(
                body: Center(child: CircularProgressIndicator()),
              );
            }

            if (snapshot.hasData && snapshot.data != null) {
              return ReviewDetailPage(
                review: snapshot.data!,
                isAdmin: false,
              );
            }

            // Если отзыв не найден, переходим к списку диалогов
            return const MyDialogsPage();
          },
        ),
      ),
    );
  }
}


